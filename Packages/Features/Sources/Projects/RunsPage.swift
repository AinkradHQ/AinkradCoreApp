import CoreUI
import SwiftUI

/// The Runs page (Core 0.10, E11-3), as in `Designs/core/0-10/screens/21-projects.html`: configurations, their environments,
/// the live run with its log, and the history. One run model: the project's own setup is the first configuration, the
/// "Default" (the header Start runs it, Edit Setup changes it), and its secrets are in the Environment tab. A Core older than
/// minor 95 has no run configurations, so it keeps the earlier Run page.
struct RunsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var runs: RunConfigsModel
    @State private var settled = false

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        let runs = RunConfigsModel(model: model, projectID: project.id)
        #if DEBUG
        if let t = model.demoRunTab { runs.tab = t }
        runs.selected = model.demoRunSelected
        #endif
        _runs = State(initialValue: runs)
    }

    var body: some View {
        if model.configsService == nil {
            RunPage(model: model, project: project)
        } else {
            VStack(spacing: Space.s2) {
                head
                // The tabs cross-fade; nothing slides, so the page never moves under the pointer.
                Group {
                    switch runs.tab {
                    case .configs: ConfigurationsTab(runs: runs, project: project)
                    case .environment: EnvironmentTab(runs: runs, project: project)
                    case .live: LiveRunsTab(runs: runs, project: project)
                    case .history: HistoryTab(runs: runs, project: project)
                    }
                }
                .id(runs.tab)
                .transition(.opacity)
                .animation(Motion.out(Motion.ui), value: runs.tab)
                .coreRise(settled, 0)
            }
            .onAppear { settled = true }
            // An edit made less than a second ago still saves when the page closes, and one held back by a lost connection
            // saves when the Core is back.
            .onDisappear { Task { [runs] in await runs.flushAll() } }
            .onChange(of: model.stale == nil) { _, back in if back, runs.hasPending { Task { await runs.flushAll() } } }
            .task(id: project.id) { await runs.load() }
            // The Core says a run changed: the runs are read again now.
            .task(id: model.runTick) {
                if runs.loaded {
                    await runs.refreshHistory()
                    await runs.setup.refreshRun()
                }
            }
            .task(id: runs.tab) {
                if runs.tab == .live || runs.tab == .history { await runs.watchLive() }
            }
            .accessibilityIdentifier("project-page-Run")
        }
    }

    private var head: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Runs").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Start things, control their environment, and watch them run.")
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            CoreSegmented(
                "Runs view", segments: RunConfigsModel.Tab.allCases.map { CoreSegment($0, $0.title) },
                selection: Binding(get: { runs.tab }, set: { runs.tab = $0 }))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
    }
}

/// Why an entry of a configuration is not saved, in words; nil when it is fine. A refused entry used to be dropped silently.
enum ProjectConfigFormRules {
    static func name(_ v: String) -> String? {
        v.trimmingCharacters(in: .whitespaces).isEmpty ? "Give it a name. Nothing is saved until it has one." : nil
    }
    static func command(_ v: String) -> String? {
        v.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Give it a command to run. Nothing is saved until it has one." : nil
    }
    static func port(_ v: String) -> String? {
        let t = v.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        guard let n = Int(t), (1...65535).contains(n) else {
            return "Use a port from 1 to 65535, or leave it empty. This one is not saved."
        }
        return nil
    }
}

func runsMono(_ s: String) -> some View {
    Text(s).font(.system(size: MacTextSize.body, design: .monospaced)).foregroundStyle(GlassInk.secondary)
        .lineLimit(1).truncationMode(.middle).help(s)
}

/// "started 2 minutes ago", "4 minutes ago".
func runsAgo(_ d: Date?, now: Date = Date()) -> String {
    guard let d else { return "" }
    if abs(now.timeIntervalSince(d)) < 60 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: now)
}

// MARK: Configurations

