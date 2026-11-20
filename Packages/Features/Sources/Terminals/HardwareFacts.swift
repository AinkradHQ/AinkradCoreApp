import Foundation
import Shell

/// What `GET /hardware` says about one machine (E15 §3.4). Read straight from the JSON, like `RunnerReportWire`, so the app
/// builds before the generated client carries the hardware routes. Unknown words stay as strings.
struct HardwareItem: Identifiable, Equatable, Sendable, Decodable {
    struct Battery: Equatable, Sendable, Decodable {
        var onBattery: Bool
        var percent: Int
    }
    struct Job: Identifiable, Equatable, Sendable, Decodable {
        let id: String
        var project: Int?
        var label: String
        var startedAt: Date
    }
    let id: String
    var name: String
    /// `core`, `mac`, `runner`.
    var kind: String
    var online: Bool
    var degraded: Bool
    var pausedUntil: Date?
    /// `open`, `busy`, `on_battery`, `paused`, `off`.
    var gate: String
    var os: String?
    var arch: String?
    var cores: Int
    var cpuPct: Int
    var memTotalMb: Int
    var memFreeMb: Int
    var battery: Battery?
    var toolchains: [String: String]
    var sessions: Int
    var jobs: [Job]
    var jobSlots: Int
}

/// `GET /hardware/pool`: the top bar's load.
struct HardwarePoolItem: Equatable, Sendable, Decodable {
    var loadPct: Int
    var jobs: Int
    var sessions: Int
    var paused: Bool
}

/// One job of `GET /jobs`, for the "Ran on" chips.
struct JobItem: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    var project: Int?
    var session: String?
    var terminal: String?
    var label: String
    var deviceName: String
    var placeReason: String
    var missing: String?
    var state: String

    var place: JobPlace {
        JobPlace(
            deviceName: deviceName, reason: JobPlace.Reason(rawValue: placeReason) ?? .runner, missing: missing,
            state: state)
    }
}

enum HardwareWire {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // RFC 3339 UTC with exactly milliseconds; a second-only stamp is read too.
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s))
        }
        return d
    }()

    /// `{"until": "…Z"}`, or `{"until": null}` to lift a pause.
    static func pauseBody(_ until: Date?) -> Data {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let v: Any = until.map { f.string(from: $0) } ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: ["until": v])) ?? Data()
    }
}

/// A machine's capacity and gate in plain words. Pure, so the words are tested without a view.
struct HardwareFacts: Equatable {
    let hw: HardwareItem
    init(_ hw: HardwareItem) { self.hw = hw }

    var isCore: Bool { hw.kind == "core" }
    var pausedNow: Bool { hw.pausedUntil.map { $0 > .now } ?? false }

    /// 0...1 of memory in use; 0 when the machine reports none.
    var memUsed: Double {
        hw.memTotalMb > 0 ? min(1, max(0, 1 - Double(hw.memFreeMb) / Double(hw.memTotalMb))) : 0
    }

    /// "5.1 of 16 GB RAM in use".
    var memWords: String {
        guard hw.memTotalMb > 0 else { return "RAM not reported yet" }
        let total = Double(hw.memTotalMb) / 1024
        let used = total - Double(hw.memFreeMb) / 1024
        return "\(Self.gb(used)) of \(Self.gb(total)) GB RAM in use"
    }

    private static func gb(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", v) }

    var cpuWords: String { "\(hw.cpuPct)% of \(hw.cores) \(hw.cores == 1 ? "core" : "cores")" }

    /// Whether it takes new work, in one line. The Core's pause wins over the machine's own gate.
    var gateWords: String {
        if pausedNow, let until = hw.pausedUntil {
            return PauseSpan.isForever(until) ? "Paused until you resume" : "Paused until " + Self.when(until)
        }
        switch hw.gate {
        case "open": return "Takes new work"
        case "busy": return "Busy: someone is using it"
        case "on_battery": return "On battery: takes no jobs"
        case "paused": return "Paused on the machine"
        default: return "Takes no jobs"
        }
    }

    var gateOpen: Bool { !pausedNow && hw.gate == "open" }

    var gateSymbol: String {
        if pausedNow { return "pause" }
        switch hw.gate {
        case "open": return "checkmark"
        case "busy": return "hourglass"
        case "on_battery": return "battery.50percent"
        default: return "minus"
        }
    }

    private static func when(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
    }

    /// "rust 1.88", sorted by name.
    var toolchains: [String] {
        hw.toolchains.keys.sorted().map { k in hw.toolchains[k].flatMap { $0.isEmpty ? nil : "\(k) \($0)" } ?? k }
    }

    var battery: String? {
        hw.battery.map { ($0.onBattery ? "On battery" : "Plugged in") + ", \($0.percent)%" }
    }

    /// "2 AI sessions · 1 job".
    var doing: String {
        let s = hw.sessions == 1 ? "1 AI session" : "\(hw.sessions) AI sessions"
        let j = hw.jobs.count == 1 ? "1 job" : "\(hw.jobs.count) jobs"
        return "\(s) · \(j)"
    }
}
