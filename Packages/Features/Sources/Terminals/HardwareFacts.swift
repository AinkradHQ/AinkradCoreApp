import AinkradClient
import Foundation
import Shell

/// What `GET /hardware` says about one machine (E15 §3.4), flattened from the generated `Components.Schemas.Hardware`:
/// the generated enums are wrapped (`value1` known, `value2` a word this build does not know), so the words stay strings.
struct HardwareItem: Identifiable, Equatable, Sendable {
    struct Battery: Equatable, Sendable {
        var onBattery: Bool
        var percent: Int
    }
    struct Job: Identifiable, Equatable, Sendable {
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
struct HardwarePoolItem: Equatable, Sendable {
    var loadPct: Int
    var jobs: Int
    var sessions: Int
    var paused: Bool
    /// `decisions.status` is `off_no_provider`: no Google account in the AI order, so commands no rule knows stay local.
    var decisionsOff = false
}

/// One job of `GET /jobs`, for the "Ran on" chips.
struct JobItem: Identifiable, Equatable, Sendable {
    let id: String
    var project: Int?
    var session: String?
    var terminal: String?
    var label: String
    var deviceName: String
    var placeReason: String
    var missing: String?
    var state: String
    var startedAt: Date?

    var place: JobPlace {
        JobPlace(
            deviceName: deviceName, reason: JobPlace.Reason(rawValue: placeReason) ?? .runner, missing: missing,
            state: state)
    }
}

enum HardwareWire {
    /// RFC 3339 UTC with milliseconds, as the Core sends it (the generated client reads it itself; tests decode JSON with this).
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
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

extension LiveTerminalService {
    /// A generated enum wrapper's word: the known case, else the word a newer Core sent.
    private static func word<E: RawRepresentable>(_ known: E?, _ other: String?) -> String? where E.RawValue == String {
        known?.rawValue ?? other
    }

    static func hardware(_ h: Components.Schemas.Hardware) -> HardwareItem {
        HardwareItem(
            id: h.id, name: h.name, kind: word(h.kind.value1, h.kind.value2) ?? "runner", online: h.online,
            degraded: h.degraded, pausedUntil: h.pausedUntil, gate: word(h.gate.value1, h.gate.value2) ?? "off",
            os: h.os, arch: h.arch, cores: Int(h.cores), cpuPct: Int(h.cpuPct), memTotalMb: Int(h.memTotalMb),
            memFreeMb: Int(h.memFreeMb),
            battery: h.battery.map { .init(onBattery: $0.onBattery, percent: Int($0.percent)) },
            toolchains: h.toolchains.additionalProperties, sessions: Int(h.sessions),
            jobs: h.jobs.map {
                .init(id: $0.id, project: $0.project.map(Int.init), label: $0.label, startedAt: $0.startedAt)
            }, jobSlots: Int(h.jobSlots))
    }

    static func job(_ j: Components.Schemas.Job) -> JobItem {
        JobItem(
            id: j.id, project: j.project.map(Int.init), session: j.session, terminal: j.terminal, label: j.label,
            deviceName: j.deviceName, placeReason: word(j.placeReason.value1, j.placeReason.value2) ?? "runner",
            missing: j.missing, state: word(j.state.value1, j.state.value2) ?? "ended", startedAt: j.startedAt)
    }
}
