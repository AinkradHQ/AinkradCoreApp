import CoreKit
import Foundation

// HAND-WRITTEN WIRE for the account page (Core API minor 98): the per-account daily series, the account's latest
// sessions and its last check. Read leniently with raw requests; below minor 98 the page degrades: the chart shows the
// provider's days, the sessions come from `/agent-sessions`, and the check details are left out.

/// API minor that serves `?account=` on `/costs/series`, `/accounts/{id}/sessions` and `last_check`.
let coreMinorAccountUsage: Int32 = 98

/// One day of an account's use: tokens, and dollars (an API key only; a plan bills nothing).
struct AccountDayItem: Equatable, Sendable {
    let day: Date
    let tokens: Int64
    let usdMicros: Int64
}

/// One session that ran on the account. `model` nil: the harness's default (a plan runs Claude's default).
struct AccountSessionItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let model: String?
    let runnerName: String?
    let tokens: Int64
    let usdMicros: Int64?
    let startedAt: Date
    let endedAt: Date?
    /// It ran out of room here and went on on another account (`moved_to_account`; `failed_over_to` below 98).
    let moved: Bool
    var live: Bool { endedAt == nil }
}

/// The account's last check (`last_check`): a plan's one short message, or a key's free request.
struct AccountCheckItem: Equatable, Sendable {
    let at: Date
    let ok: Bool
    let runnerName: String?
    let answerMs: Int64?
}

/// What the account page reads beyond the account row.
struct AccountDetailData: Equatable, Sendable {
    /// The last 7 days, oldest first; nil when the Core gave none (no admin, or no route).
    var days: [AccountDayItem]?
    /// True on an older Core: `days` are the whole provider's, not this account's.
    var daysOfProvider = false
    var sessions: [AccountSessionItem] = []
    var lastCheck: AccountCheckItem?
}

// MARK: lenient rows

private struct DayRow: Decodable {
    let day: String
    let provider: String?
    let totalTokens: Int64?
    let costUsdMicros: Int64?
    enum CodingKeys: String, CodingKey {
        case day, provider
        case totalTokens = "total_tokens"
        case costUsdMicros = "cost_usd_micros"
    }
}

private struct SessionRow: Decodable {
    let sessionId: String
    let title: String?
    let model: String?
    let runnerName: String?
    let tokens: Int64?
    let usdMicros: Int64?
    let startedAt: String?
    let endedAt: String?
    let movedToAccount: Int64?
    enum CodingKeys: String, CodingKey {
        case title, model, tokens
        case sessionId = "session_id"
        case runnerName = "runner_name"
        case usdMicros = "usd_micros"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case movedToAccount = "moved_to_account"
    }
}

/// `/agent-sessions` (every Core): the fallback when the account's own list is not served.
private struct AgentRow: Decodable {
    struct Usage: Decodable {
        let input: Int64?
        let output: Int64?
        let cacheRead: Int64?
        let cacheWrite: Int64?
        let costUsdMicros: Int64?
        enum CodingKeys: String, CodingKey {
            case input, output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
            case costUsdMicros = "cost_usd_micros"
        }
    }
    let id: String
    let runner: String?
    let model: String?
    let account: Int64?
    let title: String?
    let usage: Usage?
    let createdAt: String?
    let endedAt: String?
    let failedOverTo: String?
    enum CodingKeys: String, CodingKey {
        case id, runner, model, account, title, usage
        case createdAt = "created_at"
        case endedAt = "ended_at"
        case failedOverTo = "failed_over_to"
    }
}

private struct CheckProbe: Decodable {
    struct Check: Decodable {
        let at: String
        let ok: Bool
        let runnerName: String?
        let answerMs: Int64?
        enum CodingKeys: String, CodingKey {
            case at, ok
            case runnerName = "runner_name"
            case answerMs = "answer_ms"
        }
    }
    let lastCheck: Check?
    enum CodingKeys: String, CodingKey { case lastCheck = "last_check" }
}

enum AccountDetailWire {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Seven days ending today (UTC, as the Core keys them), oldest first; a day with no row is zero. `provider` keeps
    /// only that provider's rows (the older Core's series is per provider).
    static func days(_ data: Data, provider: String?, now: Date) -> [AccountDayItem]? {
        guard let rows = try? JSONDecoder().decode([DayRow].self, from: data) else { return nil }
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = utc.startOfDay(for: now)
        return (0..<7).reversed().map { back in
            let d = utc.date(byAdding: .day, value: -back, to: today)!
            let key = f.string(from: d)
            let mine = rows.filter { $0.day == key && (provider == nil || $0.provider == provider) }
            return AccountDayItem(
                day: d, tokens: mine.reduce(0) { $0 + ($1.totalTokens ?? 0) },
                usdMicros: mine.reduce(0) { $0 + ($1.costUsdMicros ?? 0) })
        }
    }

