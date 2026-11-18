import CoreUI
import Shell
import SwiftUI

/// The dialogs of Projects, shown over the shell like the other apps' dialogs.
@MainActor
enum NewProjectDialogs {
    static func openAdvanced(_ m: ProjectsModel, name: String, picked: Set<String> = []) {
        m.quickOpen = false
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "project-new", onClose: { [weak m] in m?.clearWriteError() }) {
                NewProjectSheet(model: m, name: name, picked: picked) { shell.closeDialog() }
            })
    }

    static func openAddRepos(_ m: ProjectsModel, _ p: ProjectItem, picked: Set<String> = []) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "project-add-repos", onClose: { [weak m] in m?.clearWriteError() }) {
                AddReposSheet(model: m, project: p, picked: picked) { shell.closeDialog() }
            })
    }
}

/// A dialog's own header: the title and one plain line under it (no icon tile).
struct DialogHead: View {
    let title: String
    let line: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let line { Text(line).foregroundStyle(palette.text2) }
        }
    }
}

/// What a new project will make, in one line each: the Brain room and the link.
private func promise(_ name: String, _ link: String?) -> AttributedString {
    let t = name.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, let link else {
        return AttributedString("Creates a Brain room and a link from the name. Add repos next.")
    }
    var out = AttributedString("Creates the Brain room “\(t)” and the link ")
    var l = AttributedString(link)
    l.font = .system(size: MacTextSize.body, design: .monospaced)
    out += l
    out += AttributedString(". Add repos next.")
    return out
}

/// ⌘N: a small pop-over under the New Project button. A name and Return is all it asks; it says what it will create.
struct QuickNewProject: View {
    let model: ProjectsModel
    @Environment(\.corePalette) private var palette

    private var slug: String { ProjectRules.slug(from: model.quickName) }
    private var typed: Bool { !model.quickName.trimmingCharacters(in: .whitespaces).isEmpty }
    /// The problem to show: the Core's refusal, else what is wrong with the name (only once something is typed).
    private var problem: String? {
        if let e = model.writeError { return e }
        guard typed else { return nil }
        return ProjectRules.nameProblem(model.quickName) ?? ProjectRules.slugProblem(slug)
    }
    private var ready: Bool {
        typed && ProjectRules.nameProblem(model.quickName) == nil && ProjectRules.slugProblem(slug) == nil
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 12) {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "New Project", line: nil)
                CoreTextField(
                    "Name", placeholder: "Project name",
                    text: Binding(get: { model.quickName }, set: { model.quickName = $0 }), error: problem,
                    autofocus: true, onSubmit: create
                )
                .accessibilityIdentifier("project-quick-name")
                Text(promise(model.quickName, ready ? ProjectRules.host(slug) : nil))
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Advanced…") { NewProjectDialogs.openAdvanced(model, name: model.quickName) },
                    primary: CoreAction("Create", key: .primary, run: create), busy: model.busy, enabled: ready)
            }
        }
        .onChange(of: model.quickName) { _, _ in model.clearWriteError() }
        .onExitCommand { model.quickOpen = false }
        .accessibilityIdentifier("project-quick")
    }

    private func create() {
        guard ready, !model.busy else { return }
        Task { await model.create(name: model.quickName, slug: slug, colour: .standard(for: slug)) }
    }
}

/// Advanced…: name, colour, GitHub repos, the public link, where it runs, and one summary line.
struct NewProjectSheet: View {
    let model: ProjectsModel
    let close: () -> Void
    @State private var name: String
    @State private var slug: String
    @State private var slugTouched = false
    @State private var colour: ProjectColour
    @State private var colourPicked = false
    @State private var picked: Set<String>
    @State private var pasted: [PickRepo] = []
    @State private var runner = "core"
    @Environment(\.corePalette) private var palette

    init(model: ProjectsModel, name: String, picked: Set<String> = [], close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _picked = State(initialValue: picked)
        let s = ProjectRules.slug(from: name)
        _name = State(initialValue: name)
        _slug = State(initialValue: s)
        _colour = State(initialValue: .standard(for: s))
    }