struct ConfigurationsTab: View {
    let runs: RunConfigsModel
    let project: ProjectItem
    @State private var deleting = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            list.frame(width: Space.s8 * 11)
            detail
        }
        .frame(maxHeight: .infinity)
        .coreConfirm(
            "Delete this configuration?", isPresented: $deleting,
            message: "Its variables go with it. A run that is going keeps going.", confirmTitle: "Delete",
            destructive: true
        ) {
            if let c = runs.selectedConfig { Task { await runs.remove(c.id) } }
        }
    }

    private var list: some View {
        Island(
            title: "Configurations",
            accessory: {
                Button {
                    Task { await runs.create() }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(runs.model.readOnly || runs.busy)
            }
        ) {
            if let e = runs.loadError {
                CoreNotice(symbol: "exclamationmark.triangle", title: "Unable to load", text: e, tone: .fail) {
                    Button("Try Again") { Task { await runs.load() } }.buttonStyle(
                        CoreButtonStyle(.secondary, size: .small))
                }
            } else {
                ScrollView {
                    VStack(spacing: Space.s1) {
                        CoreRow(
                            RunConfigsModel.defaultName, subtitle: runs.defaultLine, symbol: "square.stack.3d.up",
                            selected: runs.selected == nil, action: { runs.selected = nil }
                        ) {
                            if runs.defaultRun != nil { StateBadge("Running", tone: .run, symbol: "bolt") }
                        }
                        ForEach(runs.configs) { c in
                            CoreRow(
                                c.name, subtitle: c.command, symbol: "bolt", selected: runs.selectedConfig?.id == c.id,
                                action: { runs.selected = c.id }
                            ) {
                                if runs.isLive(c) { StateBadge("Running", tone: .run, symbol: "bolt") }
                            }
                            .transition(.opacity)
                        }
                        if runs.configs.isEmpty && runs.loaded {
                            Text("Add a configuration to start this project's code with its own command and environment.")
                                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.s2)
                        }
                    }
                    .animation(Motion.out(Motion.ui), value: runs.configs.map(\.id))
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let c = runs.selectedConfig {
            Island(
                title: c.name,
                accessory: {
                    Button {
                        Task { await runs.duplicate(c) }
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(runs.model.readOnly || runs.busy)
                    Button {
                        deleting = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(runs.model.readOnly || runs.busy)
                    if runs.envs.count > 1 {
                        CoreSelect(
                            nil, selection: Binding(get: { runs.runEnv }, set: { runs.runEnvChoice = $0 }),
                            options: runs.envs.map {
                                CoreSelectOption($0, $0, note: $0 == runs.defaultEnv ? "Default" : nil)
                            }
                        )
                        .frame(width: Space.s8 * 5).help("The environment Run starts in")
                    }
                    Button {
                        Task { await runs.start(c, project: project) }
                    } label: {
                        Label("Run", systemImage: "play")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: runs.busy))
                    .disabled(runs.model.readOnly || runs.busy || !runs.model.canControl(project))
                    .help("Run \(c.name) in \(runs.runEnv)")
                }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        ConfigForm(runs: runs, config: c).id(c.id)
                        if let e = runs.writeError { CoreFieldError(e) }
                        hint
                    }
                }
            }
        } else {
            DefaultDetail(runs: runs, project: project)
        }
    }

    private var hint: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Image(systemName: "info.circle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text("Uses the \(runs.envs.joined(separator: " and ")) environments.").foregroundStyle(GlassInk.secondary)
            Button("Edit environment") { runs.tab = .environment }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
    }
}

/// The fields of one configuration. They keep a local copy so typing is never fought by the Core's answer, and hand each change
/// to the model, which saves it a moment later.
private struct ConfigForm: View {
    let runs: RunConfigsModel
    let config: RunConfigItem
    @State private var name: String
    @State private var command: String
    @State private var workdir: String
    @State private var port: String

    init(runs: RunConfigsModel, config: RunConfigItem) {
        self.runs = runs
        self.config = config
        _name = State(initialValue: config.name)
        _command = State(initialValue: config.command)
        _workdir = State(initialValue: config.workdir)
        _port = State(initialValue: config.port.map(String.init) ?? "")
    }

    private var runnerOptions: [CoreSelectOption<String>] {
        var o = [CoreSelectOption("automatic", "Automatic", note: "Core picks the best runner each time")]
        o += runs.runnerOptions.map { CoreSelectOption($0.id, $0.name) }
        if config.runner != "automatic", !runs.runnerOptions.contains(where: { $0.id == config.runner }) {
            o.append(CoreSelectOption(config.runner, config.runner))
        }
        return o
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField("Name", placeholder: "Dev server", text: $name, error: ProjectConfigFormRules.name(name))
                CoreTextField(
                    "Command", placeholder: "npm run dev", text: $command,
                    error: ProjectConfigFormRules.command(command),
                    mono: true)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField("Working folder", placeholder: "./app", text: $workdir, mono: true)
                CoreSelect(
                    "Runner",
                    selection: Binding(get: { config.runner }, set: { runs.edit(config, RunConfigPatch(runner: $0)) }),
                    options: runnerOptions)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField("Port", placeholder: "None", text: $port, error: ProjectConfigFormRules.port(port))
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Restart if it stops")
                    HStack(spacing: Space.s2) {
                        CoreSwitch(
                            "",
                            isOn: Binding(
                                get: { config.restart }, set: { runs.edit(config, RunConfigPatch(restart: $0)) })
                        )
                        .accessibilityLabel("Restart if it stops")
                        Text(config.restart ? "Comes back within seconds, up to 5 times" : "Stays stopped")
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(runs.model.readOnly)
        .onChange(of: name) { _, v in if !v.isEmpty { runs.edit(config, RunConfigPatch(name: v)) } }
        .onChange(of: command) { _, v in if !v.isEmpty { runs.edit(config, RunConfigPatch(command: v)) } }
        .onChange(of: workdir) { _, v in runs.edit(config, RunConfigPatch(workdir: v)) }
        .onChange(of: port) { _, v in
            let n = Int(v.trimmingCharacters(in: .whitespaces)) ?? 0
            if v.isEmpty || (1...65535).contains(n) { runs.edit(config, RunConfigPatch(port: n)) }
        }
    }
}
