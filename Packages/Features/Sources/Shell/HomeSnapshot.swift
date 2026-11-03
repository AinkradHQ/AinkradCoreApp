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

    public var runningAgents: Int { running.count }
    public var machinesOnline: Int { machines.filter(\.online).count }

    public static let empty = HomeSnapshot(
        greetingName: nil, coreName: "Home Core", machines: [], running: [], events: [], board: Board(),
        loadSampleSeconds: nil,
        spendToday: 0, monthTokensUsed: 0)

    public init(
        greetingName: String?, coreName: String, machines: [Machine], running: [Run], events: [Event], board: Board,
        loadSampleSeconds: Int? = nil, spendToday: Double, monthTokensUsed: Double
    ) {
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

public enum WidgetKind: String, CaseIterable, Sendable, Identifiable {
    case today, clock, spend, quick, machines, board, events
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: "Today"
        case .clock: "Clock"
        case .spend: "Agent spend"
        case .quick: "Quick actions"
        case .machines: "Machines"
        case .board: "Citadel board"
        case .events: "Recent events"
        }
    }
    public var about: String {
        switch self {
        case .today: "What needs you, what is running, how the machines are."
        case .clock: "Time and date."
        case .spend: "Spend today and the month token meter."
        case .quick: "New session, new terminal, add a device, open the launcher."
        case .machines: "Runner slots in use."
        case .board: "Issues by state across the board."
        case .events: "What just happened on the Core."
        }
    }
    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .clock: "clock"
        case .spend: "dollarsign.square"
        case .quick: "bolt"
        case .machines: "server.rack"
        case .board: "rectangle.split.3x1"
        case .events: "list.bullet"
        }
    }
}
