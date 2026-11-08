import Foundation

// Checks' shapes. The service runs the checks and decides every result; the screens show what comes back. A result holds
// numbers and words only, never memory text (BM-05).

public enum CheckOutcome: String, Sendable, Hashable { case pass, fail, due, never }

public struct CheckItem: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    /// One plain sentence about what the check proves.
    public var about: String
    public var last: String
    public var outcome: CheckOutcome
    public var due: String
    /// What was measured, against `target`.
    public var value: String
    public var target: String
    /// The last results, oldest first. True passed.
    public var history: [Bool]
    /// The service could not run it because this Mac is offline and it needs the server.
    public var skippedOffline: Bool
    /// You cleared Paused after this result; a re-run confirms.
    public var clearedAfter: Bool
    public var housekeeping: Bool
    public var needsServer: Bool
    /// A measured series (Speed: p95 in ms, oldest first) with its limit, for the bigger chart.
    public var trend: [Double]
    public var trendLimit: Double?

    public init(
        id: String, name: String, about: String, last: String, outcome: CheckOutcome, due: String, value: String,
        target: String, history: [Bool] = [], skippedOffline: Bool = false, clearedAfter: Bool = false,
        housekeeping: Bool = false, needsServer: Bool = false, trend: [Double] = [], trendLimit: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.about = about
        self.last = last
        self.outcome = outcome
        self.due = due
        self.value = value
        self.target = target
        self.history = history
        self.skippedOffline = skippedOffline
        self.clearedAfter = clearedAfter
        self.housekeeping = housekeeping
        self.needsServer = needsServer
        self.trend = trend
        self.trendLimit = trendLimit
    }
}

public enum PilotResult: String, Sendable, Hashable {
    case pass, fail, notMeasured
    public var label: String {
        switch self {
        case .pass: "Pass"
        case .fail: "Fail"
        case .notMeasured: "Not measured"
        }
    }
}

/// One pilot target (C1 to C14). The service fills `value` and `result` from the checks.
public struct PilotTarget: Sendable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String
    public let title: String
    public let target: String
    public let value: String
    public let result: PilotResult
    public init(_ code: String, _ title: String, target: String, value: String, result: PilotResult) {
        self.code = code
        self.title = title
        self.target = target
        self.value = value
        self.result = result
    }
}

public struct ChecksReport: Sendable, Hashable {
    public var items: [CheckItem]
    public var pilot: [PilotTarget]
    public init(items: [CheckItem], pilot: [PilotTarget]) {
        self.items = items
        self.pilot = pilot
    }
}

/// What the advanced sheet chooses. `rooms` nil is every mounted room. The plain Run now uses `.standard`.
public struct CheckRunOptions: Sendable, Hashable {
    public var rooms: [String]?
    public var questions: Int
    public init(rooms: [String]? = nil, questions: Int = 1000) {
        self.rooms = rooms
        self.questions = questions
    }
    public static let standard = CheckRunOptions()
}

/// How a check row reads right now.
public enum CheckState: String, Sendable, Hashable {
    case running, skipped, pass, fail, due, never
    public var label: String {
        switch self {
        case .running: "Running"
        case .skipped: "Skipped, offline"
        case .pass: "Passed"
        case .fail: "Failed"
        case .due: "Due"
        case .never: "Never run"
        }
    }
}

extension BrainWords {
    public static let checksSkipped =
        "Needs the server, and this Mac is offline. Run it again when you are back online."
    public static let checksNever = "Not run yet. Run it once to get a first result."
    public static func checksSummary(failed: Int, due: Int) -> String {
        if failed > 0 { return "\(plural(failed, "check", "checks")) failed." }
        if due > 0 { return "\(plural(due, "check is", "checks are")) due." }
        return "Every check passed."
    }
}
