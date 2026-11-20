import Foundation

/// What the Home widgets show. The shell has no networking: the app (or `SampleWorld` in Debug) fills this in.
public struct HomeSnapshot: Sendable {
    public struct Machine: Sendable, Identifiable {
        public let id: String
        public let os: String
        public let online: Bool
        public let slots: Int
        public let used: Int
        /// Host load samples, 0...1, oldest first.
        public let load: [Double]
        public var loadPercent: Int { Int(((load.last ?? 0) * 100).rounded()) }
        /// The runner's device id (`runner.tool_install` events carry it); `id` is its name.
        public let runnerID: String
        public init(
            id: String, os: String, online: Bool, slots: Int, used: Int, load: [Double] = [], runnerID: String = ""
        ) {
            self.runnerID = runnerID
            self.load = load
            self.id = id
            self.os = os
            self.online = online
            self.slots = slots
            self.used = used
        }
    }
    public struct Run: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let tool: String
        public let minutes: Int
        public init(id: String, tool: String, name: String, minutes: Int) {
            self.id = id
            self.tool = tool
            self.name = name
            self.minutes = minutes
        }
    }
    public struct Event: Sendable, Identifiable {
        public let id: String
        public let text: String
        public let source: String
        public let minutesAgo: Int
        public let symbol: String
        public init(id: String, text: String, source: String, minutesAgo: Int, symbol: String) {
            self.id = id
            self.text = text
            self.source = source
            self.minutesAgo = minutesAgo
            self.symbol = symbol
        }
    }
    public struct Board: Sendable {
        public var todo = 0, doing = 0, review = 0, blocked = 0, done = 0
        public init(todo: Int = 0, doing: Int = 0, review: Int = 0, blocked: Int = 0, done: Int = 0) {
            self.todo = todo
            self.doing = doing
            self.review = review
            self.blocked = blocked
            self.done = done
        }
    }

    /// A terminal on the Core, as the Terminals widget shows it: its name, where it runs and its last lines.
    public struct TerminalFact: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        /// "This Mac", or the runner it runs on.
        public let place: String
        public let onThisMac: Bool
        /// The last lines on screen, when this Mac has the terminal open. Empty otherwise: the Core keeps no screen.
        public let lines: [String]
        public init(id: String, name: String, place: String, onThisMac: Bool, lines: [String] = []) {
            self.id = id
            self.name = name
            self.place = place
            self.onThisMac = onThisMac
            self.lines = lines
        }
    }
    /// A project and the AI sessions working in it now.
    public struct ProjectFact: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let sessions: Int
        public let updatedAt: Date?
        public init(id: String, name: String, sessions: Int, updatedAt: Date? = nil) {
            self.id = id
            self.name = name
            self.sessions = sessions
            self.updatedAt = updatedAt
        }
    }
    /// What Brain shows Home: how much it knows, what waits for you, and the one question it has.
    public struct BrainGlance: Sendable, Equatable {
        public struct Question: Sendable, Equatable {
            public let id: String
            public let room: String
            public let text: String
            public init(id: String, room: String, text: String) {
                self.id = id
                self.room = room
                self.text = text
            }
        }
        public var known: Int
        public var rooms: Int
        public var waiting: Int
        /// "Healthy", "Needs you" or "Paused".
        public var health: String
        public var question: Question?
        /// What the Brain is doing now, from `GET /activity`; nil on a Core without it.
        public var pipeline: Pipeline?
        public struct Pipeline: Sendable, Equatable {
            public enum Stage: Int, Sendable { case collect, distill, remember }
            /// The stage at work, nil when idle.
            public let now: Stage?
            /// Distils running, queued behind them, and overviews being written.
            public let working: Int
            public let queued: Int
            public let overviews: Int
            public let lastDoneAt: Date?
            /// 0...1 while it works: what is done of the work seen since it started, from the counts alone. nil when idle.
            public var progress: Double?
            public init(
                now: Stage?, working: Int, queued: Int, overviews: Int, lastDoneAt: Date?, progress: Double? = nil
            ) {
                self.progress = progress
                self.now = now
                self.working = working
                self.queued = queued
                self.overviews = overviews
                self.lastDoneAt = lastDoneAt
            }
            /// Distilling while any distil runs or waits, remembering while only overviews are written.
            public static func stage(distilling: Int, queued: Int, overviews: Int) -> Stage? {
                distilling + queued > 0 ? .distill : overviews > 0 ? .remember : nil
            }
        }
        public init(
            known: Int, rooms: Int, waiting: Int, health: String, question: Question? = nil, pipeline: Pipeline? = nil
        ) {
            self.pipeline = pipeline
            self.known = known
            self.rooms = rooms
            self.waiting = waiting
            self.health = health
            self.question = question
        }
    }
    /// Today's Lore note: its first paragraph and its checklist (`- [ ]` / `- [x]` lines).
    public struct NoteFact: Sendable, Equatable {
        public struct Todo: Sendable, Equatable {
            public let text: String
            public let done: Bool
            public init(text: String, done: Bool) {
                self.text = text
                self.done = done
            }
        }
        public var id: String
        public var rev: Int
        /// The whole note, so a tick can be written back without losing anything else in it.
        public var text: String
        public var title: String
        public var paragraph: String
        public var todos: [Todo]
        public var doneCount: Int { todos.filter(\.done).count }

        /// The task on `line`, if it is one: its box state and its words.
        private static func task(_ line: Substring) -> Todo? {
            let t = line.trimmingCharacters(in: .whitespaces)
            let box = t.prefix(5).lowercased()
            guard box == "- [ ]" || box == "* [ ]" || box == "- [x]" || box == "* [x]" else { return nil }
            return Todo(text: t.dropFirst(5).trimmingCharacters(in: .whitespaces), done: box.hasSuffix("x]"))
        }

        /// Reads a note: the first heading (or line) is the title, the first plain line the paragraph, and every task
        /// line a todo. nil when the note has nothing in it.
        public static func parse(_ text: String, id: String = "", rev: Int = 0) -> NoteFact? {
            var title = ""
            var paragraph = ""
            var todos: [Todo] = []
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if let t = task(raw) {
                    todos.append(t)
                } else if line.hasPrefix("#") {
                    if title.isEmpty { title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
                } else if paragraph.isEmpty {
                    paragraph = line
                }
            }
            if title.isEmpty { title = paragraph }
            guard !title.isEmpty || !todos.isEmpty else { return nil }
            return NoteFact(id: id, rev: rev, text: text, title: title, paragraph: paragraph, todos: todos)
        }

        /// `text` with the `n`th task ticked or unticked; nil when there is no such task.
        public static func toggling(_ text: String, todo n: Int) -> String? {
            var lines = text.components(separatedBy: "\n")
            var seen = 0
            for (i, l) in lines.enumerated() where task(Substring(l)) != nil {
                defer { seen += 1 }
                guard seen == n, let open = l.range(of: "[") else { continue }
                let box = l[open.upperBound]
                lines[i].replaceSubrange(open.upperBound...open.upperBound, with: box == " " ? "x" : " ")
                return lines.joined(separator: "\n")
            }
            return nil
        }
    }
    /// How much of one AI provider's plan is used (the tightest limit across its accounts).
    public struct UsageFact: Sendable, Identifiable, Equatable {
        public var id: String { provider }
        public let provider: String
        /// 0...1.
        public let share: Double
        /// When the soonest window resets, if the provider says.
        public let resetsAt: Date?
        public init(provider: String, share: Double, resetsAt: Date? = nil) {
            self.provider = provider
            self.share = share
            self.resetsAt = resetsAt
        }
    }

    public var greetingName: String?
    public var coreName: String
    public var machines: [Machine]
    public var running: [Run]
    public var events: [Event]
    public var board: Board
    /// Seconds between host-load samples, when the app samples them.
    public var loadSampleSeconds: Int?
    public var spendToday: Double
    public var monthTokensUsed: Double
    /// Spend per day from the Core's cost events, oldest first, the last entry today (at most 30 days).
    public var spendByDay: [Double] = []
    /// Spend since the first of this month, from the same events.
    public var monthSpend: Double = 0
    /// From `GET /core/health`; nil until the Core answered it.
    public var health: CoreHealthFacts?
    /// The Terminals, Projects, Brain, Today note and AI usage widgets. Empty / nil until the Core answered.
    public var terminals: [TerminalFact] = []
    public var projects: [ProjectFact] = []
    public var brain: BrainGlance?
    public var note: NoteFact?
    public var usage: [UsageFact] = []
    /// Tokens per day over the last 14 days, oldest first, from `GET /costs/series`; empty on a Core without it.
    public var usageSeries: [Double] = []

    public var runningAgents: Int { running.count }
    public var machinesOnline: Int { machines.filter(\.online).count }

    public static let empty = HomeSnapshot(
        greetingName: nil, coreName: "Home Core", machines: [], running: [], events: [], board: Board(),
        loadSampleSeconds: nil,
        spendToday: 0, monthTokensUsed: 0)

    public init(
        greetingName: String?, coreName: String, machines: [Machine], running: [Run], events: [Event], board: Board,
        loadSampleSeconds: Int? = nil, spendToday: Double, monthTokensUsed: Double, spendByDay: [Double] = [],
        monthSpend: Double = 0
    ) {
        self.spendByDay = spendByDay
        self.monthSpend = monthSpend
        self.loadSampleSeconds = loadSampleSeconds
        self.greetingName = greetingName
        self.coreName = coreName
        self.machines = machines
        self.running = running
        self.events = events
        self.board = board
        self.spendToday = spendToday
        self.monthTokensUsed = monthTokensUsed
    }
}

