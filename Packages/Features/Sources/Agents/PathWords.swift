import Foundation

/// Paths in agent text, shortened for reading (N33): a long absolute path becomes `…/last`, and a run folder
/// `run-1794395097917` becomes `run-…917`. The full text always stays available as a tooltip.
enum PathWords {
    static func short(_ text: String) -> String {
        var s = text
        // Longest first: an absolute path of three or more parts, then run ids inside what is left.
        if let re = try? NSRegularExpression(pattern: #"(?:/[\w.@+~-]+){3,}/?"#) {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let r = Range(m.range, in: s) else { continue }
                let last = s[r].split(separator: "/").last.map(String.init) ?? ""
                s.replaceSubrange(r, with: "…/" + last)
            }
        }
        if let re = try? NSRegularExpression(pattern: #"run-(\d{4,})"#) {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let r = Range(m.range, in: s), let id = Range(m.range(at: 1), in: s) else { continue }
                s.replaceSubrange(r, with: "run-…" + s[id].suffix(3))
            }
        }
        return s
    }
}

/// How an approval looks in the transcript (N33): one card per approval, in one of four states.
enum ApprovalCardState: Equatable {
    case waiting(left: TimeInterval?)
    case allowed(at: Date?)
    case deniedByYou(at: Date?)
    case deniedNoAnswer(minutes: Int?)

    static func of(_ r: ApprovalRequest, now: Date, sessionOver: Bool) -> ApprovalCardState {
        switch r.status(now: now, sessionOver: sessionOver) {
        case .pending: .waiting(left: r.remaining(now: now))
        case .approved: .allowed(at: r.decidedAt)
        case .denied: .deniedByYou(at: r.decidedAt)
        case .expired: .deniedNoAnswer(minutes: r.timeoutSecs.map { max(1, $0 / 60) })
        }
    }

    /// The result words next to the card title; nil while it waits.
    var result: String? {
        switch self {
        case .waiting: nil
        case .allowed: "Approved"
        case .deniedByYou(let at): "Denied by you" + Self.time(at)
        case .deniedNoAnswer(let m): "Denied: no answer" + (m.map { " in \($0) min" } ?? "")
        }
    }

    private static func time(_ d: Date?) -> String {
        d.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
    }
}
