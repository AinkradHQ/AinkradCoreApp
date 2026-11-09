#if DEBUG
import Admin
import AppKit
import CoreKit
import Foundation
import Shell

/// Debug only: every Accounts state of the prototype on sample data and a stand-in service, for screenshots and for the
/// reviewer to click through. Nothing here reaches a Core, and nothing here is a real key: the names are made up.
@MainActor
public final class AccountsDemo {
    final class Service: AccountsService, @unchecked Sendable {
        private let lock = NSLock()
        let now = Date()
        var providerList: [ProviderItem] {
            func p(
                _ id: String, _ name: String, _ h: String, _ v: String, _ base: String, _ m: [(String, Int64, Int64)]
            ) -> ProviderItem {
                ProviderItem(
                    id: id, name: name, harness: h, authVar: v, baseURL: base, delivery: ["env"],
                    loginMethods: ["paste"],
                    models: m.map { ModelPriceItem(id: $0.0, inputMicro: $0.1, outputMicro: $0.2) },
                    pricedAt: "2026-10-28", builtin: true)
            }
            return [
                p(
                    "anthropic", "Anthropic API", "claude", "ANTHROPIC_API_KEY", "https://api.anthropic.com",
                    [("claude-opus", 15_000_000, 75_000_000), ("claude-sonnet", 3_000_000, 15_000_000)]),
                p(
                    "openai", "OpenAI API (Codex)", "codex", "OPENAI_API_KEY", "https://api.openai.com",
                    [("gpt-5-codex", 1_250_000, 10_000_000)]),
                p(
                    "google", "Gemini API", "agy", "GEMINI_API_KEY", "https://generativelanguage.googleapis.com",
                    [("gemini-pro", 1_250_000, 10_000_000)]),
                ProviderItem(
                    id: "openrouter", name: "OpenRouter", harness: "claude", authVar: "ANTHROPIC_API_KEY",
                    baseURL: "https://openrouter.ai/api", delivery: ["gateway"], loginMethods: ["paste"],
                    models: [
                        ModelPriceItem(
                            id: "anthropic/claude-sonnet-4.5", inputMicro: 3_000_000, outputMicro: 15_000_000)
                    ], pricedAt: "2026-11-05", builtin: false, keyPrefix: "sk-or-v1-", testPath: "/key"),
                ProviderItem(
                    id: "claude-sub", name: "Claude subscription", harness: "claude",
                    authVar: "CLAUDE_CODE_OAUTH_TOKEN",
                    baseURL: "https://api.anthropic.com", delivery: ["env"], loginMethods: ["browser_code"], models: [],
                    pricedAt: nil, builtin: true),
            ]
        }
        lazy var accountList: [AccountItem] = [
            a(
                1, "claude-api-metered", "anthropic", "active", "x9Lm", 4, used: 7_200, test: (10_800, "ok"),
                limits: (2_000_000, 5_000_000), live: 2,
                health: AccountHealthItem(lastSuccessAt: now.addingTimeInterval(-120))),
            a(
                2, "claude-api-batch", "anthropic", "cooling", "k2Tq", 4, used: 1_100,
                reason: "Rate limit from the provider", until: 2_460, live: 0,
                health: AccountHealthItem(
                    lastSuccessAt: now.addingTimeInterval(-3_000), planStatus: "rejected",
                    windows: [
                        PlanWindowItem(name: "five_hour", utilization: 1.01, resetsAt: now.addingTimeInterval(2_460))
                    ])),
            a(
                3, "codex-api", "openai", "active", "b2Rt", 0, used: 660, test: (240, "auth_failed"), live: 1,
                health: AccountHealthItem(
                    failStreak: 3, lastSuccessAt: now.addingTimeInterval(-900), upstreamClass: "server_error")),
            a(
                4, "codex-api-ci", "openai", "unhealthy", "r7Vd", 2, used: 86_400,
                reason: "The provider refused the key", test: (3_600, "auth_failed"), live: 0,
                health: AccountHealthItem(authStreak: 2, upstreamClass: "auth_failed")),
            a(
                5, "gemini-key", "google", "active", "Qp0s", 4, used: 10_800, live: 3,
                health: AccountHealthItem(
                    lastSuccessAt: now.addingTimeInterval(-60), planStatus: "allowed_warning",
                    windows: [PlanWindowItem(name: "seven_day", utilization: 0.87, resetsAt: nil)])),
            a(
                6, "gemini-spare", "google", "disabled", "d1Zn", 4, used: 777_600,
                reason: "Disabled while the key is replaced"),
        ]
        func a(
            _ id: Int64, _ label: String, _ provider: String, _ state: String, _ tail: String, _ cap: Int64,
            used: TimeInterval, reason: String? = nil, until: TimeInterval? = nil,
            test: (TimeInterval, String)? = nil, limits: (Int64?, Int64?) = (nil, nil), live: Int64? = nil,
            health: AccountHealthItem? = nil
        ) -> AccountItem {
            AccountItem(
                id: id, provider: provider, label: label, maskedTail: tail, baseURL: "https://api.example.com",
                state: state,
                stateReason: reason, stateUntil: until.map { now.addingTimeInterval($0) }, cap: cap,
                lastUsedAt: now.addingTimeInterval(-used), createdAt: now.addingTimeInterval(-9_000_000),
                lastTest: test.map { (now.addingTimeInterval(-$0.0), $0.1) }, maxTokens: limits.0,
                maxUSDMicros: limits.1, live: live, health: health)
        }
        var poolList = [
            PoolItem(id: 1, name: "Default", provider: "anthropic", isDefault: true, members: [1, 2]),
            PoolItem(id: 2, name: "Client work", provider: "anthropic", isDefault: false, members: [1]),
            PoolItem(id: 3, name: "Default", provider: "openai", isDefault: true, members: [3, 4]),
            PoolItem(id: 4, name: "Default", provider: "google", isDefault: true, members: [5, 6]),
            PoolItem(id: 5, name: "Research", provider: "google", isDefault: false, members: []),
        ]
        var chainList = [
            ChainItem(
                id: 1, name: "daily", isDefault: true,
                entries: [
                    ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: "claude-sonnet"),
                    ChainEntryItem(pool: 3, provider: "openai", harness: "codex", model: nil),
                ]),
            ChainItem(
                id: 2, name: "careful", isDefault: false,
                entries: [ChainEntryItem(pool: 2, provider: "anthropic", harness: "claude", model: "claude-opus")]),
        ]
        var chainBindingList = [
            ChainBindingItem(agent: "atlas", chain: 2), ChainBindingItem(agent: "ines", chain: 2),
            ChainBindingItem(agent: "vesper", chain: 1),
        ]
        var gateState = GateState(mode: 1, providerAccounts: 1)
        func providers() async throws -> [ProviderItem] { providerList }
        func accounts() async throws -> [AccountItem] { accountList }
        func pools() async throws -> [PoolItem] { poolList }
        func gate() async throws -> GateState { gateState }
        func createPool(name: String, provider: String) async throws -> PoolItem {
            let p = PoolItem(
                id: Int64(poolList.count + 10), name: name, provider: provider, isDefault: false, members: [])
            poolList.append(p)
            return p
        }
        func deletePool(_ id: Int64) async throws { poolList.removeAll { $0.id == id } }
        func setDefaultPool(_ id: Int64) async throws {
            let provider = poolList.first { $0.id == id }?.provider
            poolList = poolList.map {
                PoolItem(
                    id: $0.id, name: $0.name, provider: $0.provider,
                    isDefault: $0.provider == provider ? $0.id == id : $0.isDefault, members: $0.members)
            }
        }
        func addMember(pool: Int64, account: Int64) async throws { edit(pool) { $0 + [account] } }
        func removeMember(pool: Int64, account: Int64) async throws { edit(pool) { $0.filter { $0 != account } } }
        private func edit(_ id: Int64, _ f: ([Int64]) -> [Int64]) {
            poolList = poolList.map {
                $0.id == id
                    ? PoolItem(
                        id: $0.id, name: $0.name, provider: $0.provider, isDefault: $0.isDefault, members: f($0.members)
                    ) : $0
            }
        }
        func chains() async throws -> [ChainItem] { chainList }
        private func entries(_ drafts: [ChainEntryDraft]) -> [ChainEntryItem] {
            drafts.map { d in
                let p = poolList.first { $0.id == d.pool }
                let h = providerList.first { $0.id == p?.provider }?.harness ?? "claude"
                return ChainEntryItem(pool: d.pool, provider: p?.provider ?? "", harness: h, model: d.model)
            }
        }
        func createChain(name: String, entries drafts: [ChainEntryDraft]) async throws -> ChainItem {
            let c = ChainItem(
                id: Int64(chainList.count + 10), name: name, isDefault: chainList.isEmpty, entries: entries(drafts))
            chainList.append(c)
            return c
        }
        func replaceChain(_ id: Int64, name: String, entries drafts: [ChainEntryDraft]) async throws -> ChainItem {
            let old = chainList.first { $0.id == id }
            let c = ChainItem(id: id, name: name, isDefault: old?.isDefault ?? false, entries: entries(drafts))
            chainList = chainList.map { $0.id == id ? c : $0 }
            return c
        }
        func deleteChain(_ id: Int64) async throws {
            chainList.removeAll { $0.id == id }
            chainBindingList.removeAll { $0.chain == id }
        }
        func setDefaultChain(_ id: Int64) async throws {
            chainList = chainList.map {
                ChainItem(id: $0.id, name: $0.name, isDefault: $0.id == id, entries: $0.entries)
            }
        }
        func chainBindings() async throws -> [ChainBindingItem] { chainBindingList }
        func bindAgent(_ agent: String, chain: Int64) async throws -> ChainBindingItem {
            chainBindingList.removeAll { $0.agent == agent }
            let b = ChainBindingItem(agent: agent, chain: chain)
            chainBindingList.append(b)
            return b
        }
        func unbindAgent(_ agent: String) async throws { chainBindingList.removeAll { $0.agent == agent } }
        func setState(account: Int64, state: String) async throws -> AccountItem {
            change(account) { ($0.label, state, $0.cap) }
        }
        func setCap(account: Int64, cap: Int64) async throws -> AccountItem {
            change(account) { ($0.label, $0.state, cap) }
        }
        private func change(_ id: Int64, _ f: (AccountItem) -> (String, String, Int64)) -> AccountItem {
            let old = accountList.first { $0.id == id }!
            let (label, state, cap) = f(old)
            let new = AccountItem(
                id: old.id, provider: old.provider, label: label, maskedTail: old.maskedTail, baseURL: old.baseURL,
                state: state, stateReason: nil, stateUntil: nil, cap: cap, lastUsedAt: old.lastUsedAt,
                createdAt: old.createdAt, lastTest: old.lastTest, maxTokens: old.maxTokens,
                maxUSDMicros: old.maxUSDMicros)
            accountList = accountList.map { $0.id == id ? new : $0 }
            return new
        }
        // A stand-in sign-in: the URL comes after a beat, the code takes another, then a new account appears.
        var loginStart: Date?
        var codeAt: Date?
        var loginLabel = "claude-plan"
        var loginFails = false
        func startLogin(provider: String, label: String, runner: String?) async throws -> LoginItem {
            if loginFails { throw CoreError.http(status: 409, code: "no_runner", message: "no runner can sign in") }
            loginStart = Date()
            codeAt = nil
            loginLabel = label
            return try await login("lg_demo")
        }
        func login(_ id: String) async throws -> LoginItem {
            let t = Date()
            var state = "starting"
            var account: Int64?
            if let c = codeAt {
                state = t.timeIntervalSince(c) > 1.5 ? "done" : "storing"
                if state == "done" {
                    if !accountList.contains(where: { $0.label == loginLabel }) {
                        accountList.append(a(7, loginLabel, "claude-sub", "active", "oat1", 1, used: 0))
                    }
                    account = 7
                }
            } else if let s = loginStart, t.timeIntervalSince(s) > 1.2 {
                state = "open_url"
            }
            return LoginItem(
                id: id, provider: "claude-sub", label: loginLabel, runner: "linux-01", state: state,
                url: state == "open_url" ? "https://claude.ai/login" : nil, reason: nil,
                accountID: account)
        }
        func sendLoginCode(_ id: String, code: String) async throws -> LoginItem {
            codeAt = Date()
            return try await login(id)
        }
        func cancelLogin(_ id: String) async throws { loginStart = nil }
        func b(
            _ id: Int64, _ kind: String, _ subject: String, _ period: String, cap: Int64, usd: Int64?, spent: Int64,
            usdSpent: Int64, stop: Bool = true, held: Int64 = 0
        ) -> BudgetItem {
            let ex = (cap > 0 && spent >= cap) || (usd.map { usdSpent >= $0 } ?? false)
            return BudgetItem(
                id: id, kind: kind, subject: subject, company: nil, period: period,
                periodKey: period == "day" ? "2026-11-06" : period == "month" ? "2026-11" : "total", tokenCap: cap,
                usdCap: usd, spent: spent, usdSpent: usdSpent, held: held, raised: 0, raisedUSD: 0, warnAt: 80,
                hardStop: stop, exhausted: ex)
        }
        lazy var budgetList: [BudgetItem] = [
            b(1, "account", "1", "day", cap: 0, usd: 25_000_000, spent: 210_000, usdSpent: 1_240_000),
            b(2, "account", "3", "day", cap: 0, usd: 20_000_000, spent: 1_240_000, usdSpent: 20_000_000),
            b(3, "pool", "2", "month", cap: 80_000_000, usd: 400_000_000, spent: 52_000_000, usdSpent: 182_000_000),
            b(4, "agent", "atlas", "week", cap: 12_000_000, usd: nil, spent: 10_400_000, usdSpent: 0, held: 320_000),
            b(
                5, "project", "kan-ainkrad", "month", cap: 40_000_000, usd: 150_000_000, spent: 9_100_000,
                usdSpent: 31_000_000, stop: false),
        ]
        func budgets() async throws -> [BudgetItem] { budgetList }
        func setBudget(_ d: BudgetDraft) async throws {
            budgetList.removeAll { $0.kind == d.kind && $0.subject == d.subject && $0.period == d.period }
            budgetList.append(
                b(
                    Int64(budgetList.count + 10), d.kind, d.subject, d.period, cap: d.tokenCap, usd: d.usdCap, spent: 0,
                    usdSpent: 0, stop: d.hardStop))
        }
        func deleteBudget(_ id: Int64) async throws { budgetList.removeAll { $0.id == id } }
        func raiseBudget(_ id: Int64, periodKey: String, tokens: Int64?, usdMicros: Int64?) async throws {
            budgetList = budgetList.map {
                guard $0.id == id else { return $0 }
                return BudgetItem(
                    id: $0.id, kind: $0.kind, subject: $0.subject, company: nil, period: $0.period,
                    periodKey: $0.periodKey, tokenCap: $0.tokenCap, usdCap: $0.usdCap, spent: $0.spent,
                    usdSpent: $0.usdSpent, held: $0.held, raised: tokens ?? 0, raisedUSD: usdMicros ?? 0,
                    warnAt: $0.warnAt, hardStop: $0.hardStop, exhausted: false)
            }
        }
        func saveProvider(_ p: ProviderDraft, replacing: Bool) async throws {}
        func deleteProvider(_ id: String) async throws {}
        var usageError: (any Error)?
        var limitRows: [LimitItem] = [
            LimitItem(
                unit: "tokens", windowSecs: 86_400, cap: 5_000_000, used: 1_900_000, warnPercent: 80, exhausted: false),
            LimitItem(
                unit: "tokens", windowSecs: 604_800, cap: 20_000_000, used: 17_400_000, warnPercent: 85,
                exhausted: false),
            LimitItem(
                unit: "messages", windowSecs: 18_000, cap: 200, used: 200, warnPercent: 75, exhausted: true),
        ]
        func setLimit(account: Int64, _ d: LimitDraft) async throws {
            limitRows.removeAll { $0.unit == d.unit && $0.windowSecs == d.windowSecs }
            limitRows.append(
                LimitItem(
                    unit: d.unit, windowSecs: d.windowSecs, cap: d.cap, used: 0, warnPercent: d.warnPercent,
                    exhausted: false))
        }
        func clearLimit(account: Int64, unit: String, windowSecs: Int64) async throws {
            limitRows.removeAll { $0.unit == unit && $0.windowSecs == windowSecs }
        }
        func usage() async throws -> [UsageItem] {
            if let usageError { throw usageError }
            func w(_ t: Int64, _ m: Int64, _ c: Int64) -> UsageWindowItem {
                UsageWindowItem(tokens: t, messages: m, costMicros: c)
            }
            return [
                UsageItem(
                    accountID: 1, fiveHours: w(210_000, 14, 1_240_000), sevenDays: w(3_100_000, 212, 18_420_000),
                    limitShare: 0.38, limitsExhausted: false, hasLimits: true, drops: 0,
                    companies: [
                        CompanyUsage(
                            company: "Ainkrad", fiveHours: w(200_000, 0, 1_100_000),
                            sevenDays: w(2_400_000, 0, 14_000_000)),
                        CompanyUsage(
                            company: "Client work", fiveHours: w(10_000, 0, 140_000),
                            sevenDays: w(700_000, 0, 4_420_000)),
                    ], limits: limitRows),
                UsageItem(
                    accountID: 3, fiveHours: w(980_000, 88, 4_100_000), sevenDays: w(1_240_000, 120, 6_900_000),
                    limitShare: 0.93, limitsExhausted: false, hasLimits: true, drops: 2,
                    companies: [
                        CompanyUsage(
                            company: "Ainkrad", fiveHours: w(980_000, 0, 4_100_000),
                            sevenDays: w(1_240_000, 0, 6_900_000))
                    ]),
                UsageItem(
                    accountID: 5, fiveHours: w(0, 0, 0), sevenDays: w(420_000, 31, 910_000), limitShare: 0,
                    limitsExhausted: false, hasLimits: false, drops: 0, companies: []),
            ]
        }
        func costs(account: Int64?) async throws -> [CostItem] {
            let models = [
                ("anthropic", "claude-sonnet-4-5", 1), ("openai", "gpt-5-codex", 3), ("google", "gemini-2.5-pro", 5),
            ]
            return (0..<18).map { i in
                let m = models[i % 3]
                let unpriced = i % 7 == 6
                return CostItem(
                    id: Int64(100 - i), at: now.addingTimeInterval(-Double(i) * 5_400), accountID: Int64(m.2),
                    provider: m.0, model: unpriced ? "gemini-2.5-flash" : m.1, session: "as_\(4_100 + i)",
                    input: Int64(12_000 + i * 900), output: Int64(1_800 + i * 70), cache: i % 2 == 0 ? 48_000 : 0,
                    costMicros: unpriced ? nil : Int64(41_000 + i * 2_300), basis: unpriced ? "unpriced" : "list_price",
                    approximate: i == 4)
            }
            .filter { account == nil || $0.accountID == account }
        }
        lazy var priceList: [PriceItem] = [
            PriceItem(
                provider: "anthropic", model: "claude-sonnet-4-5", input: 3_000_000, output: 15_000_000, cache: 300_000,
                version: 2, pricedAt: now.addingTimeInterval(-86_400 * 4)),
            PriceItem(
                provider: "anthropic", model: "claude-opus-4-1", input: 15_000_000, output: 75_000_000,
                cache: 1_500_000, version: 1, pricedAt: now.addingTimeInterval(-86_400 * 4)),
            PriceItem(
                provider: "openai", model: "gpt-5-codex", input: 1_250_000, output: 10_000_000, cache: 125_000,
                version: 1, pricedAt: now.addingTimeInterval(-86_400 * 9)),
            PriceItem(
                provider: "google", model: "gemini-2.5-pro", input: 1_250_000, output: 10_000_000, cache: 310_000,
                version: 3, pricedAt: now.addingTimeInterval(-86_400 * 2)),
        ]
        func prices() async throws -> [PriceItem] { priceList }
        func setPrice(_ p: PriceDraft) async throws {
            let v = (priceList.first { $0.provider == p.provider && $0.model == p.model }?.version ?? 0) + 1
            priceList.removeAll { $0.provider == p.provider && $0.model == p.model }
            priceList.append(
                PriceItem(
                    provider: p.provider, model: p.model, input: p.input, output: p.output, cache: p.cache, version: v,
                    pricedAt: p.pricedAt))
        }
        func runners() async throws -> [AccountRunner] {
            [
                AccountRunner(id: "r_linux01", name: "linux-01", online: true),
                AccountRunner(id: "r_mac", name: "studio-mac", online: true),
                AccountRunner(id: "r_old", name: "old-box", online: false),
            ]
        }
        func test(account: Int64) async throws -> TestedItem {
            try await Task.sleep(for: .seconds(1))
            let r = account == 4 ? "auth_failed" : "ok"
            accountList = accountList.map {
                guard $0.id == account else { return $0 }
                var n = $0
                n.lastTest = (Date(), r)
                return n
            }
            return TestedItem(result: r, latencyMs: 412)
        }
        func setSessionLimits(account: Int64, maxTokens: Int64?, maxUSDMicros: Int64?) async throws {
            accountList = accountList.map {
                guard $0.id == account else { return $0 }
                var n = $0
                n.maxTokens = maxTokens
                n.maxUSDMicros = maxUSDMicros
                return n
            }
        }
        func deleteAccount(_ id: Int64) async throws {
            accountList.removeAll { $0.id == id }
            poolList = poolList.map {
                PoolItem(
                    id: $0.id, name: $0.name, provider: $0.provider, isDefault: $0.isDefault,
                    members: $0.members.filter { $0 != id })
            }
        }
    }

    public static let scenes = [
        "overview", "overview-gate-off", "overview-gate-throwaway", "overview-empty", "accounts", "accounts-need",
        "account-ready", "account-at-limit", "connect-arrived", "accounts-not-admin",
        "account-cooling", "account-unhealthy", "account-disabled", "account-confirming", "account-testing",
        "provider-new", "provider-edit", "price-new", "budget-new", "budget-edit", "budget-raise", "budgets-empty",
        "limits", "pools", "pools-second", "chains", "chains-second", "chain-new", "chain-edit", "chain-delete",
        "chain-bind", "chain-error",
        "budgets", "costs", "ledger", "prices", "connect", "delete-account", "cap", "new-pool",
        "add-member",
        "delete-pool", "signin-intro", "signin-url", "signin-working", "signin-done", "signin-failed",
        "touchid-cancelled", "read-only", "state-loading", "state-error", "state-scope", "launcher",
        "settings-gate",
        "usage-limits", "usage-limits-empty", "usage-limit-new", "usage-limit-edit", "usage-limit-clear",
        "usage-limits-error", "usage-limits-no-admin", "usage-limits-read-only",
    ]

    let model: AccountsModel
    private let setNotice: @MainActor (AdminNotice?) -> Void
    public init(model: AccountsModel, setNotice: @escaping @MainActor (AdminNotice?) -> Void) {
        self.model = model
        self.setNotice = setNotice
    }

    /// For clicking through by hand: links really open in the browser (the snapshot runs never do).
    public func showInteractive(_ scene: String) async {
        await show(scene)
        model.opener = { NSWorkspace.shared.open($0) }
    }

    public func show(_ scene: String) async {
        if scene.hasPrefix("conn-") { return await showConnections(scene) }
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.linkNotice = nil
        shell.coreLink = .live
        setNotice(nil)
        let svc = Service()
        model.readOnly = false
        model.filter = .all
        model.poolSelection = nil
        model.chainSelection = scene == "chains-second" || scene == "chain-delete" ? 2 : nil
        model.opener = { _ in }
        model.signIn = nil
        switch scene {
        case "overview-gate-off": svc.gateState = GateState(mode: 0, providerAccounts: 0)
        case "overview-gate-throwaway": svc.gateState = GateState(mode: 1, providerAccounts: 0)
        case "overview-empty":
            svc.accountList = []
            svc.poolList = svc.poolList.map {
                PoolItem(id: $0.id, name: $0.name, provider: $0.provider, isDefault: $0.isDefault, members: [])
            }
        case "budgets-empty": svc.budgetList = []
        case "usage-limits-error":
            svc.usageError = CoreError.http(status: 500, code: "internal", message: "Core could not read usage.")
        case "usage-limits-no-admin": svc.usageError = CoreError.forbiddenScope
        case "accounts-not-admin":
            svc.accountList = svc.accountList.map {
                var x = $0
                x.live = nil
                x.health = nil
                return x
            }
        default: break
        }
        model.use(svc)
        try? await Task.sleep(for: .milliseconds(500))
        let page: AccountsPage =
            switch scene {
            case "accounts", "accounts-need", "accounts-not-admin", "account-ready", "account-cooling",
                "account-unhealthy", "account-at-limit", "connect-arrived",
                "account-disabled", "account-confirming", "account-testing", "limits", "connect", "delete-account",
                "cap", "usage-limits", "usage-limits-empty", "usage-limit-new", "usage-limit-edit",
                "usage-limit-clear", "usage-limits-error", "usage-limits-no-admin", "usage-limits-read-only",
                "signin-intro", "signin-url", "signin-working",
                "signin-done", "signin-failed":
                .accounts
            case "pools", "pools-second", "new-pool", "add-member", "delete-pool", "touchid-cancelled": .pools
            case "chains", "chains-second", "chain-new", "chain-edit", "chain-delete", "chain-bind", "chain-error":
                .chains
            case "budgets", "costs", "ledger", "prices": AccountsPage(rawValue: scene)!
            case "price-new": .prices
            case "provider-new", "provider-edit": .accounts
            case "budget-new", "budget-edit", "budget-raise", "budgets-empty": .budgets
            default: .overview
            }
        let detail: Int64? =
            switch scene {
            case "account-at-limit", "delete-account", "cap", "limits", "account-testing", "usage-limits",
                "usage-limit-new", "usage-limit-edit", "usage-limit-clear", "usage-limits-error",
                "usage-limits-no-admin", "usage-limits-read-only":
                1
            case "usage-limits-empty", "account-ready": 5
            case "account-confirming": 3
            case "account-cooling": 2
            case "account-unhealthy": 4
            case "account-disabled": 6
            default: nil
            }
        model.show(page, account: detail, pool: scene == "pools-second" || scene == "delete-pool" ? 2 : nil)
        try? await Task.sleep(for: .milliseconds(600))
        if scene == "accounts-need" { model.filter = .need }
        switch scene {
        case "connect": AccountDialogs.openConnect(model, provider: "anthropic")
        case "connect-arrived":
            AccountDialogs.openConnect(model, provider: "anthropic")
            try? await Task.sleep(for: .milliseconds(300))
            svc.accountList.append(
                AccountItem(
                    id: 7, provider: "anthropic", label: "claude-new", maskedTail: "k3Wf",
                    baseURL: "https://api.example.com", state: "active", stateReason: nil, stateUntil: nil, cap: 4,
                    lastUsedAt: nil, createdAt: Date()))
            await model.reload()
        case "signin-intro": AccountDialogs.openConnect(model, provider: "claude-sub")
        case "signin-url", "signin-working", "signin-done", "signin-failed":
            AccountDialogs.openConnect(model, provider: "claude-sub")
            model.signIn = SignInFlow(
                stage: scene == "signin-url"
                    ? .open(URL(string: "https://claude.ai/login")!)
                    : scene == "signin-working"
                        ? .working
                        : scene == "signin-done"
                            ? .done(account: 1)
                            : .failed(
                                "No runner can sign in yet. A runner needs the newest ainkrad-runner, with Claude's own app installed."
                            ), login: "lg_demo", runner: "linux-01", label: "claude-plan", opened: true)
        case "delete-account": AccountDialogs.openDelete(model, model.account(1)!)
        case "cap": AccountDialogs.openCap(model, model.account(1)!)
        case "limits": AccountDialogs.openLimits(model, model.account(1)!)
        case "usage-limit-new": AccountDialogs.openLimit(model, model.account(1)!, editing: nil)
        case "usage-limit-edit":
            await model.reloadLimits()
            AccountDialogs.openLimit(model, model.account(1)!, editing: model.limits(of: model.account(1)!)[1])
        case "usage-limit-clear":
            await model.reloadLimits()
            AccountDialogs.openClearLimit(model, model.account(1)!, model.limits(of: model.account(1)!)[0])
        case "usage-limits-read-only": model.readOnly = true
        case "budget-new": AccountDialogs.openBudget(model, editing: nil)
        case "price-new": AccountDialogs.openPrice(model, editing: nil)
        case "provider-new": AccountDialogs.openProvider(model, editing: nil)
        case "provider-edit": AccountDialogs.openProvider(model, editing: model.provider("openrouter"))
        case "budget-edit": AccountDialogs.openBudget(model, editing: model.budgets.first { $0.id == 3 })
        case "budget-raise": AccountDialogs.openRaise(model, model.budgets.first { $0.id == 2 }!)
        case "budgets": model.cursor = "g-3"
        case "account-testing": Task { await model.test(model.account(1)!) }
        case "chain-new": AccountDialogs.openChain(model, editing: nil)
        case "chain-edit": AccountDialogs.openChain(model, editing: model.chain(1))
        case "chain-delete": AccountDialogs.openDeleteChain(model, model.chain(2)!)
        case "chain-bind": AccountDialogs.openBindAgent(model, chain: model.chain(1)!)
        case "chain-error":
            AccountDialogs.openChain(model, editing: model.chain(1))
            model.note("chain", "The Core refused: a chain may hold only one subscription pool.", rule: true)
        case "new-pool": AccountDialogs.openNewPool(model)
        case "add-member": AccountDialogs.openAddMember(model, pool: model.pool(2)!)
        case "delete-pool": AccountDialogs.openDeletePool(model, model.pool(2)!)
        case "touchid-cancelled":
            AccountDialogs.openNewPool(model)
            setNotice(
                AdminNotice(
                    title: "Cancelled, nothing was changed.",
                    detail: "Your edit is still here. Try again when you are ready.", symbol: "hand.raised", warn: false
                ))
        case "read-only": model.readOnly = true
        case "state-loading": model.load = .loading
        case "state-error": model.load = .failed(code: "internal", message: "Core could not read its accounts.")
        case "state-scope": model.load = .forbidden
        case "launcher": shell.toggleLauncher()
        case "settings-gate":
            shell.settings.selected = "accounts-gate"
            shell.open(.settings)
        default: break
        }
    }
}
#endif
