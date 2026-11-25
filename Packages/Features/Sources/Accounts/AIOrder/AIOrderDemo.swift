#if DEBUG
import CoreKit
import Foundation

/// Debug only: the made-up data of the approved AI order mockup (`Designs/core/0-10/screens/09-accounts.js`), on the demo's
/// stand-in service. No real names, keys or machines.
enum AIOrderDemo {
    static func providers() -> [ProviderItem] {
        func sub(_ id: String, _ name: String, _ harness: String, _ login: String = "browser_code") -> ProviderItem {
            ProviderItem(
                id: id, name: name, harness: harness, authVar: "TOKEN", baseURL: "https://example.invalid",
                delivery: ["env"], loginMethods: [login], models: [], pricedAt: nil, builtin: true)
        }
        func key(_ id: String, _ name: String, _ harness: String = "claude") -> ProviderItem {
            ProviderItem(
                id: id, name: name, harness: harness, authVar: "API_KEY", baseURL: "https://example.invalid",
                delivery: ["gateway"], loginMethods: ["paste"],
                models: [ModelPriceItem(id: "\(id)-model", inputMicro: 3_000_000, outputMicro: 15_000_000)],
                pricedAt: "2026-11-19", builtin: id == "anthropic")
        }
        // A Core 105 preset: its key page and hint come from the Core.
        func preset(_ id: String, _ name: String) -> ProviderItem {
            var p = key(id, name, "opencode")
            (p.preset, p.keyURL, p.keyHint) = (true, "https://vercel.com/ai-gateway", "vck_")
            return p
        }
        return [
            sub("claude-sub", "Claude subscription", "claude"),
            sub("codex-sub", "Codex subscription", "codex", "device_code"),
            sub("agy-sub", "Antigravity", "agy", "runner_login"),
            sub("opencode-sub", "OpenCode", "opencode", "runner_login"),
            key("anthropic", "Anthropic API"), key("openai", "OpenAI API", "codex"), key("google", "Gemini API", "agy"),
            key("openrouter", "OpenRouter"), key("aimlapi", "AIMLAPI"), key("groq", "Groq"),
            key("deepseek", "DeepSeek"),
            key("mistral", "Mistral"), key("xai", "xAI"), key("apinex", "APInex"), preset("vercel", "Vercel AI Gateway"),
        ]
    }

    static func accounts(now: Date, limitHit: Bool) -> [AccountItem] {
        func a(
            _ id: Int64, _ label: String, _ provider: String, state: String = "active", until: Date? = nil,
            spend: (Int64, Int64)? = nil, week: Double? = nil
        ) -> AccountItem {
            // The Core's own meter, as it would answer for each row of the mockup.
            var meter: AccountMeterItem?
            if let week {
                meter = AccountMeterItem(
                    state: week >= 1 ? "limit_hit" : "ready", stateUntil: week >= 1 ? until : nil,
                    fraction: min(week, 1),
                    used: (min(week, 1) * 100).rounded(), limit: 100, unit: "percent", window: "week", resetsAt: until)
            } else if let spend {
                meter = AccountMeterItem(
                    state: "ready", fraction: Double(spend.0) / Double(spend.1), used: Double(spend.0),
                    limit: Double(spend.1), unit: "usd_micros", window: "month")
            }
            var item = AccountItem(
                id: id, provider: provider, label: label, maskedTail: "demo", baseURL: "", state: state,
                stateReason: nil,
                stateUntil: until, cap: 4, lastUsedAt: now.addingTimeInterval(-600),
                createdAt: now.addingTimeInterval(-9_000_000), monthSpendUSDMicros: spend?.0,
                monthLimitUSDMicros: spend?.1,
                health: week.map {
                    AccountHealthItem(windows: [PlanWindowItem(name: "seven_day", utilization: $0, resetsAt: until)])
                })
            item.meter = meter
            return item
        }
        let friday = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 6), matchingPolicy: .nextTime)
        return [
            limitHit
                ? a(1, "claude", "claude-sub", state: "limited", until: friday, week: 1)
                : a(1, "claude", "claude-sub", week: 0.38),
            a(2, "codex", "codex-sub", week: 0.62),
            a(3, "anthropic", "anthropic", spend: (12_000_000, 50_000_000)).named("Work API"),
            a(4, "openrouter", "openrouter", spend: (4_000_000, 50_000_000)),
            a(5, "antigravity", "agy-sub", state: "signing_in"),
        ]
    }
}

