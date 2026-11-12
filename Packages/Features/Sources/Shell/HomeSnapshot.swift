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
        public init(id: String, os: String, online: Bool, slots: Int, used: Int, load: [Double] = []) {
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
        }
    }
    public var about: String {
        switch self {
        case .today: "What needs you, what runs, which machines are up."
        case .needs: "Approvals waiting on a person."
        case .running: "AI sessions working now, and for how long."
        case .spend: "What the AI sessions cost this month."
        case .machines: "Slots in use on every machine."
        case .board: "Issues by state across the board."
        case .events: "What just happened on the Core."
        case .core: "Home Core connection and the alarms it raised."
        case .quick: "New session, new terminal, add a device, open the launcher."
        case .clock: "A round dial with hour, minute and second hands."
        case .digital: "Time and date, with UTC beside your own time."
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
        }
    }
    /// The macOS sizes this widget has a layout for; the first is its default.
    public var sizes: [WidgetSize] {
        switch self {
        case .clock: [.s, .m, .l]
        case .digital: [.m, .s, .t, .l]
        case .quick, .board: [.s, .m, .l, .x]
        default: [.m, .s, .l, .x]
        }
    }
    public var category: String {
        switch self {
        case .spend, .board: "Work"
        case .quick, .clock, .digital: "Utilities"
        default: "Core"
        }
    }
    /// The launcher entry a click on the widget opens.
    var launch: String? {
        switch self {
        case .today, .running, .events: "agents.list"
        case .needs: "agents.inbox"
        case .machines: "runners"
        case .core: "settings"
        default: nil
        }
    }
}
