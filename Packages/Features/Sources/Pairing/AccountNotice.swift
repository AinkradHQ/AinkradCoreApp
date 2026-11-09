import Foundation

/// What an account event says in plain words, for the bell and for macOS banners. Pure: names come in as closures.
struct AccountNotice: Equatable {
    /// The push kind a banner belongs to (`account_health`, `account_failover`, `account_expired`); nil for bell only.
    let pushKind: String?
    /// One bell entry per account and event, so a new one replaces the old.
    let id: String
    let isAlarm: Bool
    let title: String
    let sub: String?

    /// Kinds this build words. Others (`account.login.*`) are not announced.
    static let kinds: Set<String> = [
        "account.limited", "account.health", "account.failover", "account.budget", "account.expired", "alarm.raised",
        "alarm.cleared", "terminal.reap_warning",
    ]

    /// The bell entry an `alarm.cleared` event takes away (the one `alarm.raised` made), if this build worded it. Core's
    /// `alarm.cleared` is `{alarm, value, threshold}` for backup_age, cert_expiry and disk_free (health.rs); it never clears
    /// `failover_storm`, which is raised once per window and has no cleared event. So today this removes nothing a Core
    /// sends; it is kept for the day Core clears the storm.
    static func clearedID(kind: String, fields f: [String: String]) -> String? {
        kind == "alarm.cleared" && f["alarm"] == "failover_storm" ? "account-storm" : nil
    }

    /// A short toast for events that are not an account's, not kept in the bell. `reap_warning` is `{terminal, reason, grace_secs,
    /// reap_at}`; it names the terminal when the app knows it. There is no "Keep it" button: the client has no operation that
    /// keeps a terminal alive (using it does).
    static func toast(kind: String, fields f: [String: String] = [:], terminal: (String) -> String? = { _ in nil })
        -> String?
    {
        guard kind == "terminal.reap_warning" else { return nil }
        let name = f["terminal"].flatMap(terminal) ?? "A terminal"
        let why = f["reason"] == "orphan" ? "no window is attached to it" : "nobody has used it for a while"
        return "\(name) will close soon: \(why)."
    }

    /// `fields` is the event payload with every value as text. `account` names an account id ("Claude account Work"),
    /// `pool` a pool id; an id nobody knows reads as "An account".
    static func make(
        kind: String, fields f: [String: String], account: (Int64) -> String?, pool: (Int64) -> String?,
        now: Date = Date()
    ) -> AccountNotice? {
        func who(_ key: String) -> String { f[key].flatMap(Int64.init).flatMap(account) ?? "An account" }
        let acct = f["account"] ?? "0"
        switch kind {
        case "account.limited":
            let limit =
                switch f["class"] {
                case "quota": "quota"
                case "plan_limit": "plan limit"
                default: "rate limit"
                }
            return AccountNotice(
                pushKind: nil, id: "account-limited-\(acct)", isAlarm: false,
                title: "\(who("account")) hit its \(limit)", sub: until(f["until"], now: now))
        case "account.health":
            let why =
                f["reason"] == "auth_suspected"
                ? "The provider may have refused its key." : "The provider keeps answering with errors."
            return AccountNotice(
                pushKind: "account_health", id: "account-health-\(acct)", isAlarm: true,
                title: "\(who("account")) is not working", sub: why)
        case "account.failover":
            let from = who("from_account")
            let title: String
            if f["to_session"] == nil {
                title = "\(from) hit its limit and no other account was left"
            } else if f["to_account"] != nil {
                title = "\(from) hit its limit, moved to \(who("to_account"))"
            } else {
                title = "\(from) hit its limit, a session is waiting for an account"
            }
            return AccountNotice(
                pushKind: "account_failover", id: "account-failover-\(f["run"] ?? f["from_session"] ?? acct)",
                isAlarm: false, title: title, sub: nil)
        case "account.budget":
            let subject = f["subject"].flatMap(Int64.init)
            let name =
                f["subject_kind"] == "pool"
                ? subject.flatMap(pool).map { "\($0) pool" } ?? "A pool"
                : subject.flatMap(account) ?? "An account"
            let used = f["state"] == "exhausted"
            return AccountNotice(
                pushKind: nil, id: "account-budget-\(f["subject_kind"] ?? "")-\(f["subject"] ?? "")",
                isAlarm: used, title: used ? "\(name) used up its budget" : "\(name) is close to its budget",
                sub: used ? "Nothing more runs on it until the budget resets or is raised." : nil)
        case "account.expired":
            return AccountNotice(
                pushKind: "account_expired", id: "account-expired-\(acct)", isAlarm: true,
                title: "\(who("account")) was turned off",
                sub: "The provider refused its key. Sign in again or add a new key.")
        case "alarm.raised" where f["alarm"] == "failover_storm":
            return AccountNotice(
                pushKind: nil, id: "account-storm", isAlarm: true, title: "Too many account switches in a short time",
                sub: "Ainkrad stopped moving your runs between accounts for a while.")
        default: return nil
        }
    }

    private static func until(_ text: String?, now: Date) -> String? {
        guard let text,
            let date = (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(text, strategy: .iso8601)),
            date > now
        else { return nil }
        return "Back at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// The banner text for a push kind: a title and a line, the same words as the bell.
    var banner: (title: String, body: String)? { pushKind == nil ? nil : (title, sub ?? "") }
}
