#if DEBUG
import Foundation

/// Debug only: the focused pages of details v2 (AI Sessions, Brain, Repos, Activity, Logs), with data, empty and in error.
extension ProjectsDemo {
    static let moduleScenes = [
        "mod-ai", "mod-ai-empty", "mod-brain", "mod-brain-empty", "mod-repos", "mod-repos-failed", "mod-repos-empty",
        "mod-activity", "mod-activity-docs", "mod-activity-empty", "mod-logs", "mod-logs-failed", "mod-logs-empty",
    ]

    private static func lanterna(_ i: Int64, _ name: String, _ branch: String, minutes: Double, broken: Bool = false)
        -> RepoItem
    {
        RepoItem(
            id: 10 + i, name: name, remoteURL: "https://github.com/lanterna-co/\(name)", branch: branch,
            primary: i == 0, fetchedAt: Date().addingTimeInterval(-minutes * 60),
            fetchError: broken ? "The GitHub connection can no longer read this repo." : nil,
            head: ["4e1c9a2", "a81f03d", "91aa0c4", "77be210"][Int(i) % 4], state: broken ? "failed" : "ready",
            reason: broken ? "not_found_or_private" : nil)
    }

    static func moduleSample(_ scene: String, _ list: inout [ProjectItem]) {
        switch scene {
        case "mod-ai-empty": list[3].live?.sessions = []
        case "mod-brain-empty":
            list[3].live?.room = nil
            list[3].live?.roomID = nil
        case "mod-repos", "mod-repos-failed":
            list[0].repos = [
                lanterna(0, "lanterna-api", "development", minutes: 4),
                lanterna(1, "lanterna-web", "development", minutes: 4),
                lanterna(2, "lanterna-ios", "main", minutes: 60),
            ]
            if scene == "mod-repos-failed" {
                list[0].repos.append(lanterna(3, "lanterna-admin", "main", minutes: 600, broken: true))
            }
        case "mod-repos-empty": list[3].repos = []
        case "mod-activity-empty": list[3].repos = []
        case "mod-logs-empty":
            list[3].live?.logs = []
            // Never run, so no "Last run" line above an empty log.
            list[3].run = RunSummary(state: .stopped, services: 0, sessions: 0, lastRun: nil)
        case "mod-activity-docs":
            list[3].kindName = ProjectKind.other.rawValue
            list[3].name = "Harbour Book"
            list[3].description = "Research and chapters for the harbour book"
            list[3].repos = []
            list[3].run = nil
            list[3].live = nil
        default: break
        }
    }

    func showModules(_ scene: String) async {
        let pages: [String: (Int64, ProjectModule)] = [
            "mod-ai": (1, .ai), "mod-ai-empty": (4, .ai), "mod-brain": (1, .brain), "mod-brain-empty": (4, .brain),
            "mod-repos": (1, .repos), "mod-repos-failed": (1, .repos), "mod-repos-empty": (4, .repos),
            "mod-activity": (1, .activity), "mod-activity-docs": (4, .activity), "mod-activity-empty": (4, .activity), "mod-logs": (1, .logs),
            "mod-logs-failed": (3, .logs), "mod-logs-empty": (4, .logs),
        ]
        guard let (id, page) = pages[scene] else { return }
        if scene == "mod-activity-empty" { model.configsService = nil }
        model.openID = id
        model.module = page
    }
}
#endif
