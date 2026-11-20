import Admin
import CoreKit
import Foundation
import Observation

/// What the Runs page of one project holds: its run configurations, its environments and the variables of one configuration in
/// one environment, the project's runs, and the writes. Reads go through `ProjectsModel.configsService`. A configuration's
/// fields save by themselves a moment after the last keystroke; starting and stopping run behind the host's Touch ID like every
/// other run control. A revealed value lives here only until the environment, configuration or page changes.
@MainActor @Observable
final class RunConfigsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case configs, environment, live, history
        var id: String { rawValue }
        var title: String {
            switch self {
            case .configs: "Configurations"
            case .environment: "Environment"
            case .live: "Live runs"
            case .history: "History"
            }
        }
    }

    let model: ProjectsModel
    let projectID: Int64

    var tab = Tab.configs
    private(set) var configs: [RunConfigItem] = []
    /// The configuration open in the Configurations tab.
    var selected: Int64?
    private(set) var envs: [String] = []
    /// The environment the Environment tab edits, and the configuration whose variables it shows.
    var env = ""
    var envConfig: Int64?
    private(set) var vars: [RunVarItem] = []
    private(set) var revealed: [String: String] = [:]
    var comparing = false
    var compareWith = ""
    private(set) var diff: [EnvDiffItem] = []
    private(set) var secretNames: [String] = []
    private(set) var history: [RunRecord] = []
    private(set) var runnerOptions: [RunnerOption] = []
    /// The newest log lines of each live run, by run id (the last 300 each).
    private(set) var logLines: [String: [ProjectLive.LogLine]] = [:]
    private var logNext: [String: Int] = [:]
    private(set) var loaded = false
    private(set) var loadError: String?
    private(set) var busy = false
    /// A refusal for the write in flight, in words.
    private(set) var writeError: String?
    private var pending = RunConfigPatch()
    private var saveTask: Task<Void, Never>?
    /// The environment a Run button starts in (Project Settings has the default; the first one until then).
    var runEnv: String { env.isEmpty ? (envs.first ?? "") : env }

    init(model: ProjectsModel, projectID: Int64) {
        self.model = model
        self.projectID = projectID
    }

    private var service: (any RunConfigsService)? { model.configsService }

    // MARK: derived

    var selectedConfig: RunConfigItem? { configs.first { $0.id == selected } ?? configs.first }
    var envConfigItem: RunConfigItem? { configs.first { $0.id == envConfig } ?? configs.first }
    /// Every live run, newest first: a project has one live run per configuration.
    var liveRuns: [RunRecord] { history.filter(\.live) }
    func liveRun(of config: RunConfigItem) -> RunRecord? { liveRuns.first { $0.configID == config.id } }
    func isLive(_ config: RunConfigItem) -> Bool { liveRun(of: config) != nil }
    func name(of config: Int64?) -> String { configs.first { $0.id == config }?.name ?? "Setup" }

    /// "3 variables · values are hidden", for the Environment tab.
    var varsLine: String {
        "\(ProjectItem.count(vars.count, "variable")) · values are hidden"
    }

    /// What the Compare view counts as a difference.
    var differences: Int { diff.filter { $0.change != .same }.count }

    // MARK: reads

    func load() async {
        guard let service else { return }
        do {
            configs = try await service.configs(project: projectID)
            envs = try await service.environments(project: projectID)
            secretNames = ((try? await model.runService?.secrets(project: projectID)) ?? []).map(\.name).sorted()
            if selected == nil || !configs.contains(where: { $0.id == selected }) { selected = configs.first?.id }
            if envConfig == nil || !configs.contains(where: { $0.id == envConfig }) { envConfig = configs.first?.id }
            if env.isEmpty || !envs.contains(env) { env = envs.first ?? "" }
            if compareWith.isEmpty || !envs.contains(compareWith) || compareWith == env { compareWith = other }
            history = try await service.history(project: projectID)
            runnerOptions = (try? await service.runners()) ?? []
            loadError = nil
            await loadVars()
        } catch {
            if !loaded { loadError = words(error) }
        }
        loaded = true
    }

    /// The first environment that is not the one open.
    private var other: String { envs.first { $0 != env } ?? env }

    func loadVars() async {
        revealed = [:]
        guard let service, let c = envConfigItem, !env.isEmpty else {
            vars = []
            diff = []
            return
        }
        vars = (try? await service.vars(project: projectID, config: c.id, env: env)) ?? []
        if comparing, compareWith != env {
            diff = (try? await service.diff(project: projectID, config: c.id, a: env, b: compareWith)) ?? []
        }
    }

    /// While the Live runs or History tab is open: the runs and the live run's log, every few seconds.
    func watchLive() async {
        while !Task.isCancelled {
            if let service, let h = try? await service.history(project: projectID) { history = h }
            for r in liveRuns {
                guard let page = try? await service?.logs(project: projectID, run: r.id, after: logNext[r.id] ?? 0)
                else { continue }
                logNext[r.id] = page.next
                logLines[r.id] = Array(((logLines[r.id] ?? []) + page.lines).suffix(300))
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: configurations

    func create() async {
        let taken = Set(configs.map(\.name))
        var name = "New configuration"
        var n = 2
        while taken.contains(name) {
            name = "New configuration \(n)"
            n += 1
        }
        await write { service in
            let c = try await service.createConfig(project: self.projectID, name: name, command: "echo hello")
            self.selected = c.id
            await self.load()
            self.model.host.shell.showToast(
                "Configuration added",
                undo: { Task { await self.remove(c.id, quietly: true) } })
        }
    }

    func duplicate(_ c: RunConfigItem) async {
        await write { service in
            let d = try await service.duplicateConfig(project: self.projectID, id: c.id)
            self.selected = d.id
            await self.load()
            self.model.host.shell.showToast(
                "Duplicated \(c.name)", undo: { Task { await self.remove(d.id, quietly: true) } })
        }
    }

    func remove(_ id: Int64, quietly: Bool = false) async {
        await write { service in
            try await service.deleteConfig(project: self.projectID, id: id)
            await self.load()
            if !quietly { self.model.host.shell.showToast("Configuration deleted") }
        }
    }

    /// Applies a field change at once on screen and saves it 0.8 s after the last one.
    func edit(_ c: RunConfigItem, _ change: RunConfigPatch) {
        guard let i = configs.firstIndex(where: { $0.id == c.id }) else { return }
        if let v = change.name {
            configs[i].name = v
            pending.name = v
        }
        if let v = change.command {
            configs[i].command = v
            pending.command = v
        }
        if let v = change.workdir {
            configs[i].workdir = v
            pending.workdir = v
        }
        if let v = change.runner {
            configs[i].runner = v
            pending.runner = v
        }
        if let v = change.port {
            configs[i].port = v == 0 ? nil : v
            pending.port = v
        }
        if let v = change.restart {
            configs[i].restart = v
            pending.restart = v
        }
        saveTask?.cancel()
        let id = c.id
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.flush(id)
        }
    }

    /// Saves what `edit` held back; on a refusal the page reads the Core's version again and says why.
    func flush(_ id: Int64) async {
        guard let service, model.mayWrite() else { return }
        let patch = pending
        pending = RunConfigPatch()
        guard !patch.json.isEmpty else { return }
        do {
            _ = try await service.updateConfig(project: projectID, id: id, patch)
            writeError = nil
        } catch {
            writeError = words(error)
            await load()
        }
    }

    // MARK: runs

    /// Starts `c` in the open environment. A live run of the same configuration is replaced; the others keep running.
    func start(_ c: RunConfigItem, project: ProjectItem) async {
        await flush(c.id)
        guard let service, !busy, model.mayWrite() else { return }
        busy = true
        writeError = nil
        defer { busy = false }
        let replace = isLive(c)
        do {
            _ = try await model.host.elevated(
                "Start \(c.name) of \(project.name) in \(runEnv).", done: "started", keepsEdit: true
            ) {
                try await service.start(project: projectID, config: c.id, environment: runEnv, replace: replace)
            }
            model.host.shell.showToast("Started \(c.name)")
            tab = .live
            await load()
        } catch is AdminDeclined {
        } catch {
            writeError = model.runWords(error)
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
    }

    /// Stops one live run by id, behind Touch ID.
    func stop(_ r: RunRecord, project: ProjectItem) async {
        guard let service, !busy, model.mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await model.host.elevated(
                "Stop \(name(of: r.configID)) of \(project.name).", done: "stopped", keepsEdit: true
            ) { try await service.stop(project: projectID, run: r.id) }
            model.host.shell.showToast("Stopped \(name(of: r.configID))")
            await load()
        } catch is AdminDeclined {
        } catch {
            writeError = model.runWords(error)
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
    }

    // MARK: environments

    func addEnvironment() async {
        var n = 1
        while envs.contains("Custom \(n)") { n += 1 }
        let name = "Custom \(n)"
        await write { service in
            self.envs = try await service.addEnvironment(project: self.projectID, name: name)
            self.env = name
            await self.loadVars()
            self.model.host.shell.showToast(
                "Added the \(name) environment", undo: { Task { await self.removeEnvironment(name) } })
        }
    }

    func removeEnvironment(_ name: String) async {
        await write { service in
            self.envs = try await service.deleteEnvironment(project: self.projectID, name: name)
            if self.env == name { self.env = self.envs.first ?? "" }
            await self.load()
        }
    }

    func pickEnv(_ e: String) async {
        env = e
        if compareWith == e { compareWith = other }
        await loadVars()
    }

    func pickConfig(_ id: Int64) async {
        envConfig = id
        await loadVars()
    }

    func toggleCompare() async {
        comparing.toggle()
        if comparing, compareWith == env || compareWith.isEmpty { compareWith = other }
        await loadVars()
    }

    func pickCompare(_ e: String) async {
        compareWith = e
        await loadVars()
    }

    // MARK: variables

    /// The name as the Core takes it: upper case, spaces as `_`.
    static func varName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "_")
    }

    func addVar(key: String, value: String) async -> Bool {
        let k = Self.varName(key)
        guard !k.isEmpty else {
            model.host.shell.showToast("Give the variable a name first", kind: .warn)
            return false
        }
        return await setVar(k, value: value, secret: nil, done: "Added \(k)")
    }

    func link(_ v: RunVarItem, to secret: String) async {
        _ = await setVar(v.key, value: nil, secret: secret, done: "\(v.key) now comes from Secrets")
    }

    /// Back to a plain value: the value is gone with the link, so it is empty until set again.
    func unlink(_ v: RunVarItem) async {
        _ = await setVar(v.key, value: "", secret: nil, done: "\(v.key) is a plain value now")
    }

    func setValue(_ v: RunVarItem, _ value: String) async {
        _ = await setVar(v.key, value: value, secret: nil, done: nil)
    }

    @discardableResult
    private func setVar(_ key: String, value: String?, secret: String?, done: String?) async -> Bool {
        guard let c = envConfigItem else { return false }
        var ok = false
        await write { service in
            try await service.setVar(
                project: self.projectID, config: c.id, env: self.env, key: key, value: value, secret: secret)
            await self.loadVars()
            if let done { self.model.host.shell.showToast(done) }
            ok = true
        }
        return ok
    }

    func deleteVar(_ v: RunVarItem) async {
        guard let c = envConfigItem else { return }
        await write { service in
            try await service.deleteVar(project: self.projectID, config: c.id, env: self.env, key: v.key)
            await self.loadVars()
            self.model.host.shell.showToast("Deleted \(v.key)")
        }
    }

    /// Show or hide a plain value. The value is read from the Core when shown and dropped when hidden.
    func toggleReveal(_ v: RunVarItem) async {
        if revealed[v.key] != nil {
            revealed[v.key] = nil
            return
        }
        guard let service, let c = envConfigItem, v.secret == nil else { return }
        revealed[v.key] = try? await service.reveal(project: projectID, config: c.id, env: env, key: v.key)
    }

    func importEnv(_ text: String) async -> Bool {
        guard let c = envConfigItem else { return false }
        var ok = false
        await write { service in
            let r = try await service.importEnv(project: self.projectID, config: c.id, env: self.env, text: text)
            await self.loadVars()
            let skipped = r.skipped > 0 ? ", \(r.skipped) skipped" : ""
            self.model.host.shell.showToast(
                "Imported \(ProjectItem.count(r.imported, "variable")) into \(self.env)\(skipped)")
            ok = true
        }
        return ok
    }

    func clearWriteError() { writeError = nil }

    // MARK: plumbing

    private func write(_ op: @escaping (any RunConfigsService) async throws -> Void) async {
        guard let service, !busy, model.mayWrite() else { return }
        busy = true
        writeError = nil
        defer { busy = false }
        do { try await op(service) } catch {
            writeError = words(error)
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
    }

    private func words(_ error: any Error) -> String {
        if let f = error as? RunFailure { return f.sentence }
        return model.words(error)
    }
}
