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
    internal(set) var envs: [String] = []
    /// The environment the Environment tab edits, and the configuration whose variables it shows.
    var env = ""
    var envConfig: Int64?
    /// `envConfig` when the Environment tab edits the Default (API 112): the project's own variables, no configuration.
    static let defaultID: Int64 = 0
    var envIsDefault: Bool { envConfig == Self.defaultID }
    internal(set) var vars: [RunVarItem] = []
    internal(set) var revealed: [String: String] = [:]
    /// Why the variables could not be read (shown with Try Again), nil when they were.
    internal(set) var varsError: String?
    var comparing = false
    var compareWith = ""
    internal(set) var diff: [EnvDiffItem] = []
    var secretNames: [String] { setup.secrets.map(\.name).sorted() }
    private(set) var history: [RunRecord] = []
    /// Why the runs could not be read just now (the list shown is the last one that was).
    private(set) var historyError: String?
    private(set) var runnerOptions: [RunnerOption] = []
    private(set) var loaded = false
    private(set) var loadError: String?
    internal(set) var busy = false
    /// A refusal for the write in flight, in words.
    internal(set) var writeError: String?
    /// What each configuration has changed and not saved yet (a second configuration's edit never rides on the first's).
    private var pending: [Int64: RunConfigPatch] = [:]
    private var saveTasks: [Int64: Task<Void, Never>] = [:]
    /// Configurations whose edits are held back because the Core could not be reached; saved when it is back.
    var hasPending: Bool { !pending.isEmpty }
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

    var service: (any RunConfigsService)? { model.configsService }

    // MARK: derived

    var selectedConfig: RunConfigItem? { configs.first { $0.id == selected } }
    var envConfigItem: RunConfigItem? { configs.first { $0.id == envConfig } ?? (envIsDefault ? nil : configs.first) }
    /// There is something to edit variables of: a configuration, or the Default on a Core that keeps its variables (API 112).
    var envReady: Bool { envIsDefault ? model.core112 : envConfigItem != nil }
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
    /// The name of what the Environment tab edits: a configuration, or the Default.
    var envOwnerName: String { envIsDefault ? Self.defaultName : envConfigItem?.name ?? "" }

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
            if envConfig == nil || (!envIsDefault && !configs.contains(where: { $0.id == envConfig })) {
                envConfig = configs.first?.id ?? (model.core112 ? Self.defaultID : nil)
            }
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

    /// The runs again. The Core says when one changes (`project.run_*`, through `ProjectsModel.runTick`), so this runs then; the
    /// slow loop below is only the safety net for a missed event.
    func refreshHistory() async {
        guard let service else { return }
        do {
            history = try await service.history(project: projectID)
            historyError = nil
        } catch { historyError = words(error) }
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

    /// Saves what `edit` held back for one configuration, behind the same Touch ID as every other write. A refusal makes the page
    /// read the Core's version again and say why; a Core that cannot be reached keeps the edit to try again when it is back.
    func flush(_ id: Int64) async {
        guard let service, model.mayWrite() else { return }
        let patch = pending[id] ?? RunConfigPatch()
        pending[id] = nil
        guard !patch.json.isEmpty else { return }
        do {
            _ = try await model.host.elevated("Change a run configuration of \(model.open?.name ?? "the project").", done: "saved", keepsEdit: true) {
                try await service.updateConfig(project: projectID, id: id, patch)
            }
            writeError = nil
        } catch is AdminDeclined {
            pending[id] = (pending[id] ?? RunConfigPatch()).filled(from: patch)
            writeError = "Not saved: Touch ID was not given. Change it again to save."
        } catch {
            if LiveProjectsService.network(error) != nil {
                pending[id] = (pending[id] ?? RunConfigPatch()).filled(from: patch)
                writeError = "Not saved yet: \(words(error)). It saves when the Core is back."
                return
            }
            writeError = words(error)
            await load()
        }
    }

    /// Saves every held-back edit now: when the page closes, and when the Core is back.
    func flushAll() async {
        for task in saveTasks.values { task.cancel() }
        saveTasks = [:]
        for id in pending.keys.sorted() { await flush(id) }
    }

    // MARK: runs

    /// Starts `c` in the open environment. A live run of the same configuration is replaced; the others keep running.
    /// `environment` is the one a past run used (Build Again, Run again); it falls back to the one picked when that is gone.
    func start(_ c: RunConfigItem, project: ProjectItem, environment: String? = nil) async {
        await flush(c.id)
        let runEnv = environment.flatMap { envs.contains($0) ? $0 : nil } ?? self.runEnv
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
        if id == Self.defaultID { comparing = false }
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

    func clearWriteError() { writeError = nil }

    // MARK: plumbing

    func write(
        _ why: String = "Change the run setup of this project.", _ op: @escaping (any RunConfigsService) async throws -> Void
    ) async {
        guard let service, !busy, model.mayWrite() else { return }
        busy = true
        writeError = nil
        defer { busy = false }
        do {
            try await model.host.elevated(why, done: "saved", keepsEdit: true) { try await op(service) }
        } catch is AdminDeclined {
        } catch {
            writeError = words(error)
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
    }

    func words(_ error: any Error) -> String {
        if let f = error as? RunFailure { return f.sentence }
        return model.words(error)
    }
}
