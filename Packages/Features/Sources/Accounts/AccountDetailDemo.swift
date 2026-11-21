#if DEBUG
import Foundation

/// Debug only: the account page's six states on the made-up data of the approved mockup
/// (`Designs/core/0-10/review/account-details`). No real names, keys or machines.
enum AccountDetailDemo {
    static let scenes = [
        "detail-healthy", "detail-full", "detail-api", "detail-signed-out", "detail-off", "detail-checking",
        "detail-checked",
    ]

    static func accounts(_ scene: String, now: Date) -> [AccountItem] {
        let thursday = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 5), matchingPolicy: .nextTime)
        func a(
            _ id: Int64, _ name: String, _ provider: String, tail: String = "", state: String = "active",
            five: Double? = nil, week: Double? = nil, fiveReset: TimeInterval = 8_040, live: Int64 = 0,
            spend: (Int64, Int64)? = nil
        ) -> AccountItem {
            var windows: [PlanWindowItem] = []
            if let five {
                windows.append(
                    PlanWindowItem(name: "five_hour", utilization: five, resetsAt: now.addingTimeInterval(fiveReset)))
            }
            if let week { windows.append(PlanWindowItem(name: "seven_day", utilization: week, resetsAt: thursday)) }
            var item = AccountItem(
                id: id, provider: provider, label: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                displayName: name, maskedTail: tail, baseURL: "", state: state, stateReason: nil, stateUntil: nil,
                cap: 4,
                lastUsedAt: now.addingTimeInterval(-120),
                createdAt: now.addingTimeInterval(provider == "anthropic" ? -1_555_200 : -3_600),
                live: live, monthSpendUSDMicros: spend?.0, monthLimitUSDMicros: spend?.1,
                health: five == nil
                    ? nil : AccountHealthItem(lastSuccessAt: now.addingTimeInterval(-120), windows: windows))
            if provider == "anthropic" { item.lastTest = (now.addingTimeInterval(-9_600), "ok") }
            return item
        }
        var studio = a(1, "Studio plan", "claude-sub", five: 0.62, week: 0.41, live: 2)
        switch scene {
        case "detail-full":
            studio = a(1, "Studio plan", "claude-sub", state: "limited", five: 1, week: 0.74, fiveReset: 4_800)
            studio.meter = AccountMeterItem(
                state: "limit_hit", stateUntil: now.addingTimeInterval(4_800), fraction: 1, used: 100, limit: 100,
                unit: "percent", window: "five_hours", resetsAt: now.addingTimeInterval(4_800))
        case "detail-signed-out":
            studio = a(1, "Studio plan", "claude-sub", five: 0.62, week: 0.41)
            studio.health?.authStreak = 1
            studio.health?.lastSuccessAt = now.addingTimeInterval(-4_000)
            studio.lastTest = (now.addingTimeInterval(-4_000), "auth_failed")
        case "detail-off":
            studio = a(1, "Studio plan", "claude-sub", state: "disabled", five: 0.31, week: 0.41)
            studio.health?.lastSuccessAt = now.addingTimeInterval(-64_000)
        default: break
        }
        return [
            studio, a(2, "Side plan", "claude-sub", five: 0.18, week: 0.2, fiveReset: 12_000),
            a(
                3, "Studio API", "anthropic", tail: "7Qx2", live: scene == "detail-api" ? 1 : 0,
                spend: (52_800_000, 80_000_000)),
            a(4, "Gemini", "google", tail: "Lm4c", spend: (6_400_000, 80_000_000)),
        ]
    }

    static func data(_ scene: String, account: Int64, now: Date) -> AccountDetailData {
        let today = AccountDetailWire.utc.startOfDay(for: now)
        func days(_ v: [Double], usd: Bool) -> [AccountDayItem] {
            v.enumerated().map { i, x in
                AccountDayItem(
                    day: AccountDetailWire.utc.date(byAdding: .day, value: i - 6, to: today)!,
                    tokens: usd ? Int64(x * 50_000) : Int64(x), usdMicros: usd ? Int64(x * 1_000_000) : 0)
            }
        }
        func s(
            _ id: String, _ title: String, _ model: String?, _ runner: String, _ tokens: Int64, _ ago: TimeInterval,
            live: Bool = false, usd: Double? = nil, moved: Bool = false
        ) -> AccountSessionItem {
            AccountSessionItem(
                id: id, title: title, model: model, runnerName: runner, tokens: tokens,
                usdMicros: usd.map { Int64($0 * 1_000_000) }, startedAt: now.addingTimeInterval(-ago - 600),
                endedAt: live ? nil : now.addingTimeInterval(moved ? -4_000 : -ago), moved: moved)
        }
        if account == 3 {
            return AccountDetailData(
                days: days([4.10, 7.85, 2.20, 9.40, 6.15, 3.90, 7.60], usd: true),
                sessions: [
                    s(
                        "as_31", "Write tests for checkout", "claude-sonnet-4-5", "attic box", 412_000, 0, live: true,
                        usd: 1.24),
                    s(
                        "as_32", "Summarise the support inbox", "claude-haiku-4-5", "harbor mini", 96_000, 1_680,
                        usd: 0.08),
                    s("as_33", "Fix the login bug", "claude-opus-4-1", "This Mac", 238_000, 7_200, usd: 3.10),
                    s(
                        "as_34", "Draft the onboarding email", "claude-sonnet-4-5", "attic box", 55_000, 90_000,
                        usd: 0.19),
                ])
        }
        var week = [2.1e6, 3.4e6, 0.8e6, 5.2e6, 4.1e6, 1.9e6, 11.8e6]
        if scene == "detail-off" { (week[5], week[6]) = (3.6e6, 0) }
        if scene == "detail-signed-out" { week[6] = 6.2e6 }
        let away = ["detail-full", "detail-signed-out"].contains(scene)
        let off = scene == "detail-off"
        return AccountDetailData(
            days: days(week, usd: false),
            sessions: [
                s(
                    "as_11", "Brain import: learning your notes", "claude-opus-4-1", "attic box", 4_100_000,
                    off ? 64_000 : 120, live: !away && !off, moved: away),
                s(
                    "as_12", "Fix the login bug", "claude-sonnet-4-5", "harbor mini", 182_000, off ? 65_000 : 360,
                    live: !away && !off, moved: away),
                s("as_13", "Write tests for checkout", "claude-sonnet-4-5", "attic box", 69_800, 2_460),
                s("as_14", "Tidy the release notes", nil, "This Mac", 32_000, 3_600),
                s("as_15", "Rename the billing module", "claude-opus-4-1", "harbor mini", 76_500, 10_800),
                s("as_16", "Plan the search page", "claude-opus-4-1", "attic box", 1_200_000, 90_000),
            ],
            lastCheck: AccountCheckItem(
                at: now.addingTimeInterval(-720), ok: true, runnerName: "attic box", answerMs: 3_200))
    }

    static func costs(now: Date) -> [CostItem] {
        let rows: [(String, Int64)] = [
            ("claude-opus-4-1", 20_100_000), ("claude-opus-4-1", 15_800_000), ("claude-sonnet-4-5", 9_400_000),
            ("claude-sonnet-4-5", 5_200_000), ("claude-haiku-4-5", 2_300_000),
        ]
        return rows.enumerated().map { i, r in
            CostItem(
                id: Int64(500 + i), at: now.addingTimeInterval(-Double(i) * 3_600), accountID: 3, provider: "anthropic",
                model: r.0, session: "as_3\(i)", input: 40_000, output: 8_000, cache: 0, costMicros: r.1,
                basis: "list_price", approximate: false)
        }
    }
}

extension AccountsDemo.Service {
    /// The account page sample: four accounts in an AI order, with the scene's state on Studio plan.
    func useDetailSample(_ scene: String) {
        order010 = true
        detailScene = scene
        accountList = AccountDetailDemo.accounts(scene, now: now)
        poolList = []
        chainList = []
        chainBindingList = []
        budgetList = []
        limitRows = []
        orderEntries = accountList.map { AIOrderEntry(account: $0.id, provider: $0.provider, harness: nil, model: nil) }
        agentOrders = []
        detailCosts = AccountDetailDemo.costs(now: now)
    }

    func detailData(_ a: AccountItem, now: Date) async -> AccountDetailData {
        guard let detailScene else { return AccountDetailData() }
        return AccountDetailDemo.data(detailScene, account: a.id, now: now)
    }

    /// A plan's check on the sample: three and a half seconds on attic box, then Claude answers.
    func check(account: Int64) async throws -> PlanCheck {
        try await Task.sleep(for: .seconds(detailScene == nil ? 1 : 3.6))
        return PlanCheck(result: "ok", latencyMs: 3_200, runner: "attic box")
    }
}
#endif
