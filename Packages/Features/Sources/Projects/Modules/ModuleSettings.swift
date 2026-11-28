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

    private var changed: Bool {
        name.trimmingCharacters(in: .whitespaces) != project.name || description != project.description || slug != project.slug
    }
    private var linkLocked: Bool { project.tag == .running || project.tag == .starting }
    private var nameProblem: String? { ProjectRules.nameProblem(name) }
    private var slugProblem: String? { slug == project.slug ? nil : ProjectRules.slugProblem(slug) }
    private var limitsNow: ProjectLimits { limitsDraft ?? project.limits }
    private var runnerNow: String { runnerDraft ?? project.runner }
    private var runningPatch: ProjectPatch { ProjectsModel.runningPatch(from: project, runner: runnerNow, limits: limitsNow) }
    private var kinds: [ProjectKind] { project.allKinds }

    var body: some View {
        Island("Settings") {
            ScrollView {
                HStack(alignment: .top, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: 0) {
                        nameAndLook
                        if kinds.contains(where: \.runs) { running }
                        ArchiveDeleteBlock(model: model, project: project)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        whatItIs
                        link
                    }
                }
                .padding(.bottom, Space.s4)
            }
        }
        .task(id: project.id) { await insights.loadTuning() }
        .task { await model.loadRunners() }
        .onChange(of: project.name) { old, new in if name == old { name = new } }
        .onChange(of: project.description) { old, new in if description == old { description = new } }
        .onChange(of: project.slug) { old, new in if slug == old { slug = new } }
        .onChange(of: project.limits) { _, new in if limitsDraft == new { limitsDraft = nil } }
        .onChange(of: project.runner) { _, new in if runnerDraft == new { runnerDraft = nil } }
        .accessibilityIdentifier("project-page-Settings")
    }

    // MARK: Name and look

    private var nameAndLook: some View {
        PgBlock("Name and look") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField(
                    "Name", placeholder: "Project name", text: $name, error: changed ? nameProblem : nil, onSubmit: save)
                CoreTextField("Description", placeholder: "What it is, in a line", text: $description, onSubmit: save)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Colour")
                    ColourSwatches(
                        selection: Binding(get: { model.colour(project) }, set: { model.setColour($0, for: project) }),
                        compact: true)
                }
                if let e = model.writeError { CoreFieldError(e) }
                saveBar(show: changed, disabled: nameProblem != nil || slugProblem != nil) {
                    name = project.name
                    description = project.description
                    slug = project.slug
                    model.clearWriteError()
                } save: { save() }
            }
        }
        .onChange(of: name) { _, _ in model.clearWriteError() }
    }

    private func save() {
        guard changed, nameProblem == nil, slugProblem == nil, !model.busy else { return }
        Task { await model.saveGeneral(project, name: name, description: description, slug: slug) }
    }

    private func saveBar(show: Bool, disabled: Bool, revert: @escaping () -> Void, save: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s2) {
            if show {
                Spacer(minLength: 0)
                Button("Revert", action: revert).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Save", action: save).buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: model.busy))
                    .disabled(disabled || model.busy || model.readOnly).keyboardShortcut(.defaultAction)
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
                saveBar(show: !runningPatch.isEmpty, disabled: false) {
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
                    CoreTextField("Link name", placeholder: "atlas-notes", text: $slug, error: slugProblem, onSubmit: save)
                        .disabled(model.readOnly || linkLocked)
                        .help(linkLocked ? "Stop the project to change its link name." : "")
                    PgQuiet(
                        linkLocked
                            ? "Stop the project to change its link name."
                            : "\(ProjectRules.host(slug)). It can change while the project is stopped.")
                }
                saveBar(show: slug != project.slug, disabled: slugProblem != nil || nameProblem != nil) {
                    slug = project.slug
                } save: { save() }
            }
        }
    }
}