    private var nameProblem: String? { name.isEmpty ? nil : ProjectRules.nameProblem(name) }
    private var slugProblem: String? { slug.isEmpty && name.isEmpty ? nil : ProjectRules.slugProblem(slug) }
    private var ready: Bool { ProjectRules.nameProblem(name) == nil && ProjectRules.slugProblem(slug) == nil }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 22) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(title: "New Project", line: "Everything here can be changed later in Project Settings.")
                HStack(alignment: .bottom, spacing: Space.s5) {
                    CoreTextField("Name", placeholder: "Project name", text: $name, error: nameProblem, autofocus: true)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("Colour")
                        CoreSegmented(
                            "Colour", segments: ProjectColour.allCases.map { CoreSegment($0, $0.title) },
                            selection: $colour
                        )
                        .fixedSize()
                    }
                }
                RepoPicker(model: model, picked: $picked, pasted: $pasted)
                HStack(alignment: .top, spacing: Space.s5) {
                    CoreTextField(
                        "Public link", placeholder: "link-name", text: $slug, error: slugProblem ?? model.writeError,
                        suffix: ".\(ProjectRules.domain)")
                    // One machine for now: projects run on the Core itself. More runners arrive with the run engine.
                    CoreSelect(
                        "Runs on", selection: $runner,
                        options: [CoreSelectOption("core", "\(model.coreName) · \(ProjectRules.defaultLimits)")])
                }
                summary
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Create Project", key: .primary, run: create), busy: model.busy,
                    enabled: ready)
            }
        }
        .onChange(of: name) { _, new in
            // The link follows the name until it is edited by hand; a colour follows the link until one is picked.
            if !slugTouched { slug = ProjectRules.slug(from: new) }
            model.clearWriteError()
        }
        .onChange(of: slug) { _, new in
            if new != ProjectRules.slug(from: name) { slugTouched = true }
            if !colourPicked { colour = .standard(for: new) }
            model.clearWriteError()
        }
        .onChange(of: colour) { _, new in if new != .standard(for: slug) { colourPicked = true } }
        .accessibilityIdentifier("project-new")
    }

    /// The one summary line: what the Core will do and what the link is.
    private var summary: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkle").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(palette.text2).accessibilityHidden(true)
            Text(summaryText).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .accessibilityElement(children: .combine)
    }

    private var summaryText: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        let room = t.isEmpty ? "a Brain room" : "the Brain room “\(t)”"
        let lead =
            picked.isEmpty
            ? "The Core creates \(room) and the link. Add repos any time and it copies them and drafts how to run them."
            : "The Core copies the repos, drafts how to run them and creates \(room)."
        return
            "\(lead) The link is public while it runs and stops after \(ProjectRules.idleMinutes) min with no visits."
    }

    private func create() {
        guard ready, !model.busy else { return }
        let repos = model.chosen(picked, pasted: pasted)
        Task { await model.create(name: name, slug: slug, colour: colour, repos: repos) }
    }
}

/// "Add a repo" in a project: the picker alone, with the Core's copy-and-draft promise.
struct AddReposSheet: View {
    let model: ProjectsModel
    let project: ProjectItem
    let close: () -> Void
    @State private var picked: Set<String>
    @State private var pasted: [PickRepo] = []

    init(model: ProjectsModel, project: ProjectItem, picked: Set<String> = [], close: @escaping () -> Void) {
        self.model = model
        self.project = project
        self.close = close
        _picked = State(initialValue: picked)
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(title: "Add Repos", line: "The Core keeps a copy of each one and drafts how to run them.")
                RepoPicker(model: model, picked: $picked, pasted: $pasted, height: Space.s8 * 5)
                if let e = model.writeError { CoreFieldError(e) }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(
                        picked.count == 1 ? "Add 1 Repo" : picked.isEmpty ? "Add Repos" : "Add \(picked.count) Repos",
                        key: .primary
                    ) {
                        let repos = model.chosen(picked, pasted: pasted)
                        Task { await model.addRepos(to: project, repos) }
                    }, busy: model.busy, enabled: !picked.isEmpty)
            }
        }
        .accessibilityIdentifier("project-add-repos")
    }
}
