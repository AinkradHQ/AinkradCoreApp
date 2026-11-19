import AppKit
import CoreUI
import SwiftUI

/// Project Settings, laid out as in the approved mockup (`21-projects.html`): Name and colour, the public link, keeping copies
/// fresh, where it runs by default and Delete this project (a few seconds to undo).
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
            VStack(spacing: Space.s2) {
                general.coreRise(settled, 0)
                publicLink.coreRise(settled, 1)
            }
            VStack(spacing: Space.s2) {
                if insights.supported { keepFresh.coreRise(settled, 2) }
                limits.coreRise(settled, 3)
                deleteCard.coreRise(settled, 4)
            }
        }
        .onAppear { settled = true }
        .task(id: project.id) { await insights.loadTuning() }
        .onChange(of: project.name) { _, new in if !changed { name = new } }
        .accessibilityIdentifier("project-page-Project Settings")
    }

    // MARK: General

    private var general: some View {
        Island("Name and colour") {
            VStack(alignment: .leading, spacing: Space.s4) {
                CoreTextField(
                    "Name", placeholder: "Project name", text: $name, error: changed ? nameProblem : nil, onSubmit: save
                )
                CoreTextField("Description", placeholder: "What it is, in a line", text: $description, onSubmit: save)
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

    // MARK: Public link

    /// The switch, one line of words and the link with Copy, as the mockup's card.
    private var publicLink: some View {
        Island(
            title: "Public link",
            accessory: {
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                )
                .disabled(model.readOnly).accessibilityLabel("Public link")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Anyone with the link can see the project page, not your code.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    Text(project.link).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                    Spacer(minLength: 0)
                    CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("https://\(project.link)", forType: .string)
                        model.host.shell.showToast("Link copied")
                    }
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .coreCard(GlassInk.well, radius: Radius.row)
                .opacity(project.expose ? 1 : 0.45)
            }
        }
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
        Island("Where it runs by default") {
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
            }
        }
    }

    // MARK: Delete

    /// Delete this project: the Core archives it (nothing is erased) and the toast offers Undo for a few seconds. A Core without
    /// the unarchive route (older than minor 95) asks first instead, since it cannot undo.
    private var deleteCard: some View {
        Island("Delete this project") {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Removes it from Core. Your repos stay on GitHub, and you can undo for a few seconds.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if model.insightsService == nil { model.confirmArchive(project) } else { Task { await model.archive(project) } }
                } label: {
                    Label("Delete project", systemImage: "trash")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly || model.busy)
                .accessibilityIdentifier("project-delete")
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
