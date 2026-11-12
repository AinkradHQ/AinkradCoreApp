import CoreUI
import SwiftUI

/// The words of the conversation screen (ui-fixes ai-session-conversation): quiet centred event lines in sentence case, the
/// one notice above the transcript, and the composer's placeholder. Pure, so the copy is tested.
enum ConversationWords {
    /// An event line: "Started on Oracle", "Ended: finished", "Interrupted: …". Nil for entries that are not events.
    static func event(_ kind: EntryKind, runner: String) -> String? {
        switch kind {
        case .started(_, let resumed): resumed ? "Woke up on \(runner)" : "Started on \(runner)"
        case .interrupted(let reason):
            "Interrupted" + (reason.isEmpty ? "" : ": \(AgentWords.reasonWords(reason))")
        case .gap(let from, let to): "Entries \(from) to \(to) were not kept"
        case .ended(let kind, let reason):
            {
                let budget =
                    kind == "budget" || (kind == "cancelled" && reason?.lowercased().contains("budget") == true)
                let why = budget ? nil : reason.flatMap { $0.isEmpty ? nil : AgentWords.reasonWords($0) }
                return AgentWords.endedWords(budget ? "budget" : kind) + (why.map { " · \($0)" } ?? "")
            }()
        case .note(let type, let detail): detail.isEmpty ? words(type) : "\(words(type)): \(detail)"
        default: nil
        }
    }

    /// `approval_escalated` → `Approval escalated`.
    static func words(_ code: String) -> String {
        let w = code.replacingOccurrences(of: "_", with: " ")
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    /// The turn number of every `turnEnded` entry, by seq, in one pass.
    static func turnNumbers(_ entries: [TranscriptEntry]) -> [Int64: Int] {
        var out: [Int64: Int] = [:]
        var n = 0
        for e in entries {
            if case .turnEnded = e.kind {
                n += 1
                out[e.seq] = n
            }
        }
        return out
    }

    /// "Turn 1 done", then the tokens and the cost when the Core reported them; the time is added by the line.
    static func turn(_ number: Int?, cost: Int64?, tokens: Int64?) -> [String] {
        [
            number.map { "Turn \($0) done" } ?? "Turn done", tokens.map { "\(AgentWords.tokens($0)) tokens" },
            AgentWords.cost(cost),
        ].compactMap { $0 }
    }

    /// The one notice above the transcript, most urgent first (audit: one notice at a time). Lost carries Resume.
    struct Banner: Equatable {
        let symbol: String
        let tone: Tone
        let title: String
        let text: String
        var resume = false
    }

    static func banner(_ s: AgentSessionInfo, runner: String, reconnecting: Bool, notice: InlineNotice?) -> Banner? {
        if reconnecting {
            return Banner(
                symbol: "arrow.triangle.2.circlepath", tone: .warn, title: "Reconnecting",
                text: "It resumes from where it left off.")
        }
        if let n = notice { return Banner(symbol: n.symbol, tone: n.tone, title: n.title, text: n.detail) }
        if s.state == .lost {
            return Banner(
                symbol: "wifi.exclamationmark", tone: .fail, title: "Session lost",
                text: "\(runner) dropped it. The transcript is kept.", resume: true)
        }
        if s.idleEnded {
            return Banner(
                symbol: "moon.zzz", tone: .queue, title: "Ended (idle)",
                text: "Send a message to continue in the same conversation.")
        }
        if s.keepsOpen == false && !s.over {
            return Banner(
                symbol: "info.circle", tone: .warn, title: "One answer, then it ends",
                text: "\(runner) runs an older version. Update the runner for live AI sessions.")
        }
        if let raw = s.state.unknownRaw {
            return Banner(
                symbol: "questionmark.circle", tone: .queue, title: raw, text: "This state is newer than this app.")
        }
        return nil
    }

    static func placeholder(_ s: AgentSessionInfo) -> String {
        let tool = AgentWords.toolName(s.harness)
        switch s.state {
        case .running: return "Type to queue a message for after this turn"
        case .waiting: return "Message \(tool)"
        case .starting: return "Starting. You can type now; it is sent when the session is up."
        case .interrupted: return "Resuming. You can type now."
        case .ended where s.idleEnded: return "Send a message to continue"
        case .ended: return "This AI session ended. Start again opens a new one with the same first message."
        default: return "Send a message to bring it back"
        }
    }

    /// Recent places to start in, newest first, one per project: the empty session's "Or start in a project".
    struct Place: Equatable, Identifiable {
        let project: String
        let branch: String?
        let runner: String
        var id: String { project }
    }

    static func recentPlaces(_ sessions: [AgentSessionInfo], limit: Int = 3) -> [Place] {
        var seen = Set<String>()
        var out: [Place] = []
        for s in sessions.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let p = s.project, !p.isEmpty, seen.insert(p).inserted else { continue }
            out.append(Place(project: p, branch: s.branch, runner: s.runner))
            if out.count == limit { break }
        }
        return out
    }
}

/// Thinking and running tools: a short blue bar whose segment slides along its track, never a spinner or bouncing dots.
/// Under Reduce Motion the segment rests in the middle. Local part, proposed for CoreUI as an indeterminate `CoreMeter`.
struct WorkingBar: View {
    var width: CGFloat = Space.s8 + Space.s6
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let seg = width * 0.4
        TimelineView(.animation(paused: reduce)) { ctx in
            // A 1.2 s sweep, eased at both ends so it reads as calm travel rather than a tick.
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let p = reduce ? 0.5 : (1 - cos(t * 2 * .pi)) / 2
            coreShape(2).fill(palette.track)
                .overlay(alignment: .leading) {
                    coreShape(2).fill(palette.primary).frame(width: seg).offset(x: (width - seg) * p)
                }
        }
        .frame(width: width, height: Space.s1)
        .clipShape(coreShape(2))
        .accessibilityHidden(true)
    }
}
