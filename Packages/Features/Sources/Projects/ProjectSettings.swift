import CoreUI
import SwiftUI

/// Project Settings: General (name, description, link, colour) beside Run limits and Archive, as in the approved mockup.
///
/// What the Core lets change today decides what is editable: `PATCH /projects/{id}` takes the name and description only, so
/// the link name and the limits are shown, not edited (TODO(core): link and limit fields on `UpdateProject`). The colour is a
/// choice of this Mac (`ProjectColours`). TODO(design-system): proposal CoreSwatch for the colour row.
struct SettingsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var name: String
    @State private var description: String
    @State private var settled = false
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.description)
    }

    private var changed: Bool {
        name.trimmingCharacters(in: .whitespaces) != project.name || description != project.description
    }
    private var nameProblem: String? { ProjectRules.nameProblem(name) }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            general.coreRise(settled, 0).frame(width: Space.s8 * 18)
            VStack(spacing: Space.s2) {
                if insights.supported { keepFresh.coreRise(settled, 1) }
                limits.coreRise(settled, 2)
            }
        }
        .onAppear { settled = true }
        .task(id: project.id) { await insights.loadTuning() }
        .onChange(of: project.name) { _, new in if !changed { name = new } }
        .accessibilityIdentifier("project-page-Project Settings")
    }

    // MARK: General

    private var general: some View {
        Island("General") {
            VStack(alignment: .leading, spacing: Space.s4) {
                CoreTextField(
                    "Name", placeholder: "Project name", text: $name, error: changed ? nameProblem : nil, onSubmit: save
                )
                CoreTextField("Description", placeholder: "What it is, in a line", text: $description, onSubmit: save)
                CoreTextField(
                    "Public link", placeholder: "link-name", text: .constant(project.slug),
                    suffix: ".\(ProjectRules.domain)"
                )
                .disabled(true).help("The link name is fixed once the project exists")
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Colour")
                    CoreSegmented(
                        "Colour", segments: ProjectColour.allCases.map { CoreSegment($0, $0.title) },
                        selection: Binding(
                            get: { model.colour(project) }, set: { model.setColour($0, for: project) })
                    )
                    .fixedSize()
                }
                if let e = model.writeError { CoreFieldError(e) }
                if changed {
                    HStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        Button("Revert") {
                            name = project.name
                            description = project.description
                            model.clearWriteError()
                        }
                        .buttonStyle(CoreButtonStyle(.secondary))
                        Button("Save") { save() }
                            .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy))
                            .disabled(nameProblem != nil || model.busy || model.readOnly)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .onChange(of: name) { _, _ in model.clearWriteError() }
    }

    private func save() {
        guard changed, nameProblem == nil, !model.busy else { return }
        Task { await model.saveGeneral(project, name: name, description: description) }
    }

    // MARK: Keep copies fresh

    /// How often the Core fetches the repos by itself (the Core's own setting, per project).
    private var keepFresh: some View {
        Island("Keep copies fresh") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreSelect(
                    "Fetch new changes",
                    selection: Binding(
                        get: { insights.tuning.fetchInterval }, set: { v in Task { await insights.set(fetchInterval: v) } }),
                    options: FetchInterval.options.map { CoreSelectOption($0.minutes, $0.title) })
                    .disabled(model.readOnly || !insights.tuningLoaded)
                Text("The Core copies each repo by itself; Fetch Now on the Code page does it at once.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Run limits

    private var limits: some View {
        Island("Where it runs") {
            VStack(alignment: .leading, spacing: Space.s6) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
                    GridRow {
                        label("Runs on")
                        HStack(spacing: Space.s2) {
                            Text(model.coreName)
                            // TODO(core): more than one machine to run on; the Core runs projects on itself today.
                            Button("Change…") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(true)
                                .help("Only \(model.coreName) can run projects for now")
                        }
                    }
                    if insights.supported, !insights.environments.isEmpty {
                        GridRow {
                            label("Default environment")
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
                    GridRow {
                        label("CPU")
                        Text("up to \(Self.cpus(project.cpuLimit))")
                    }
                    GridRow {
                        label("Memory")
                        Text("up to \(Self.memory(project.memLimitMb))")
                    }
                    GridRow {
                        label("Idle stop")
                        HStack(spacing: Space.s2) {
                            Text("after \(project.idleMinutes) min with no visits")
                            if let idle = project.live?.idle, project.tag == .running {
                                Text("· \(idle)").foregroundStyle(GlassInk.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                archive
            }
        }
    }

    private var archive: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Archive").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
            HStack(alignment: .center, spacing: Space.s4) {
                Text("Stops the run and hides the project. Repos, secrets and the Brain room are kept.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Archive Project…") { model.confirmArchive(project) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
    }

    /// "2 CPUs", "1.5 CPUs", "1 CPU".
    static func cpus(_ n: Double) -> String {
        let t = n == n.rounded() ? String(Int(n)) : String(n)
        return "\(t) CPU\(n == 1 ? "" : "s")"
    }

    /// "2 GB", "512 MB".
    static func memory(_ mb: Int64) -> String {
        guard mb >= 1024 else { return "\(mb) MB" }
        let gb = Double(mb) / 1024
        return gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)
    }
}
