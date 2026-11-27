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
    /// The configuration open in the Configurations tab; nil is the Default, the project's own run setup.
    var selected: Int64?
    /// The Default's setup (the newest run spec, what the header Start runs) and the project's secrets: Edit Setup and the
    /// Secrets list of the Environment tab write through this one (secrets belong to the project, not to one environment).
    let setup: RunPageModel
    private(set) var envs: [String] = []
    /// The environment the Environment tab edits, and the configuration whose variables it shows.
    var env = ""
    var envConfig: Int64?
    private(set) var vars: [RunVarItem] = []
    private(set) var revealed: [String: String] = [:]
    var comparing = false
    var compareWith = ""
    private(set) var diff: [EnvDiffItem] = []
    var secretNames: [String] { setup.secrets.map(\.name).sorted() }
    private(set) var history: [RunRecord] = []
    private(set) var runnerOptions: [RunnerOption] = []
    private(set) var loaded = false
    private(set) var loadError: String?
    private(set) var busy = false
    /// A refusal for the write in flight, in words.
    private(set) var writeError: String?
    /// What each configuration has changed and not saved yet (a second configuration's edit never rides on the first's).
    private var pending: [Int64: RunConfigPatch] = [:]
    private var saveTasks: [Int64: Task<Void, Never>] = [:]
    /// The project's default environment (Project Settings), when it names one that exists.
    private(set) var defaultEnv: String?
    /// The environment the person picked next to Run, until the page closes.
    var runEnvChoice: String?
    /// The environment a Run button starts in: the one picked next to it, else the project's default, else the first.
    var runEnv: String {
        if let c = runEnvChoice, envs.contains(c) { return c }
        if let d = defaultEnv, envs.contains(d) { return d }
        return envs.first ?? ""
    }

    init(model: ProjectsModel, projectID: Int64) {
        self.model = model
        self.projectID = projectID
        setup = RunPageModel(model: model, projectID: projectID)
    }

    private var service: (any RunConfigsService)? { model.configsService }

    // MARK: derived

    var selectedConfig: RunConfigItem? { configs.first { $0.id == selected } }
    var envConfigItem: RunConfigItem? { configs.first { $0.id == envConfig } ?? configs.first }
    /// Every live run, newest first: a project has one live run per configuration.
    var liveRuns: [RunRecord] { history.filter(\.live) }
    func liveRun(of config: RunConfigItem) -> RunRecord? { liveRuns.first { $0.configID == config.id } }
    func isLive(_ config: RunConfigItem) -> Bool { liveRun(of: config) != nil }
    /// The live run of the Default: a run the project's own setup started, with no configuration.
    var defaultRun: RunRecord? { liveRuns.first { $0.configID == nil } }
    func name(of config: Int64?) -> String {
        config == nil ? Self.defaultName : configs.first { $0.id == config }?.name ?? "A deleted configuration"
    }
    static let defaultName = "Default"
    /// Under the Default's name in the list: what its setup runs.
    var defaultLine: String {
        guard let spec = setup.spec, !spec.services.isEmpty else { return setup.loaded ? "Not set up yet" : "" }
        return ProjectItem.count(spec.services.count, "service")
    }

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
            if let s = selected, !configs.contains(where: { $0.id == s }) { selected = nil }
            await setup.load()
            if envConfig == nil || !configs.contains(where: { $0.id == envConfig }) { envConfig = configs.first?.id }
            defaultEnv = (try? await model.insightsService?.tuning(project: projectID))?.defaultEnvironment
            if env.isEmpty || !envs.contains(env) { env = runEnv }
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

    /// The runs again. The Core says when one changes (`project.run_*`, through `ProjectsModel.runTick`), so this runs then; the
    /// slow loop below is only the safety net for a missed event.
    func refreshHistory() async {
        if let service, let h = try? await service.history(project: projectID) { history = h }
    }

    /// While the Live runs or History tab is open: the runs every half minute, and at once when the Core says one changed.
    func watchLive() async {
        while !Task.isCancelled {
            await refreshHistory()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// The project's run crashed until the Core stopped restarting it.
    var crashLoop: Bool { CrashLoop.detect(history, now: model.now()) }

    /// The runner's name for a run's runner id.
    func runnerName(_ id: String) -> String {
        runnerOptions.first { $0.id == id }?.name ?? model.runnerNames[id] ?? id
    }

    /// The Core's log of a run, read live (the stream while the device has sockets to spare, else every 3 s).
    func logs(of run: RunRecord, stream: Bool) -> RunLogsModel? {
        guard let source = model.logSources(projectID, run.id) else { return nil }
        let m = RunLogsModel(source: source)
        m.useStream = stream
        return m
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

    /// Applies a field change at once on screen and saves it 0.8 s after the last one of that configuration.
    func edit(_ c: RunConfigItem, _ change: RunConfigPatch) {
        guard let i = configs.firstIndex(where: { $0.id == c.id }) else { return }
        var p = pending[c.id] ?? RunConfigPatch()
        if let v = change.name {
            configs[i].name = v
            p.name = v
        }
        if let v = change.command {
            configs[i].command = v
            p.command = v
        }
        if let v = change.workdir {
            configs[i].workdir = v
            p.workdir = v
        }
        if let v = change.runner {
            configs[i].runner = v
            p.runner = v
        }
        if let v = change.port {
            configs[i].port = v == 0 ? nil : v
            p.port = v
        }
        if let v = change.restart {
            configs[i].restart = v
            p.restart = v
        }
        pending[c.id] = p
        saveTasks[c.id]?.cancel()
        let id = c.id
        saveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.flush(id)
        }
    }

    /// Saves what `edit` held back for one configuration; on a refusal the page reads the Core's version again and says why.
    func flush(_ id: Int64) async {
        guard let service, model.mayWrite() else { return }
        let patch = pending[id] ?? RunConfigPatch()
        pending[id] = nil
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

    /// Starts the Default: the project's own setup, which is what the header Start runs (the Core's `run/start`; a live Default is
    /// restarted). The Core lays no environment over it, only a configuration gets one.
    func startDefault(_ project: ProjectItem) async {
        let action: RunAction = defaultRun == nil ? .start : .restart
        #if DEBUG
        if model.demoPage { model.control(action, project) } else { await model.runControl(action, project) }
        #else
        await model.runControl(action, project)
        #endif
        tab = .live
        await load()
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
        do {
            revealed[v.key] = try await service.reveal(project: projectID, config: c.id, env: env, key: v.key)
        } catch {
            let why = words(error)
            writeError = "Could not show \(v.key): \(why)"
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
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
