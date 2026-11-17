import Foundation

/// What the Overview shows of a project beyond what the Core serves today: its services, logs, AI sessions and Brain room.
///
/// Nothing here exists in the Core yet. A real project has `live == nil` and its islands show their empty words; only the
/// Debug demo (`ProjectsDemo`) fills it, so the screens can be built and reviewed now.
/// TODO(P5-03, P5-04): services, health, memory and logs from the run engine (`ProjectItem.run` and `.live.services/logs`).
/// TODO(P3-02): the AI sessions of this project (`project_id` filter on the sessions list).
/// TODO(P1-03): the project's Brain room (`room` on the project); until it lands the island keeps its "new room" words.
/// TODO(P6-02): `idle` and the live app address state, from the exposure.
struct ProjectLive: Equatable, Sendable {
    struct Service: Equatable, Sendable {
        enum State: Equatable, Sendable { case up, down, exited }
        let name: String
        let memory: String
        let state: State
    }
    struct LogLine: Equatable, Sendable {
        let service: String
        let text: String
    }
    struct Session: Equatable, Sendable {
        enum State: Equatable, Sendable { case needsYou, running, done }
        let title: String
        let state: State
        let harness: String
        let when: String
    }
    struct Room: Equatable, Sendable {
        let summary: String
        let instructionsInUse: Bool
        let rules: Int
        let items: Int
    }

    var services: [Service] = []
    var logs: [LogLine] = []
    var sessions: [Session] = []
    var room: Room?
    /// "idle 4 min of 30", while running.
    var idle: String?
    /// 0...1 and its words, while starting.
    var progress = 0.0
    var progressLine = ""
    /// Why the last start failed, in words.
    var failure: String?
    /// What to do about it.
    var failureFix: String?
}

/// The pages of a project's space, in the rail's order. `⌘` + `key` opens one.
enum ProjectSection: Int, CaseIterable, Identifiable {
    case overview, run, repos, sessions, brain, settings
    var id: Int { rawValue }
    var key: Character { Character("\(rawValue + 1)") }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .run: "Run"
        case .repos: "Repos"
        case .sessions: "AI Sessions"
        case .brain: "Brain"
        case .settings: "Project Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .run: "display"
        case .repos: "arrow.triangle.branch"
        case .sessions: "sparkles"
        case .brain: "brain.head.profile"
        case .settings: "slider.horizontal.3"
        }
    }
    /// What an unbuilt page says (P7-03..P7-05 fill them in), from the approved mockup's empty states.
    func empty(_ project: ProjectItem) -> (title: String, line: String) {
        switch self {
        case .overview: ("Overview", "")
        case .run: ("Run", "Not set up yet. It is drafted from your repos once you add them.")
        case .repos:
            ("Repos", project.repos.isEmpty ? "No repos yet." : project.repos.map(\.name).joined(separator: ", "))
        case .sessions: ("AI Sessions", "No AI sessions yet. Start one from the top bar.")
        case .brain:
            (
                "\(project.name) room",
                "New room, nothing in it yet. It fills from the repos’ instruction files, AI sessions and docs you add."
            )
        case .settings: ("General", "Name, link and run limits, as in any project.")
        }
    }
}

enum RunAction { case start, stop, restart }