extension AccountsDemo.Service {
    /// Turns the stand-in into the mockup's: five accounts in an AI order, and the 14 providers of the Add cards.
    func useAIOrderSample(limitHit: Bool) {
        order010 = true
        accountList = AIOrderDemo.accounts(now: now, limitHit: limitHit)
        poolList = []
        chainList = []
        chainBindingList = []
        orderEntries = accountList.map { AIOrderEntry(account: $0.id, provider: $0.provider, harness: nil, model: nil) }
        agentOrders = [AIOrderOverride(agent: "birch", items: [orderEntries[2]])]
        // The mockup's two Claude limits: 900 messages a week, 60 every 5 hours.
        for (id, period, cap, warn) in [(21, "week", 900, 80), (22, "hour5", 60, 90)] as [(Int64, String, Int64, Int64)]
        {
            budgetList.append(
                BudgetItem(
                    id: id, kind: "provider", subject: "claude-sub", company: nil, period: period, periodKey: period,
                    tokenCap: 0, usdCap: nil, spent: 0, usdSpent: 0, held: 0, raised: 0, raisedUSD: 0, warnAt: warn,
                    hardStop: true, exhausted: false, messageCap: cap))
        }
    }

    func aiOrderSupported() async -> Bool { order010 }
    func aiOrder() async throws -> AIOrderDoc { AIOrderDoc(items: orderEntries, overrides: agentOrders) }
    func setAIOrder(agent: String?, items: [AIOrderPut.Item]) async throws -> AIOrderDoc {
        let entries = items.map { i in
            AIOrderEntry(
                account: i.account, provider: accountList.first { $0.id == i.account }?.provider, harness: nil,
                model: i.model)
        }
        if let agent {
            agentOrders.removeAll { $0.agent == agent }
            agentOrders.append(AIOrderOverride(agent: agent, items: entries))
        } else {
            orderEntries = entries
        }
        return try await aiOrder()
    }
    func clearAIOrder(agent: String) async throws { agentOrders.removeAll { $0.agent == agent } }
    func modelCount(account: Int64) async -> Int? { order010 ? 14 : nil }
    func loginScreen(_ id: String) async throws -> LoginScreen {
        var lines = ["Sign in to your account", "Open the page below and approve the sign-in.", "Then type OK here."]
        if guidedSentAt != nil { lines += ["Waiting for the page to confirm…"] }
        return LoginScreen(lines: lines, url: nil, code: nil)
    }
    func sendLoginInput(_ id: String, line: String) async throws { guidedSentAt = Date() }
    func boundRunners() async -> [Int64: String] { order010 ? [2: "r_linux01"] : [:] }
    func accountMeters() async -> [Int64: AccountMeterItem] {
        Dictionary(uniqueKeysWithValues: accountList.compactMap { a in a.meter.map { (a.id, $0) } })
    }
    func accountModels(account: Int64) async -> [ModelRowItem] {
        guard order010, let a = accountList.first(where: { $0.id == account }) else { return [] }
        let denied = deniedModels[account] ?? []
        let list = AIOrderDemo.providers().first { $0.id == a.provider }?.models ?? []
        return list.map {
            ModelRowItem(
                model: $0.id, allowed: !denied.contains($0.id), inputMicro: $0.inputMicro, outputMicro: $0.outputMicro)
        }
    }
    func setModelAllowed(account: Int64, model: String, allowed: Bool) async throws {
        if allowed { deniedModels[account]?.remove(model) } else { deniedModels[account, default: []].insert(model) }
    }
    func loginExtra(_ id: String) async -> LoginExtra {
        LoginExtra(code: loginProvider == "codex-sub" ? "K7QM-4XZP" : nil)
    }

    func namesSupported() async -> Bool { order010 }
    func setAccountName(account: Int64, name: String?) async throws -> AccountItem {
        guard let i = accountList.firstIndex(where: { $0.id == account }) else {
            throw CoreError.http(status: 404, code: "not_found", message: "no such account")
        }
        accountList[i].displayName = name.flatMap(AccountNames.clean)
        return accountList[i]
    }
    func createAccount(
        provider: String, label: String, key: String, runners: [String], placement p: ResolvedPlacement
    ) async throws -> AccountItem {
        let a = try await createAccount(provider: provider, label: label, key: key, runners: runners)
        guard let n = p.displayName else { return a }
        return try await setAccountName(account: a.id, name: n)
    }
    func startLogin(provider: String, label: String, displayName: String?, runner: String?) async throws -> LoginItem {
        loginName = displayName
        return try await startLogin(provider: provider, label: label, runner: runner)
    }
}

extension AccountItem {
    fileprivate func named(_ n: String) -> AccountItem {
        var a = self
        a.displayName = n
        return a
    }
}
#endif
