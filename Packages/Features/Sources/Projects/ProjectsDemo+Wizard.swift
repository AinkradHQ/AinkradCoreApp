#if DEBUG
import Foundation

/// Debug only: the New Project wizard's scenes, one per step and state (three steps, each kind, review rows, setup).
extension ProjectsDemo {
    static let wizardScenes = [
        "new-name", "new-link-name", "new-kind", "new-kind-picked", "new-kind-other", "new-code", "new-code-corrected",
        "new-code-other", "new-code-no-github", "new-paste-link", "new-review",
        "new-review-brain",
        "new-review-runs", "new-review-runs-app", "new-review-link", "new-review-app", "new-review-infra",
        "new-review-other", "new-setting-up", "new-copying", "new-failed-repos", "new-finished",
    ]

    /// Repos pasted as links: a project with many repos, to show the counts.
    private static func pastedRepos(_ names: [String]) -> [PickRepo] {
        names.map { PickRepo(org: "Pasted links", name: $0, url: "https://github.com/tidepool-labs/\($0)") }
    }

    func showWizard(_ scene: String) async {
        guard Self.wizardScenes.contains(scene) else { return }
        await model.loadCatalog()
        let two: Set<String> = [Self.apiURL, Self.webURL]
        let m = model
        func open(
            _ name: String, _ picked: Set<String> = [], _ step: WizardStep = .what, kind: ProjectKind? = nil,
            editing: WizardRow? = nil, pasted: [PickRepo] = []
        ) {
            NewProjectDialogs.openWizard(
                m, name: name, picked: picked, step: step, pasted: pasted, kind: kind, editing: editing)
        }
        switch scene {
        case "new-name": open("Tidepool")
        case "new-link-name": open("2048 game")
        case "new-kind": open("Tidepool Mobile", kind: .app)
        case "new-kind-picked": open("Tidepool Platform", kind: .infra)
        case "new-kind-other": open("Harbour Book", kind: .other)
        case "new-code": open("Tidepool", two, .code)
        case "new-code-corrected": open("Tidepool Mobile", [Self.iosURL], .code)
        case "new-code-other": open("Harbour Book", [], .code, kind: .other)
        // No GitHub connected: the step offers "Connect GitHub"; the second scene has a repo link pasted in.
        case "new-code-no-github": open("Tidepool", [], .code)
        case "new-paste-link":
            open("Tidepool", [Self.apiURL], .code, pasted: Self.pastedRepos(["tidepool-api"]))
        case "new-review": open("Tidepool", two, .review)
        case "new-review-brain": open("Tidepool", two, .review, editing: .brain)
        case "new-review-runs": open("Tidepool", two, .review, editing: .runs)
        case "new-review-runs-app": open("Tidepool Mobile", [Self.iosURL], .review, editing: .runs)
        case "new-review-link": open("Tidepool", two, .review, editing: .link)
        case "new-review-app": open("Tidepool Mobile", [Self.iosURL], .review)
        case "new-review-infra": open("Tidepool Platform", [Self.apiURL], .review, kind: .infra)
        case "new-review-other": open("Harbour Book", [], .review, kind: .other)
        case "new-setting-up":
            open("Tidepool", [], .review, pasted: Self.pastedRepos((1...22).map { "tidepool-service-\($0)" }))
            model.creating = CreateProgress(stage: .repos, added: 9, total: 22)
        case "new-copying":
            open("Tidepool", two, .review)
            model.wizardProjectID = 7
        case "new-failed-repos":
            open("Tidepool", two, .review, pasted: Self.pastedRepos(["tidepool-infra", "tidepool-ops"]))
            try? await Task.sleep(for: .milliseconds(300))
            model.wizardMissed = [
                MissedRepo(name: "tidepool-infra", why: "This project already has that repo."),
                MissedRepo(
                    name: "tidepool-ops", why: "SSH addresses are not supported yet. Use the https address of the repo."
                ),
            ]
            model.wizardIssues = ["The link is tidepool-2.ainkrad.io: tidepool was taken."]
            model.wizardProjectID = 7
        default:
            open("Tidepool", two, .review)
            model.wizardProjectID = 7
        }
    }
}
#endif
