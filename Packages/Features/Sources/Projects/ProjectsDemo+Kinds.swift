#if DEBUG
import Foundation

/// Debug only: the scenes of the project kinds (the wizard's "What is it?" step and each kind's Overview and Settings).
extension ProjectsDemo {
    static let kindScenes = [
        "new-kind", "new-kind-other", "new-kind-picked", "new-runs-app", "new-review-other", "gallery-kinds",
        "overview-app", "overview-app-running", "overview-infra", "overview-infra-stopped", "overview-other",
        "page-settings-kind", "page-settings-kind-old-core",
    ]

    /// The scenes that show a Core with API 111 (it holds the kind).
    static let core111Scenes: Set<String> = ["page-settings-kind", "gallery-kinds", "overview-other"]

    static let iosURL = "https://github.com/tidepool-labs/tidepool-ios"

    private static func set(
        _ p: inout ProjectItem, _ kind: ProjectKind, _ name: String, _ repos: [String], _ line: String
    ) {
        p.kindName = kind.rawValue
        p.name = name
        p.description = line
        p.repos = repos.enumerated().map {
            RepoItem(
                id: p.id * 10 + Int64($0.offset), name: $0.element,
                remoteURL: "https://github.com/tidepool-labs/\($0.element)", branch: "main", primary: $0.offset == 0,
                fetchedAt: Date().addingTimeInterval(-600), fetchError: nil)
        }
    }

    /// The sample list for a kind scene: which of the four projects is which kind.
    static func kindSample(_ scene: String, _ list: inout [ProjectItem]) {
        switch scene {
        case "gallery-kinds":
            set(&list[1], .app, "Tidepool Mobile", ["tidepool-ios", "tidepool-android"], "Order tracking for couriers")
            set(&list[2], .infra, "Tidepool Platform", ["tidepool-infra", "tidepool-os"], "The servers behind it all")
            set(&list[3], .other, "Harbour Book", [], "Research for the book")
            list[3].run = nil
            list[3].live = nil
        case "overview-app", "overview-app-running", "page-settings-kind", "page-settings-kind-old-core":
            let i = scene == "overview-app" ? 1 : 0
            set(&list[i], .app, "Tidepool Mobile", ["tidepool-ios", "tidepool-android"], "Order tracking for couriers")
            list[i].draft = RunDraft(
                source: "Package.swift", services: ["Build the iOS app", "Build the Android app"], secrets: [])
            if scene == "overview-app-running" {
                list[i].live?.steps = [
                    StartStep(title: "Getting the code", state: .done),
                    StartStep(title: "Building the app", state: .done, detail: "Debug · 41 s"),
                    StartStep(title: "Running it", state: .done),
                ]
            }
        case "overview-infra", "overview-infra-stopped":
            let i = scene == "overview-infra" ? 0 : 3
            set(&list[i], .infra, "Tidepool Platform", ["tidepool-infra", "tidepool-os"], "The servers behind it all")
            list[i].draft = RunDraft(
                source: "main.tf", services: ["network", "vault", "queue", "db", "gateway"], secrets: [])
        case "overview-other":
            set(&list[3], .other, "Harbour Book", [], "Research and chapters for the harbour book")
            list[3].run = nil
            var l = DemoLive.make(.stopped)
            l.services = []
            list[3].live = l
        default: break
        }
    }

    /// What a kind scene opens after the list is read.
    func showKind(_ scene: String) async {
        if scene == "overview-infra" {
            let up = { (n: String, mem: String, cpu: Int, health: String) in
                ProjectLive.Service(name: n, memory: mem, state: .up, cpu: cpu, health: health)
            }
            (model.runService as? DemoRunService)?.services[1] = [
                up("network", "42 MB", 2, "healthy"), up("vault", "118 MB", 4, "healthy"),
                up("queue", "96 MB", 3, "unhealthy"), up("db", "402 MB", 6, "healthy"),
                ProjectLive.Service(name: "gateway", memory: "–", state: .exited, restarts: 3),
            ]
            await model.refreshLive(1)
        }
        switch scene {
        case "new-kind", "new-kind-picked", "new-runs-app":
            await model.loadCatalog()
            NewProjectDialogs.openWizard(
                model, name: "Tidepool Mobile", picked: [Self.iosURL],
                step: scene == "new-runs-app" ? .runs : .kind)
        case "new-kind-other":
            NewProjectDialogs.openWizard(model, name: "Harbour Book", step: .kind)
        case "new-review-other":
            NewProjectDialogs.openWizard(model, name: "Harbour Book", step: .review)
        case "gallery-kinds": break
        case "overview-app", "overview-infra-stopped": model.openID = scene == "overview-app" ? 2 : 4
        case "overview-app-running", "overview-infra": model.openID = 1
        case "overview-other": model.openID = 4
        case "page-settings-kind", "page-settings-kind-old-core":
            model.openID = 1
            model.section = .settings
        default: break
        }
    }
}
#endif
