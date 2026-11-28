import CoreUI
import SwiftUI

/// The Settings focused page (details v2): two columns of blocks inside one island. Name and look, What it is (several types on
/// a Core with API 112), Running (runner, CPU, memory and idle stop save together), Link, and Archive or delete.
struct ModuleSettings: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var name: String
    @State private var description: String
    @State private var slug: String
    @State private var limitsDraft: ProjectLimits?
    @State private var runnerDraft: String?
    @State private var insights: ProjectInsightsModel
    /// The section the person worked in last: its Save is the Return key's, so only one is ever the default action.
    @State private var touched = SettingsSave.name
    /// A refusal under the section's own field, not in whichever block comes first.
    @State private var errors: [SettingsSave: String] = [:]

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.description)
        _slug = State(initialValue: project.slug)
        #if DEBUG
        _limitsDraft = State(initialValue: model.demoLimitsDraft)
        #endif
    }

    private var changed: Bool { name.trimmingCharacters(in: .whitespaces) != project.name || description != project.description }
    /// The Core's reason when the link name cannot change now (`slug_locked`); a running project is locked even on an older Core.
    private var linkLock: String? {
        SettingsSave.linkLock(project.slugLocked, running: project.tag == .running || project.tag == .starting)
    }
    private var linkLocked: Bool { linkLock != nil }
    private var defaultSection: SettingsSave {
        SettingsSave.defaultAction(
            touched: touched, showing: [
                .name: changed, .running: !runningPatch.isEmpty, .link: slug != project.slug,
            ])
    }
    private var nameProblem: String? { ProjectRules.nameProblem(name) }
    private var slugProblem: String? { slug == project.slug ? nil : ProjectRules.slugProblem(slug) }
    private var limitsNow: ProjectLimits { limitsDraft ?? project.limits }
    private var runnerNow: String { runnerDraft ?? project.runner }
    private var runningPatch: ProjectPatch { ProjectsModel.runningPatch(from: project, runner: runnerNow, limits: limitsNow) }
    private var kinds: [ProjectKind] { project.allKinds }

    var body: some View {
        ModulePage(title: "Settings", tools: { EmptyView() }) {
            ScrollView {
                HStack(alignment: .top, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: 0) {
                        nameAndLook
                        if kinds.contains(where: \.runs) { running }
                        ArchiveDeleteBlock(model: model, project: project)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        whatItIs
                        if insights.supported { fetching }
                        link
                    }
                }
                .padding(.horizontal, Space.s5).padding(.bottom, Space.s4)
            }
        }
        .task(id: project.id) { await insights.loadTuning() }
        .task { await model.loadRunners() }
        // Leaving the space (Esc, Back) asks first while there is something unsaved here.
        .onChange(of: changed || slug != project.slug || limitsDraft != nil || runnerDraft != nil, initial: true) { _, dirty in
            model.setDraft(project.id, dirty: dirty)
        }
        .onDisappear { model.setDraft(project.id, dirty: false) }
        .onChange(of: project.name) { old, new in if name == old { name = new } }
        .onChange(of: project.description) { old, new in if description == old { description = new } }
        .onChange(of: project.slug) { old, new in if slug == old { slug = new } }
        .onChange(of: name) { _, _ in touched = .name }
        .onChange(of: description) { _, _ in touched = .name }
        .onChange(of: slug) { _, _ in touched = .link }
        .onChange(of: limitsDraft) { _, _ in touched = .running }
        .onChange(of: runnerDraft) { _, _ in touched = .running }
        .onChange(of: project.limits) { _, new in if limitsDraft == new { limitsDraft = nil } }
        .onChange(of: project.runner) { _, new in if runnerDraft == new { runnerDraft = nil } }
        .accessibilityIdentifier("project-page-Settings")
    }

    // MARK: Name and look

    private var nameAndLook: some View {
        PgBlock("Name and look") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Name", placeholder: "Project name", text: $name, error: changed ? nameProblem : nil,
                    onSubmit: saveName)
                CoreTextField("Description", placeholder: "What it is, in a line", text: $description, onSubmit: saveName)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Colour")
                    ColourSwatches(
                        selection: Binding(get: { model.colour(project) }, set: { model.setColour($0, for: project) }),
                        compact: true)
                }
                if let e = errors[.name] { CoreFieldError(e) }
                saveBar(.name, show: changed, disabled: nameProblem != nil) {
                    name = project.name
                    description = project.description
                    errors[.name] = nil
                } save: { saveName() }
            }
        }
        .onChange(of: name) { _, _ in errors[.name] = nil }
    }

    private func saveName() {
        guard changed, nameProblem == nil, !model.busy else { return }
        Task {
            model.clearWriteError()
            if await model.saveGeneral(project, name: name, description: description) { errors[.name] = nil } else {
                errors[.name] = model.writeError
                model.clearWriteError()
            }
        }
    }

    private func saveLink() {
        guard slug != project.slug, slugProblem == nil, !linkLocked, !model.busy else { return }
        Task {
            model.clearWriteError()
            if await model.saveGeneral(project, name: project.name, description: project.description, slug: slug) {
                errors[.link] = nil
            } else {
                errors[.link] = model.writeError
                model.clearWriteError()
            }
        }
    }

    private func saveBar(
        _ section: SettingsSave, show: Bool, disabled: Bool, revert: @escaping () -> Void, save: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.s2) {
            if show {
                Button("Revert", action: revert).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Save", action: save).buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: model.busy))
                    .disabled(disabled || model.busy || model.readOnly)
                    .keyboardShortcut(defaultSection == section ? .defaultAction : nil)
                    .help("Saves the changes above with one Touch ID")
            }
        }
        .frame(minHeight: show ? MacSize.controlMd : 0)
        .animation(Motion.out(Motion.ui), value: show)
    }

    // MARK: What it is

    private var whatItIs: some View {
        PgBlock("What it is") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(
                    model.core112
                        ? "Pick every type that fits. The pages follow what each needs."
                        : "One type only on this Core. Update the Core to pick several."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2) {
                    ForEach(ProjectKind.allCases) { k in
                        SettingsKindTile(kind: k, on: kinds.contains(k)) { model.tapKind(k, for: project) }
                            .disabled(model.readOnly || model.busy)
                    }
                }
                if let e = model.writeError { CoreFieldError(e) }
            }
        }
    }

    // MARK: Fetching

    /// How often the Core fetches the repos by itself (the Core's own setting, per project).
    private var fetching: some View {
        PgBlock("Fetch interval") {
            VStack(alignment: .leading, spacing: Space.s2) {
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { insights.tuning.fetchInterval },
                        set: { v in Task { await insights.set(fetchInterval: v) } }),
                    options: FetchInterval.options.map { CoreSelectOption($0.minutes, $0.title) }
                )
                .disabled(model.readOnly || !insights.tuningLoaded).frame(width: Space.s8 * 5)
                PgQuiet("The Core copies each repo by itself. Fetch Now on the Code page does it at once.")
            }
        }
    }

    // MARK: Running

    private var running: some View {
        PgBlock("Running") {
            VStack(alignment: .leading, spacing: Space.s3) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
                    GridRow {
                        label("Runs on")
                        runnerChoice
                    }
                    GridRow {
                        label("CPU")
                        pick(
                            ProjectsOptions.coreChoice(limitsNow),
                            ProjectsOptions.cores.map { CoreSelectOption($0, $0 == 1 ? "1 core" : "\($0) cores") }
                        ) { n in
                            var l = limitsNow
                            l.cpus = Double(n)
                            return l
                        }
                    }
                    GridRow {
                        label("Memory")
                        pick(
                            ProjectsOptions.memoryChoice(limitsNow),
                            ProjectsOptions.memoryGB.map { CoreSelectOption($0, "\($0) GB") }
                        ) { g in
                            var l = limitsNow
                            l.memoryMb = Int64(g) * 1024
                            return l
                        }
                    }
                    GridRow {
                        label("Idle stop")
                        pick(
                            ProjectsOptions.idleChoice(limitsNow),
                            ProjectsOptions.idleChoices.map { CoreSelectOption($0.minutes, $0.title) }
                        ) { m in ProjectsOptions.setIdle(limitsNow, minutes: m) }
                    }
                    if insights.supported, !insights.environments.isEmpty {
                        GridRow {
                            label("Environment")
                            CoreSelect(
                                nil,
                                selection: Binding(
                                    get: { insights.tuning.defaultEnvironment ?? insights.environments[0] },
                                    set: { v in Task { await insights.set(defaultEnvironment: v) } }),
                                options: insights.environments.map { CoreSelectOption($0, $0) }
                            )
                            .disabled(model.readOnly).frame(width: Space.s8 * 5)
                        }
                    }
                }
                saveBar(.running, show: !runningPatch.isEmpty, disabled: false) {
                    limitsDraft = nil
                    runnerDraft = nil
                } save: {
                    let (l, r) = (limitsNow, runnerNow)
                    Task {
                        if await model.saveRunning(project, runner: r, limits: l) {
                            limitsDraft = nil
                            runnerDraft = nil
                        }
                    }
                }
            }
        }
    }

    private func label(_ s: String) -> some View { Text(s).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading) }

    private func pick(_ current: Int, _ options: [CoreSelectOption<Int>], _ make: @escaping (Int) -> ProjectLimits) -> some View {
        CoreSelect(nil, selection: Binding(get: { current }, set: { limitsDraft = make($0) }), options: options)
            .disabled(model.readOnly || model.busy).frame(width: Space.s8 * 5)
    }

    @ViewBuilder private var runnerChoice: some View {
        if model.runnerSupported {
            CoreSelect(
                nil,
                selection: Binding(
                    get: { WizardRunner(rawValue: runnerNow) ?? .auto }, set: { runnerDraft = $0.rawValue }),
                options: WizardRunner.allCases.map { CoreSelectOption($0, $0.title) }
            )
            .disabled(model.readOnly || model.busy).frame(width: Space.s8 * 5)
            .help((WizardRunner(rawValue: runnerNow) ?? .auto).line(model.runners))
        } else {
            Text(model.coreName).help("This Core keeps one place for now. Update it to choose where projects run.")
        }
    }

    // MARK: Link

    private var link: some View {
        PgBlock("Link") {
            VStack(alignment: .leading, spacing: Space.s3) {
                if kinds.contains(.web) {
                    HStack(alignment: .center, spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public link")
                            Text("Anyone with it can see the site, not your code")
                                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        CoreSwitch(
                            "",
                            isOn: Binding(get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                        )
                        .disabled(model.readOnly || model.exposing.contains(project.id)).accessibilityLabel("Public link")
                    }
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreTextField(
                        "Link name", placeholder: "atlas-notes", text: $slug, error: slugProblem ?? errors[.link],
                        onSubmit: saveLink
                    )
                    .disabled(model.readOnly || linkLocked)
                    .help(linkLock ?? "")
                    PgQuiet(linkLock ?? "\(ProjectRules.host(slug)). It can change while the project is stopped.")
                }
                saveBar(.link, show: slug != project.slug, disabled: slugProblem != nil || linkLocked) {
                    slug = project.slug
                    errors[.link] = nil
                } save: { saveLink() }
            }
        }
    }
}
