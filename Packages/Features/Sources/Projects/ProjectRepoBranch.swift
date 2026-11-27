import CoreUI
import Shell
import SwiftUI

/// "Change…" on the Repos page (API 110): the branch a repo follows. The Core has no list of branches to offer, so it is a
/// field; the Core checks the name on its copy and says in words when there is no such branch.
@MainActor
enum RepoDialogs {
    static func openBranch(_ m: ProjectsModel, _ p: ProjectItem, _ r: RepoItem) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "project-repo-branch", onClose: { [weak m] in m?.clearWriteError() }) {
                BranchSheet(model: m, project: p, repo: r) { shell.closeDialog() }
            })
    }
}

struct BranchSheet: View {
    let model: ProjectsModel
    let project: ProjectItem
    let repo: RepoItem
    let close: () -> Void
    @State private var branch: String

    init(model: ProjectsModel, project: ProjectItem, repo: RepoItem, close: @escaping () -> Void) {
        self.model = model
        self.project = project
        self.repo = repo
        self.close = close
        _branch = State(initialValue: repo.branch)
    }

    private var problem: String? {
        branch == repo.branch ? nil : ProjectsModel.branchProblem(branch)
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Change the Branch of \(repo.name)",
                    line:
                        "Sessions and runs of \(project.name) start from this branch. The Core fetches it again to follow it."
                )
                CoreTextField("Branch", placeholder: "main", text: $branch, error: problem, onSubmit: save)
                if let e = model.writeError { CoreFieldError(e) }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Change Branch", key: .primary, run: save), busy: model.busy,
                    enabled: problem == nil && !branch.trimmingCharacters(in: .whitespaces).isEmpty
                        && branch.trimmingCharacters(in: .whitespaces) != repo.branch)
            }
        }
        .accessibilityIdentifier("project-repo-branch")
    }

    private func save() { Task { await model.changeBranch(project, repo, to: branch) } }
}
