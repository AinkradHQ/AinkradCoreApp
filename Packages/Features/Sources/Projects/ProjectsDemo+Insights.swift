#if DEBUG
import Foundation

/// Debug only: the Core's insights routes on made-up data, for the scenes that show a current Core's Settings (Fetch interval,
/// Default environment) and the Activity page. Everything else the insights read is empty. Nothing reaches a Core.
struct DemoInsightsService: ProjectInsightsService {
    /// The kind of each demo project, so a docs project reports edits and imports where a web one reports commits.
    var kinds: [Int64: ProjectKind] = [:]

    func code(project: Int64) async throws -> [CodeInfo] { [] }
    func usage(project: Int64) async throws -> UsageInfo { UsageInfo() }
    func changes(project: Int64) async throws -> ChangesInfo {
        let now = Date()
        func line(_ who: String, _ kind: String, _ summary: String, hours: Double) -> ChangeLine {
            ChangeLine(who: who, kind: kind, summary: summary, at: now.addingTimeInterval(-hours * 3600))
        }
        if kinds[project] == .other {
            return ChangesInfo(
                byAuthor: [("Ana V.", 4), ("AI session", 2)],
                recent: [
                    line("Ana V.", "commit", "Edited Chapter 2 · The ferry crossing", hours: 1),
                    line("AI session", "session", "Linked the tide tables to the research notes", hours: 3),
                    line("Ana V.", "commit", "Imported the interview notes", hours: 26),
                    line("Ana V.", "commit", "Edited the outline of the whole book", hours: 50),
                ])
        }
        return ChangesInfo(
            byAuthor: [("Lina M.", 3), ("Omar K.", 2)],
            recent: [
                line("Lina M.", "commit", "Round coupon totals per line, not per order", hours: 1),
                line("AI session", "session", "Fix coupon rounding for EU orders", hours: 2),
                line("Omar K.", "commit", "Cache product images for 1 day", hours: 27),
            ])
    }
    func area(_ area: String, room: String?) async throws -> [KnownRecord] { [] }
    func sessionDocs() async throws -> [SessionDocItem] { [] }
    func tuning(project: Int64) async throws -> ProjectTuning {
        ProjectTuning(fetchInterval: 15, defaultEnvironment: "Development")
    }
    func setTuning(project: Int64, fetchInterval: Int?, defaultEnvironment: String?) async throws {}
    func unarchive(project: Int64) async throws {}
}
#endif