    static func sessions(_ data: Data) -> [AccountSessionItem] {
        ((try? JSONDecoder().decode([SessionRow].self, from: data)) ?? []).map {
            AccountSessionItem(
                id: $0.sessionId, title: $0.title, model: cleanModel($0.model), runnerName: $0.runnerName,
                tokens: $0.tokens ?? 0, usdMicros: $0.usdMicros,
                startedAt: WireDate.parse($0.startedAt) ?? .distantPast, endedAt: WireDate.parse($0.endedAt),
                moved: $0.movedToAccount != nil)
        }
    }

    /// The account's rows of `/agent-sessions`, newest first, with runner ids named from `runners`.
    static func agentSessions(_ data: Data, account: Int64, runners: [String: String]) -> [AccountSessionItem] {
        ((try? JSONDecoder().decode([AgentRow].self, from: data)) ?? []).filter { $0.account == account }.map { r in
            let u = r.usage
            let tokens = [u?.input, u?.output, u?.cacheRead, u?.cacheWrite].compactMap { $0 }.reduce(0, +)
            return AccountSessionItem(
                id: r.id, title: r.title, model: cleanModel(r.model), runnerName: r.runner.flatMap { runners[$0] },
                tokens: tokens, usdMicros: u?.costUsdMicros, startedAt: WireDate.parse(r.createdAt) ?? .distantPast,
                endedAt: WireDate.parse(r.endedAt), moved: r.failedOverTo != nil)
        }
    }

    static func lastCheck(_ data: Data) -> AccountCheckItem? {
        guard let c = (try? JSONDecoder().decode(CheckProbe.self, from: data))?.lastCheck, let at = WireDate.parse(c.at)
        else { return nil }
        return AccountCheckItem(at: at, ok: c.ok, runnerName: c.runnerName, answerMs: c.answerMs)
    }

    /// The meter's old placeholder for "the harness's default" is never a model name.
    static func cleanModel(_ m: String?) -> String? {
        guard let m, !m.isEmpty, m != "unknown" else { return nil }
        return m
    }
}

extension LiveAccountsService {
    func detailData(_ a: AccountItem, now: Date) async -> AccountDetailData {
        let c = connection
        func get(_ target: String) async -> Data? { try? await c.signedRequest(method: "GET", target: target) }
        var out = AccountDetailData()
        if await c.serverSupports(minor: coreMinorAccountUsage) {
            async let series = get("/api/v1/costs/series?days=7&account=\(a.id)")
            async let list = get("/api/v1/accounts/\(a.id)/sessions?limit=12")
            async let row = get("/api/v1/accounts/\(a.id)")
            out.days = await series.flatMap { AccountDetailWire.days($0, provider: nil, now: now) }
            out.sessions = await list.map(AccountDetailWire.sessions) ?? []
            out.lastCheck = await row.flatMap(AccountDetailWire.lastCheck)
            return out
        }
        // An older Core: the provider's days, and the account's sessions picked out of the newest 200.
        async let series = get("/api/v1/costs/series?days=7")
        async let list = get("/api/v1/agent-sessions?limit=200")
        let names = ((try? await runners()) ?? []).reduce(into: [String: String]()) { $0[$1.id] = $1.name }
        out.days = await series.flatMap { AccountDetailWire.days($0, provider: a.provider, now: now) }
        out.daysOfProvider = true
        out.sessions = await list.map { AccountDetailWire.agentSessions($0, account: a.id, runners: names) } ?? []
        return out
    }
}

extension AccountsService {
    func detailData(_ a: AccountItem, now: Date) async -> AccountDetailData { AccountDetailData() }
}

extension AccountsModel {
    /// The page's chart, sessions and last check, again every 30 s while the page is open.
    func watchDetail(_ id: Int64) async {
        while !Task.isCancelled {
            guard let service, let a = account(id) else {
                // The account list is still loading (a new connection): look again shortly.
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }
            detailData[id] = await service.detailData(a, now: now())
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