public enum WidgetKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case today, needs, running, spend, machines, board, events, core, quick, clock, digital
    // Added in 0.10 (E4-2, D-13).
    case terminals, projects, brain, todaynote, approvals, aiusage, weather, calendar
    public var id: String { rawValue }
    /// Core has no board, so the board widget exists in the sample world (`CORE_DEMO=1`) only, never on a live Core.
    static var boardShown: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CORE_DEMO"] == "1"
        #else
        false
        #endif
    }
    public var title: String {
        switch self {
        case .today: "Today"
        case .needs: "Needs you"
        case .running: "Running AI sessions"
        case .spend: "AI spend"
        case .machines: "Machines"
        case .board: "Citadel board"
        case .events: "Recent events"
        case .core: "Core health"
        case .quick: "Quick actions"
        case .clock: "Analog clock"
        case .digital: "Digital clock"
        case .terminals: "Terminals"
        case .projects: "Projects"
        case .brain: "Brain"
        case .todaynote: "Today note"
        case .approvals: "Approvals"
        case .aiusage: "AI usage"
        case .weather: "Weather"
        case .calendar: "Calendar"
        }
    }
    public var about: String {
        switch self {
        case .today: "What needs you, what runs, which machines are up."
        case .needs: "Everything waiting on a person."
        case .running: "AI sessions working now, and for how long."
        case .spend: "What the AI sessions cost this month."
        case .machines: "How busy every machine is."
        case .board: "Issues by state across the board."
        case .events: "What just happened on the Core."
        case .core: "Core connection, memory, disk and backup."
        case .quick: "Start an AI session, a terminal or a Brain search."
        case .clock: "A round dial, hands and a quiet second tick."
        case .digital: "Time and date, with other places beside it."
        case .terminals: "Your terminals, with a live look at the last lines."
        case .projects: "Your projects and the sessions working in them."
        case .brain: "What Brain is learning, and the one question it has for you."
        case .todaynote: "Today note and a short checklist."
        case .approvals: "Allow or refuse a request without opening anything."
        case .aiusage: "How much of each plan you have used so far."
        case .weather: "The weather where you are."
        case .calendar: "Your next events, this week or this month."
        }
    }
    public var symbol: String {
        switch self {
        case .today: "calendar"
        case .needs: "lock.shield"
        case .running: "play"
        case .spend: "creditcard"
        case .machines: "server.rack"
        case .board: "rectangle.split.3x1"
        case .events: "list.bullet"
        case .core: "heart.text.square"
        case .quick: "bolt"
        case .clock: "clock"
        case .digital: "textformat.123"
        case .terminals: "terminal"
        case .projects: "folder"
        case .brain: "brain"
        case .todaynote: "note.text"
        case .approvals: "checkmark.shield"
        case .aiusage: "chart.bar"
        case .weather: "sun.max"
        case .calendar: "calendar"
        }
    }
    /// The sizes this widget has a layout for (small a glance, medium a list, wide a chart, large the detail); the first
    /// is its default.
    public var sizes: [WidgetSize] {
        switch self {
        case .clock, .quick, .board: [.s, .m, .w, .l]
        default: [.m, .s, .w, .l]
        }
    }
    /// True for the widgets added in 0.10: the gallery tags them New.
    public var isNew: Bool {
        switch self {
        case .terminals, .projects, .brain, .todaynote, .approvals, .aiusage, .weather, .calendar: true
        default: false
        }
    }
    public var category: String {
        switch self {
        case .spend, .board, .terminals, .projects: "Work"
        case .quick, .clock, .digital, .todaynote, .weather, .calendar: "Utilities"
        default: "Core"
        }
    }
    /// The launcher entry a click on the widget opens (the app the widget belongs to).
    var launch: String? {
        switch self {
        case .today, .running, .events: "agents.list"
        case .needs, .approvals: "agents.inbox"
        case .machines: "runners"
        case .core, .weather, .digital, .clock: "settings"
        case .terminals: "terminals"
        case .projects: "projects"
        case .brain: "brain"
        case .todaynote: "lore"
        case .aiusage, .spend: "accounts"
        case .calendar: "connections"
        case .quick, .board: nil
        }
    }
}
