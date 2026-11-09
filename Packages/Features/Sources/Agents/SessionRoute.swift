import Foundation

/// Why a chain session has not started: every account its chain can use is resting, limited or at its cap.
public struct SessionWaiting: Equatable, Sendable {
    public var since: Date?
    public var until: Date
    public var why: String
    public init(since: Date? = nil, until: Date, why: String) {
        self.since = since
        self.until = until
        self.why = why
    }
}

/// Why an ended run could not move to another account.
public struct FailoverEnd: Equatable, Sendable {
    public var result: String
    public var why: String?
    public var reasons: [String]
    public init(result: String, why: String? = nil, reasons: [String] = []) {
        self.result = result
        self.why = why
        self.reasons = reasons
    }
}

/// Where the scheduler put a session: its chain and step, account, run and attempt. Only admins are given any of it, so a
/// session read by another device has no route and nothing here shows.
public struct SessionRoute: Equatable, Sendable {
    public var agent: String?
    public var chainID: Int64?
    public var chainPos: Int?
    /// One word per chain step as the session began, e.g. `claude · sonnet`.
    public var steps: [String]
    public var account: Int64?
    public var repicked: Int?
    public var upstreamClass: String?
    public var waiting: SessionWaiting?
    public var run: String?
    public var attempt: Int?
    public var failoverOf: String?
    public var failedOverTo: String?
    public var failoverClass: String?
    public var ended: FailoverEnd?

    public init(
        agent: String? = nil, chainID: Int64? = nil, chainPos: Int? = nil, steps: [String] = [], account: Int64? = nil,
        repicked: Int? = nil, upstreamClass: String? = nil, waiting: SessionWaiting? = nil, run: String? = nil,
        attempt: Int? = nil, failoverOf: String? = nil, failedOverTo: String? = nil, failoverClass: String? = nil,
        ended: FailoverEnd? = nil
    ) {
        self.agent = agent
        self.chainID = chainID
        self.chainPos = chainPos
        self.steps = steps
        self.account = account
        self.repicked = repicked
        self.upstreamClass = upstreamClass
        self.waiting = waiting
        self.run = run
        self.attempt = attempt
        self.failoverOf = failoverOf
        self.failedOverTo = failedOverTo
        self.failoverClass = failoverClass
        self.ended = ended
    }

    /// A run that moved at least once, or can: it has attempts worth listing.
    public var moved: Bool { failoverOf != nil || failedOverTo != nil }
}

/// Plain sentences for a session's route. Pure, so the pane, the tiles and the tests agree.
public enum SessionCues {
    /// `daily · step 2 of 3`, or `Chain step 2 of 3` when the chain's name is not known here.
    public static func chain(_ r: SessionRoute, name: String?) -> String? {
        guard r.chainID != nil || !r.steps.isEmpty else { return nil }
        let step = r.chainPos.map { "step \($0 + 1)" + (r.steps.isEmpty ? "" : " of \(r.steps.count)") }
        return [name ?? "Chain", step].compactMap { $0 }.joined(separator: " · ")
    }

    /// The harness and model of the step the run sits on.
    public static func step(_ r: SessionRoute) -> String? {
        guard let p = r.chainPos, r.steps.indices.contains(p) else { return nil }
        return r.steps[p]
    }

    /// `14:00` today, `Nov 9, 14:00` on another day.
    public static func clock(_ d: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let same = calendar.isDate(d, inSameDayAs: now)
        var style =
            same ? Date.FormatStyle().hour().minute() : Date.FormatStyle().month(.abbreviated).day().hour().minute()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return d.formatted(style)
    }

    /// The banner for a session that waits for an account.
    public static func waiting(
        _ w: SessionWaiting, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> (
        title: String, text: String
    ) {
        let why = sentence(w.why) ?? "Every account this chain can use is resting, limited or at its cap."
        let until = clock(w.until, now: now, calendar: calendar, locale: locale)
        let since =
            w.since.map { " It has waited since \(clock($0, now: now, calendar: calendar, locale: locale))." } ?? ""
        return ("Waiting for an account", "\(why) It tries again from \(until).\(since)")
    }

    /// What the provider last told this session's gateway; nil when all is well or unsaid.
    public static func upstream(_ cls: String?) -> String? {
        switch cls {
        case nil, "ok": nil
        case "rate_limited": "The provider is limiting this account for now."
        case "quota": "This account is out of quota."
        case "server_error": "The provider is having trouble."
        case "auth_failed": "The provider refused this account's sign-in."
        default: "The provider reported a problem."
        }
    }

    /// Why a run was moved off an attempt, to follow "This account ...".
    public static func reason(_ cls: String?) -> String {
        switch cls {
        case "rate_limited": "hit a rate limit"
        case "quota": "ran out of quota"
        case "auth": "needs signing in again"
        case "budget_pool": "reached its budget"
        default: "had a problem"
        }
    }

    /// "Moved to another account": on the attempt that was left, and on the one that took over.
    public static func moved(_ r: SessionRoute) -> (title: String, text: String)? {
        if let next = r.failedOverTo {
            return (
                "Moved to another account",
                "This account \(reason(r.failoverClass)). The run went on in session \(tail(next))."
            )
        }
        if r.failoverOf != nil {
            let n = r.attempt.map { " This is attempt \($0 + 1)." } ?? ""
            return ("Moved here from another account", "An earlier attempt had to give up its account.\(n)")
        }
        return nil
    }

    /// The last attempt of a run that could not move on.
    public static func notMoved(_ e: FailoverEnd, steps: [String] = []) -> (title: String, text: String)? {
        guard e.result == "ended" else { return nil }
        let why = sentence(e.why) ?? "No other account was available."
        return (
            "The run ended: no other account was available",
            ([why] + e.reasons.map { named($0, steps: steps) }.compactMap(sentence)).joined(separator: " ")
        )
    }

    /// `entry 2: at its cap` becomes `claude · opus: at its cap`: the chain step by name, never by number.
    static func named(_ reason: String, steps: [String]) -> String {
        guard let r = reason.range(of: #"^entry (\d+)"#, options: [.regularExpression, .caseInsensitive]),
            let n = Int(reason[r].dropFirst(6))
        else { return reason }
        let name = steps.indices.contains(n - 1) ? steps[n - 1] : "Chain step \(n)"
        return name + reason[r.upperBound...]
    }

    /// `Two accounts refused to start before this one did.`
    public static func repicked(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n == 1
            ? "One account refused to start before this one did."
            : "\(n) accounts refused to start before this one did."
    }

    /// One attempt of a run, for the list: `Attempt 2 · claude · moved on: hit a rate limit`.
    public static func attempt(_ s: AgentSessionInfo) -> String {
        let r = s.route
        var parts = ["Attempt \((r?.attempt ?? 0) + 1)", s.harness]
        if r?.failedOverTo != nil {
            parts.append("moved on: \(reason(r?.failoverClass))")
        } else if s.live {
            parts.append("working now")
        } else if s.stoppedByBudget {
            parts.append("stopped: budget reached")
        } else if let o = s.outcome {
            parts.append(o.label.lowercased())
        }
        return parts.joined(separator: " · ")
    }

    private static func tail(_ id: String) -> String { id.count > 10 ? "…" + id.suffix(6) : id }

    /// A fixed phrase as a sentence: capital first, full stop last.
    static func sentence(_ s: String?) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        t = t.prefix(1).uppercased() + t.dropFirst()
        return t.hasSuffix(".") ? t : t + "."
    }
}
