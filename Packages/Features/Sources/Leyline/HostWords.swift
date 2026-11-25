import CoreUI
import SwiftUI

/// Small words shared by the host pages.
enum HostWords {
    static func ago(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
    static func percent(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "–" }
    static func size(_ n: Int64?) -> String { n.map { $0.formatted(.byteCount(style: .file)) } ?? "–" }

    /// How a command's run on this host stands, in a line.
    static func run(_ r: CommandRun) -> String {
        switch r.state {
        case .queued, .running: "Running…"
        case .needsApproval: "Waiting for approval"
        case .ok:
            "ok"
                + (r.durationMS.map { " · \((Double($0) / 1000).formatted(.number.precision(.fractionLength(1)))) s" }
                    ?? "")
        case .failed: "failed" + (r.exitCode.map { " · exit \($0)" } ?? "") + (r.step.map { " · step \($0)" } ?? "")
        case .refused: "Refused by the gate"
        case .skipped: "Skipped"
        }
    }
    /// The run's state as the card's badge: a word and its tone.
    static func badge(_ r: CommandRun) -> (word: String, tone: Tone) {
        switch r.state {
        case .queued, .running: ("Running", .run)
        case .needsApproval: ("Waiting for approval", .warn)
        case .ok: ("Done", .done)
        case .failed: (r.exitCode.map { "Failed · exit \($0)" } ?? "Failed", .fail)
        case .refused: ("Refused", .fail)
        case .skipped: ("Skipped", .queue)
        }
    }

    /// "exit 0 · 1.2 s · step 2": what the drawer says beside the badge; nil while nothing is known.
    static func facts(_ r: CommandRun) -> String? {
        var out: [String] = []
        if let e = r.exitCode { out.append("exit \(e)") }
        if let ms = r.durationMS {
            out.append("\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))) s")
        }
        if let s = r.step, s > 1 { out.append("step \(s)") }
        return out.isEmpty ? nil : out.joined(separator: " · ")
    }

    static func symbol(_ w: HostEvent.Who) -> String {
        switch w {
        case .you: "person"
        case .ai: "sparkles"
        case .fleet: "square.stack.3d.up"
        case .system: "bell"
        }
    }
    static func who(_ w: HostEvent.Who) -> String {
        switch w {
        case .you: "You"
        case .ai: "AI"
        case .fleet: "Fleet"
        case .system: "Alert"
        }
    }
    /// What a read that has no data says, in place of the data.
    static func gone(_ missing: String) -> String { "\(missing) arrives with the next Core update." }
}
