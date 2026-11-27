import CoreUI
import Shell
import SwiftUI

/// The dialogs of Projects, shown over the shell like the other apps' dialogs.
@MainActor
enum NewProjectDialogs {
    static func openWizard(
        _ m: ProjectsModel, name: String, picked: Set<String> = [], step: WizardStep = .name, pasted: [PickRepo] = []
    ) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "project-new", onClose: { [weak m] in m?.clearWriteError() }) {
                ProjectWizard(model: m, name: name, picked: picked, step: step, pasted: pasted) { shell.closeDialog() }
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
                RepoPicker(
                    model: model, picked: $picked, pasted: $pasted, height: Space.s8 * 5, existing: project.repos)
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
