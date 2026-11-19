#if DEBUG
import CoreKit
import Foundation

/// Debug only: the made-up data of the approved AI order mockup (`Designs/core/0-10/screens/09-accounts.js`), on the demo's
/// stand-in service. No real names, keys or machines.
enum AIOrderDemo {
    static func providers() -> [ProviderItem] {
        func sub(_ id: String, _ name: String, _ harness: String) -> ProviderItem {
            ProviderItem(
                id: id, name: name, harness: harness, authVar: "TOKEN", baseURL: "https://example.invalid",
                delivery: ["env"], loginMethods: ["browser_code"], models: [], pricedAt: nil, builtin: true)
        }
        func key(_ id: String, _ name: String, _ harness: String = "claude") -> ProviderItem {
            ProviderItem(
                id: id, name: name, harness: harness, authVar: "API_KEY", baseURL: "https://example.invalid",
                delivery: ["gateway"], loginMethods: ["paste"],
                models: [ModelPriceItem(id: "\(id)-model", inputMicro: 3_000_000, outputMicro: 15_000_000)],
                pricedAt: "2026-11-19", builtin: id == "anthropic")
        }
        return [
            sub("claude-sub", "Claude subscription", "claude"), sub("codex-sub", "Codex subscription", "codex"),
            sub("agy-sub", "Antigravity", "agy"), sub("opencode-sub", "OpenCode", "claude"),
            key("anthropic", "Anthropic API"), key("openai", "OpenAI API", "codex"), key("google", "Gemini API", "agy"),
            key("openrouter", "OpenRouter"), key("aimlapi", "AIMLAPI"), key("groq", "Groq"),
            key("deepseek", "DeepSeek"),
            key("mistral", "Mistral"), key("xai", "xAI"), key("apinex", "APInex"),
        ]
    }

    static func accounts(now: Date, limitHit: Bool) -> [AccountItem] {
        func a(
            _ id: Int64, _ label: String, _ provider: String, state: String = "active", until: Date? = nil,
            spend: (Int64, Int64)? = nil, week: Double? = nil
        ) -> AccountItem {
            AccountItem(
                id: id, provider: provider, label: label, maskedTail: "demo", baseURL: "", state: state,
                stateReason: nil,
                stateUntil: until, cap: 4, lastUsedAt: now.addingTimeInterval(-600),
                createdAt: now.addingTimeInterval(-9_000_000), monthSpendUSDMicros: spend?.0,
                monthLimitUSDMicros: spend?.1,
                health: week.map {
                    AccountHealthItem(windows: [PlanWindowItem(name: "seven_day", utilization: $0, resetsAt: until)])
                })
        }
        let friday = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 6), matchingPolicy: .nextTime)
        return [
            limitHit
                ? a(1, "claude", "claude-sub", state: "limited", until: friday, week: 1)
                : a(1, "claude", "claude-sub", week: 0.38),
            a(2, "codex", "codex-sub", week: 0.62),
            a(3, "anthropic", "anthropic", spend: (12_000_000, 50_000_000)),
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
    func loginCode(_ id: String) async -> String? { loginProvider == "codex-sub" ? "K7QM-4XZP" : nil }
}
#endif
