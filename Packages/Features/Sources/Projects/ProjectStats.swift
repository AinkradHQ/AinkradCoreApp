import Foundation

/// The numbers on the Overview's stat tiles, worked out from what the Core already says (the repos' copy state and the
/// project's runs). A number the Core does not serve yet (AI usage, what Core knows) is not drawn here, never guessed.
struct ProjectStats: Equatable {
    /// Repos that are ready, of all.
    let ready: Int
    let total: Int
    /// Repos whose copy failed.
    let needsYou: Int
    let runsThisWeek: Int
    let runningNow: Int

    init(repos: [RepoItem], runs: [RunRecord], now: Date) {
        total = repos.count
        ready = repos.filter { if case .ready = $0.copy { true } else { false } }.count
        needsYou = repos.filter { if case .failed = $0.copy { true } else { false } }.count
        let week = now.addingTimeInterval(-7 * 86_400)
        runsThisWeek = runs.filter { ($0.startedAt ?? .distantPast) >= week }.count
        runningNow = runs.filter(\.live).count
    }

    /// "Good", or what needs the person.
    var health: String { needsYou > 0 ? "Needs you" : total == 0 ? "No code yet" : "Good" }
    var healthLine: String {
        needsYou > 0
            ? "\(ProjectItem.count(needsYou, "repo")) could not be copied"
            : total == 0 ? "Add a repo" : "Everything is ready"
    }
    var healthFraction: Double { total == 0 ? 0 : Double(ready) / Double(total) }
}

/// One line of the Overview's Activity list.
struct ActivityLine: Equatable, Identifiable {
    let title: String
    let symbol: String
    let at: Date
    var id: String { "\(title)\(at.timeIntervalSince1970)" }

    /// Runs and repo copies, newest first, at most `limit`.
    static func timeline(repos: [RepoItem], runs: [RunRecord], names: [Int64: String], limit: Int = 6) -> [ActivityLine]
    {
        var out: [ActivityLine] = []
        for r in runs {
            guard let at = r.startedAt else { continue }
            let n = r.configID.flatMap { names[$0] } ?? "The project"
            out.append(
                ActivityLine(
                    title: r.state == "failed" ? "\(n) failed to start" : "\(n) started",
                    symbol: r.state == "failed" ? "exclamationmark.triangle" : "bolt", at: at))
        }
        for r in repos {
            if let at = r.fetchedAt { out.append(ActivityLine(title: "\(r.name) copied", symbol: "checkmark", at: at)) }
        }
        return Array(out.sorted { $0.at > $1.at }.prefix(limit))
    }
}
