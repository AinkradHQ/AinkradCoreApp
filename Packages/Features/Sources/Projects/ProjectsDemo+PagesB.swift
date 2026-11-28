#if DEBUG
import Foundation

/// Debug only: the focused pages of details v2 (Live site, Builds, Services, Documents, Settings), each with data, empty and
/// failing. Every scene sets `model.module`; the shell shows the page.
extension ProjectsDemo {
    static let pagesBScenes = [
        "v2b-live", "v2b-live-stopped", "v2b-live-failed", "v2b-live-error",
        "v2b-builds", "v2b-builds-empty", "v2b-builds-error",
        "v2b-services", "v2b-services-empty", "v2b-services-failed",
        "v2b-docs", "v2b-docs-empty", "v2b-docs-error",
        "v2b-settings", "v2b-settings-old-core", "v2b-settings-error",
    ]

    private static let multi: Set<String> = [
        "v2b-live", "v2b-builds", "v2b-builds-empty", "v2b-builds-error", "v2b-settings", "v2b-settings-error",
    ]

    /// The sample list for a scene: the first project is a web and app project in the build scenes.
    static func pagesBSample(_ scene: String, _ list: inout [ProjectItem]) {
        guard scene.hasPrefix("v2b-") else { return }
        if multi.contains(scene) {
            list[0].kinds = [.web, .app]
            list[0].kindName = "web"
        }
        if scene == "v2b-settings-old-core" { list[0].kindName = "web" }
        if scene == "v2b-builds" {
            list[0].live?.steps = [
                StartStep(title: "Getting the code", state: .done, detail: "4 s"),
                StartStep(title: "Resolving packages", state: .done, detail: "22 s"),
                StartStep(title: "Building for iOS", state: .done, detail: "2 min 31 s"),
                StartStep(title: "Signing", state: .done, detail: "9 s"),
                StartStep(title: "Installing on the simulator", state: .done, detail: "6 s"),
            ]
        }
        if scene == "v2b-live-stopped" {
            var l = DemoLive.make(.stopped)
            l.stopWords = "It stopped after a while with no visits."
            l.services = []
            list[3].live = l
        }
        if scene == "v2b-docs" || scene == "v2b-docs-empty" || scene == "v2b-docs-error" {
            list[3].kindName = ProjectKind.other.rawValue
            list[3].name = "Harbour Book"
            list[3].run = nil
            list[3].live = nil
        }
    }

    private static func build(_ id: String, _ state: String, minutes: Double, took: Double, why: String? = nil, error: String? = nil)
        -> RunRecord
    {
        RunRecord(
            id: id, state: state, configID: nil, environment: "Debug", runner: "core-oracle",
            startedAt: Date().addingTimeInterval(-minutes * 60),
            stoppedAt: Date().addingTimeInterval(-minutes * 60 + took), stopReason: why, error: error)
    }

    func showPagesB(_ scene: String) async {
        guard scene.hasPrefix("v2b-") else { return }
        model.core112 = scene != "v2b-settings-old-core"
        let configs = model.configsService as? DemoConfigsService
        switch scene {
        case "v2b-live", "v2b-live-error": model.openID = 1
        case "v2b-live-failed": model.openID = 3
        case "v2b-live-stopped": model.openID = 4
        case "v2b-builds", "v2b-builds-empty", "v2b-builds-error":
            model.openID = 1
            configs?.historyOverride =
                scene == "v2b-builds"
                ? [
                    Self.build("b1", "stopped", minutes: 4, took: 192, why: "user"),
                    Self.build("b2", "failed", minutes: 70, took: 41, error: "error: no such module ‘Tidepool’"),
                    Self.build("b3", "stopped", minutes: 1_500, took: 280, why: "user"),
                    Self.build("b4", "stopped", minutes: 1_560, took: 182, why: "user"),
                ] : []
            configs?.failing = scene == "v2b-builds-error"
        case "v2b-services", "v2b-services-empty", "v2b-services-failed":
            model.openID = scene == "v2b-services-empty" ? 4 : scene == "v2b-services-failed" ? 3 : 1
            model.core110 = true
            await model.refreshLive(1)
            if scene == "v2b-services-failed" {
                (model.runService as? DemoRunService)?.services[3] = DemoLive.make(.failed).services
                await model.refreshLive(3)
            }
        case "v2b-docs", "v2b-docs-empty", "v2b-docs-error":
            let lore = DemoDocsLore(scene == "v2b-docs-empty" ? [] : DemoDocsLore.harbour)
            lore.failing = scene == "v2b-docs-error"
            model.lore = lore
            model.openID = 4
        case "v2b-settings", "v2b-settings-old-core", "v2b-settings-error": model.openID = 1
        default: break
        }
        if scene == "v2b-live-error" { model.demoPreviewProblem = "The app is busy with other requests. Try again in a moment." }
        if scene == "v2b-settings-error" { model.writeError = "The Core refused the change: that link name is taken." }
        model.module =
            switch scene.dropFirst(4).prefix { $0 != "-" } {
            case "live": .live
            case "builds": .builds
            case "services": .services
            case "docs": .docs
            default: .settings
            }
    }
}
#endif
