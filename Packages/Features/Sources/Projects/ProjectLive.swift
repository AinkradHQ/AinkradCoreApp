import Brain
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
        /// Percent of one CPU while up; nil when the run engine has not said.
        var cpu: Int? = nil
        var restarts = 0
        /// `none`, `starting`, `healthy` or `unhealthy` (the Core's `health`).
        var health = "none"
    }
    struct LogLine: Equatable, Sendable {
        let service: String
        let text: String
        /// The Core's line number in the run (`seq`) and when the container wrote it; 0 and nil from a stand-in.
        var seq = 0
        var at: Date? = nil
    }
    struct Session: Equatable, Sendable {
        enum State: Equatable, Sendable { case needsYou, running, done }
        let title: String
        let state: State
        let harness: String
        let when: String
        /// The AI Sessions page's other columns; "–" when the Core has not said.
        var runner = "–"
        var branch = "–"
        var cost = "–"
        /// The Core's session id, to open it in AI Sessions; nil from a stand-in.
        var id: String? = nil
    }
    /// A recent commit of a repo.
    struct Commit: Equatable, Sendable {
        let title: String
        /// "Lina M. · 4 m".
        let by: String
        let hash: String
    }
    /// What the Repos page shows of a repo beyond what the Core serves (keyed by repo name).
    /// TODO(core): used-by, size and recent commits per repo; the page hides these rows until they exist.
    struct RepoExtra: Equatable, Sendable {
        var usedBy: String
        var size: String
        var commits: [Commit]
    }
    /// The project's Brain room as the Brain app's own overview model (`RoomOverview`): the page only reads it.
    struct Room: Equatable, Sendable {
        let overview: RoomOverview
        let items: Int
        /// "2 h ago".
        let updated: String
        /// "yesterday", when the instructions were approved.
        var approved = ""
        var summary: String { overview.overview?.summary.components(separatedBy: "\n\n").first ?? "" }
        var instructionsInUse: Bool { overview.instructionsApprovedAt != nil }
        var rules: Int {
            guard let r = overview.overview?.rules else { return 0 }
            return r.workflow.count + r.code.count + r.design.count + r.never.count
        }
    }

    var services: [Service] = []
    var logs: [LogLine] = []
    var sessions: [Session] = []
    var repoExtras: [String: RepoExtra] = [:]
    var room: Room?
    /// The Brain room the project is linked to (`ProjectInfo.room`), written or not.
    var roomID: String?
    /// "idle 4 min of 30", while running.
    var idle: String?
    /// 0...1 while starting when the Core's own state says how far (services up of the setup's); nil when it does not.
    /// No guessed easing: a bar only moves on something read. `steps` is the seam for the Core's real start steps.
    var progress: Double? = nil
    var progressLine = ""
    var steps: [StartStep] = []
    /// Why the last start failed, in words.
    var failure: String?
    /// What to do about it.
    var failureFix: String?
    /// The Core's own word for why it ended (`stop_reason`) and when anything last visited it.
    var stopWords: String?
    var lastActivity: Date?
    /// The runner's name (not its id), where the run lives.
    var runner: String?
    /// The Core could not be asked just now: what is shown is how it last looked.
    var stale = false
}

/// One step of a start, as the Core will say them (lane Q); nothing fills these yet.
struct StartStep: Equatable, Sendable {
    let title: String
    var done: Bool
}

/// The pages of a project's space. `⌘` + `key` opens one. The rail shows them in this order, Project Settings last at the
/// bottom; `docs` (R6-06) is declared after `settings` so every earlier page keeps its ⌘ key, and the rail puts it after Brain.
enum ProjectSection: Int, CaseIterable, Identifiable {
    case overview, run, repos, sessions, brain, settings, docs
    var id: Int { rawValue }
    var key: Character { Character("\(rawValue + 1)") }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .run: "Runs"
        case .repos: "Repos"
        case .sessions: "AI Sessions"
        case .brain: "Brain"
        case .settings: "Project Settings"
        case .docs: "Docs"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .run: "display"
        case .repos: "arrow.triangle.branch"
        case .sessions: "sparkles"
        // SF Symbols 5 (macOS 14): "brain.head.profile" drew a hand on older systems.
        case .brain: "brain"
        case .settings: "slider.horizontal.3"
        case .docs: "doc.text"
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
        case .docs: ("Docs", "No docs yet. Import them from the repos, or write the first one.")
        }
    }
}

enum RunAction { case start, stop, restart }
