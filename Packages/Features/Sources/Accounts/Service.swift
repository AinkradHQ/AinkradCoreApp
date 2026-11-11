import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// The Core as the Accounts screens use it. `LiveAccountsService` is the only real one; tests and the demo bring their own.
/// A key only ever goes in on the Core's side: nothing here takes or returns one.
protocol AccountsService: Sendable {
    func providers() async throws -> [ProviderItem]
    func accounts() async throws -> [AccountItem]
    func pools() async throws -> [PoolItem]
    /// `secrets.mode` and `secrets.provider_accounts`.
    func gate() async throws -> GateState
    func createPool(name: String, provider: String) async throws -> PoolItem
    func deletePool(_ id: Int64) async throws
    func setDefaultPool(_ id: Int64) async throws
    func addMember(pool: Int64, account: Int64) async throws
    func removeMember(pool: Int64, account: Int64) async throws
    /// Fallback chains (`admin`; writes need Touch ID): a name and 1 to 4 entries, each a pool and a model.
    func chains() async throws -> [ChainItem]
    func createChain(name: String, entries: [ChainEntryDraft]) async throws -> ChainItem
    func replaceChain(_ id: Int64, name: String, entries: [ChainEntryDraft]) async throws -> ChainItem
    func deleteChain(_ id: Int64) async throws
    func setDefaultChain(_ id: Int64) async throws
    func chainBindings() async throws -> [ChainBindingItem]
    func bindAgent(_ agent: String, chain: Int64) async throws -> ChainBindingItem
    func unbindAgent(_ agent: String) async throws
    func setState(account: Int64, state: String) async throws -> AccountItem
    func setCap(account: Int64, cap: Int64) async throws -> AccountItem
    func deleteAccount(_ id: Int64) async throws
    /// Adds an account with its key (`admin`, step-up). The key goes to the Core and is never read back.
    func createAccount(provider: String, label: String, key: String, runners: [String]) async throws -> AccountItem
    /// The same with where it goes (pool, chain, seat) and its monthly limit. A pool or chain that is new must exist first.
    func createAccount(
        provider: String, label: String, key: String, runners: [String], placement: ResolvedPlacement
    ) async throws -> AccountItem
    /// Replaces an account's key; `runners` nil keeps the ones it has (`admin`, step-up).
    func replaceSecret(account: Int64, key: String, runners: [String]?) async throws
    /// Sets one of the two `secrets.*` switches (`admin`, step-up).
    func setSecretsSwitch(_ key: String, _ value: Int64) async throws
    /// Subscription sign-in (KAN-441): start one on a runner, read where it is, hand it the approval code, stop it.
    func startLogin(provider: String, label: String, runner: String?) async throws -> LoginItem
    func login(_ id: String) async throws -> LoginItem
    func sendLoginCode(_ id: String, code: String) async throws -> LoginItem
    func cancelLogin(_ id: String) async throws
    /// Runners a sign-in may be pinned to (the advanced choice).
    func runners() async throws -> [AccountRunner]
    /// One free request with the key through a runner: the status class and the latency, never a body.
    func test(account: Int64) async throws -> TestedItem
    /// What one session may spend on the account; nil clears that limit.
    func setSessionLimits(account: Int64, maxTokens: Int64?, maxUSDMicros: Int64?) async throws
    /// Budgets with where each stands in its period now (`read`); changing one needs `admin` and Touch ID.
    func budgets() async throws -> [BudgetItem]
    func setBudget(_ b: BudgetDraft) async throws
    func deleteBudget(_ id: Int64) async throws
    func raiseBudget(_ id: Int64, periodKey: String, tokens: Int64?, usdMicros: Int64?) async throws
    /// Each account's use over 5 hours and 7 days, with where each of its usage limits stands (`admin`).
    func usage() async throws -> [UsageItem]
    /// Add a usage limit or change the one with the same unit and window (`admin`, Touch ID).
    func setLimit(account: Int64, _ d: LimitDraft) async throws
    func clearLimit(account: Int64, unit: String, windowSecs: Int64) async throws
    /// Cost events, newest first, at most 100 (`admin`).
    func costs(account: Int64?) async throws -> [CostItem]
    func prices() async throws -> [PriceItem]
    /// The next version of a model's price, from now on (`admin`, Touch ID).
    func setPrice(_ p: PriceDraft) async throws
    /// A provider definition of your own (`admin`, Touch ID); replacing makes a new version, deleting refuses one in use.
    func saveProvider(_ p: ProviderDraft, replacing: Bool) async throws
    func deleteProvider(_ id: String) async throws
}

/// A placement with real ids: the Core takes ids, never "the default" (nil lets the Core use its own default).
struct ResolvedPlacement: Equatable, Sendable {
    var pool: Int64?
    var chain: Int64?
    var position: Int?
    var monthlyLimitMicros: Int64?
}

extension AccountsService {
    /// Fakes that do not care where an account goes.
    func createAccount(
        provider: String, label: String, key: String, runners: [String], placement: ResolvedPlacement
    ) async throws -> AccountItem {
        try await createAccount(provider: provider, label: label, key: key, runners: runners)
    }
}

struct AccountRunner: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let online: Bool
    /// What the runner advertised: the command ops of every driver (`gateway`, `login`, `subscription-env`…) and the
    /// driver names (`agent`, `pty`…). Empty until it first connects.
    var commands: Set<String> = []
    var drivers: Set<String> = []
}

struct TestedItem: Equatable, Sendable {
    let result: String
    let latencyMs: Int64
}

/// The Core's transport already turns every non-2xx answer into a `CoreError`, so only `.ok` is read here.
struct LiveAccountsService: AccountsService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func providers() async throws -> [ProviderItem] {
        try await run { try await client.listProviders().ok.body.json.map(Self.provider) }
    }
    func accounts() async throws -> [AccountItem] {
        try await run { try await client.listAccounts().ok.body.json.map(Self.account) }
    }
    func pools() async throws -> [PoolItem] {
        try await run { try await client.listPools().ok.body.json.map(Self.pool) }
    }
    func gate() async throws -> GateState {
        try await run {
            let all = try await client.listServerSettings().ok.body.json
            func value(_ k: String) -> Int64? { all.first { $0.key == k }?.value }
            return GateState(mode: value("secrets.mode"), providerAccounts: value("secrets.provider_accounts"))
        }
    }
    func createPool(name: String, provider: String) async throws -> PoolItem {
        try await run {
            Self.pool(try await client.createPool(body: .json(.init(name: name, provider: provider))).ok.body.json)
        }
    }
    func deletePool(_ id: Int64) async throws {
        try await run { _ = try await client.deletePool(path: .init(id: String(id))).ok }
    }
    func setDefaultPool(_ id: Int64) async throws {
        try await run { _ = try await client.setDefaultPool(path: .init(id: String(id))).ok }
    }
    func addMember(pool: Int64, account: Int64) async throws {
        try await run { _ = try await client.addPoolMember(path: .init(id: String(pool), account: String(account))).ok }
    }
    func removeMember(pool: Int64, account: Int64) async throws {
        try await run {
            _ = try await client.removePoolMember(path: .init(id: String(pool), account: String(account))).ok
        }
    }
    func chains() async throws -> [ChainItem] {
        try await run { try await client.listChains().ok.body.json.map(Self.chain) }
    }
    func createChain(name: String, entries: [ChainEntryDraft]) async throws -> ChainItem {
        try await run {
            Self.chain(try await client.createChain(body: .json(Self.newChain(name, entries))).ok.body.json)
        }
    }
    func replaceChain(_ id: Int64, name: String, entries: [ChainEntryDraft]) async throws -> ChainItem {
        try await run {
            Self.chain(
                try await client.replaceChain(path: .init(id: String(id)), body: .json(Self.newChain(name, entries)))
                    .ok.body.json)
        }
    }
    func deleteChain(_ id: Int64) async throws {
        try await run { _ = try await client.deleteChain(path: .init(id: String(id))).ok }
    }
    func setDefaultChain(_ id: Int64) async throws {
        try await run { _ = try await client.setDefaultChain(path: .init(id: String(id))).ok }
    }
    func chainBindings() async throws -> [ChainBindingItem] {
        try await run {
            try await client.listChainBindings().ok.body.json.map { ChainBindingItem(agent: $0.agent, chain: $0.chain) }
        }
    }
    func bindAgent(_ agent: String, chain: Int64) async throws -> ChainBindingItem {
        try await run {
            let b = try await client.bindAgentChain(path: .init(agent: agent), body: .json(.init(chain: chain))).ok.body
                .json
            return ChainBindingItem(agent: b.agent, chain: b.chain)
        }
    }
    func unbindAgent(_ agent: String) async throws {
        try await run { _ = try await client.unbindAgentChain(path: .init(agent: agent)).ok }
    }
    func setState(account: Int64, state: String) async throws -> AccountItem {
        try await run {
            Self.account(
                try await client.setAccountState(path: .init(id: String(account)), body: .json(.init(state: state))).ok
                    .body.json)
        }
    }
    func setCap(account: Int64, cap: Int64) async throws -> AccountItem {
        try await run {
            Self.account(
                try await client.setAccountCap(path: .init(id: String(account)), body: .json(.init(cap: cap))).ok.body
                    .json)
        }
    }
    func deleteAccount(_ id: Int64) async throws {
        try await run { _ = try await client.deleteAccount(path: .init(id: String(id))).ok }
    }
    func createAccount(provider: String, label: String, key: String, runners: [String]) async throws -> AccountItem {
        try await createAccount(
            provider: provider, label: label, key: key, runners: runners,
            placement: ResolvedPlacement(pool: nil, chain: nil, position: nil, monthlyLimitMicros: nil))
    }
    func createAccount(
        provider: String, label: String, key: String, runners: [String], placement p: ResolvedPlacement
    ) async throws -> AccountItem {
        try await run {
            Self.account(
                try await client.createAccount(
                    body: .json(
                        .init(
                            chain: p.chain, label: label, monthlyLimitUsdMicros: p.monthlyLimitMicros, pool: p.pool,
                            position: p.position.map(Int32.init), provider: provider, runners: runners, value: key))
                ).ok.body.json.account)
        }
    }
    func replaceSecret(account: Int64, key: String, runners: [String]?) async throws {
        try await run {
            _ = try await client.replaceAccountSecret(
                path: .init(id: String(account)), body: .json(.init(runners: runners, value: key))
            ).ok
        }
    }
    func setSecretsSwitch(_ key: String, _ value: Int64) async throws {
        try await run {
            _ = try await client.setSetting(path: .init(scope: "server", key: key), body: .json(.init(value: value))).ok
        }
    }

    func startLogin(provider: String, label: String, runner: String?) async throws -> LoginItem {
        try await run {
            Self.login(
                try await client.startAccountLogin(
                    body: .json(.init(label: label, provider: provider, runner: runner))
                ).ok.body.json)
        }
    }
    func login(_ id: String) async throws -> LoginItem {
        try await run { Self.login(try await client.getAccountLogin(path: .init(id: id)).ok.body.json) }
    }
    func sendLoginCode(_ id: String, code: String) async throws -> LoginItem {
        try await run {
            Self.login(
                try await client.sendAccountLoginCode(path: .init(id: id), body: .json(.init(code: code))).ok.body.json)
        }
    }
    func cancelLogin(_ id: String) async throws {
        try await run { _ = try await client.cancelAccountLogin(path: .init(id: id)).ok }
    }

    func runners() async throws -> [AccountRunner] {
        try await run {
            try await client.listRunners().ok.body.json.map {
                let ds = $0.drivers ?? []
                return AccountRunner(
                    id: $0.id, name: $0.name, online: $0.online ?? false,
                    commands: Set(ds.flatMap { $0.commands ?? [] }), drivers: Set(ds.compactMap(\.name)))
            }
        }
    }
    func test(account: Int64) async throws -> TestedItem {
        try await run {
            let t = try await client.testAccount(path: .init(id: String(account))).ok.body.json
            return TestedItem(result: t.result, latencyMs: t.latencyMs)
        }
    }
    func setSessionLimits(account: Int64, maxTokens: Int64?, maxUSDMicros: Int64?) async throws {
        try await run {
            _ = try await client.setAccountSessionLimits(
                path: .init(id: String(account)), body: .json(.init(maxTokens: maxTokens, maxUsdMicros: maxUSDMicros))
            ).ok
        }
    }

    func budgets() async throws -> [BudgetItem] {
        try await run { try await client.listBudgets().ok.body.json.map(Self.budget) }
    }
    func setBudget(_ b: BudgetDraft) async throws {
        try await run {
            _ = try await client.setBudget(
                body: .json(
                    .init(
                        hardStop: b.hardStop, kind: b.kind, period: b.period, subject: b.subject, tokenCap: b.tokenCap,
                        usdCapMicros: b.usdCap, warnAtPercent: b.warnAt))
            ).ok
        }
    }
    func deleteBudget(_ id: Int64) async throws {
        try await run { _ = try await client.deleteBudget(path: .init(id: String(id))).ok }
    }
    func raiseBudget(_ id: Int64, periodKey: String, tokens: Int64?, usdMicros: Int64?) async throws {
        try await run {
            _ = try await client.raiseBudget(
                path: .init(id: String(id)),
                body: .json(.init(periodKey: periodKey, tokens: tokens, usdMicros: usdMicros))
            ).ok
        }
    }

    func saveProvider(_ p: ProviderDraft, replacing: Bool) async throws {
        let body = Components.Schemas.Provider(
            authVar: p.authVar, baseUrl: p.baseURL, delivery: ["gateway"], harness: p.harness, id: p.id,
            keyPrefix: p.keyPrefix, loginMethods: ["paste"],
            models: p.models.map { .init(id: $0.id, inputPerMtokMicro: $0.input, outputPerMtokMicro: $0.output) },
            name: p.name, pricedAt: p.models.isEmpty ? nil : ISO8601DateFormatter().string(from: Date()),
            testPath: p.testPath, usageParser: p.usageParser)
        try await run {
            if replacing {
                _ = try await client.replaceProvider(path: .init(id: p.id), body: .json(body)).ok
            } else {
                _ = try await client.createProvider(body: .json(body)).ok
            }
        }
    }
    func deleteProvider(_ id: String) async throws {
        try await run { _ = try await client.deleteProvider(path: .init(id: id)).ok }
    }

    func usage() async throws -> [UsageItem] {
        try await run { try await client.accountsUsage().ok.body.json.map(Self.usage) }
    }
    func setLimit(account: Int64, _ d: LimitDraft) async throws {
        try await run {
            _ = try await client.setAccountLimit(
                path: .init(id: String(account)),
                body: .json(.init(cap: d.cap, unit: d.unit, warnPercent: d.warnPercent, windowSecs: d.windowSecs))
            ).ok
        }
    }
    func clearLimit(account: Int64, unit: String, windowSecs: Int64) async throws {
        try await run {
            _ = try await client.clearAccountLimit(
                path: .init(id: String(account), unit: unit, windowSecs: windowSecs)
            ).ok
        }
    }
    func costs(account: Int64?) async throws -> [CostItem] {
        try await run {
            try await client.listCosts(query: .init(account: account, limit: 100)).ok.body.json.map {
                CostItem(
                    id: $0.id, at: $0.occurredAt, accountID: $0.accountId, provider: $0.provider, model: $0.model,
                    session: $0.session, input: $0.inputTokens, output: $0.outputTokens, cache: $0.cacheTokens,
                    costMicros: $0.costUsdMicros, basis: $0.basis, approximate: $0.approximate)
            }
        }
    }
    func prices() async throws -> [PriceItem] {
        try await run {
            try await client.listPrices().ok.body.json.map {
                PriceItem(
                    provider: $0.provider, model: $0.model, input: $0.inputPerMtokMicro, output: $0.outputPerMtokMicro,
                    cache: $0.cachePerMtokMicro, version: $0.version, pricedAt: $0.pricedAt)
            }
        }
    }
    func setPrice(_ p: PriceDraft) async throws {
        try await run {
            _ = try await client.setPrice(
                body: .json(
                    .init(
                        cachePerMtokMicro: p.cache, inputPerMtokMicro: p.input, model: p.model,
                        outputPerMtokMicro: p.output, pricedAt: ISO8601DateFormatter().string(from: p.pricedAt),
                        provider: p.provider))
            ).ok
        }
    }

    static func usage(_ u: Components.Schemas.AccountSpend) -> UsageItem {
        func w(_ x: Components.Schemas.UsageWindow) -> UsageWindowItem {
            UsageWindowItem(tokens: x.totalTokens, messages: x.messages, costMicros: x.costUsdMicros)
        }
        return UsageItem(
            accountID: u.accountId, fiveHours: w(u.fiveHours), sevenDays: w(u.sevenDays),
            limitShare: Double(u.maxUtilisationBps) / 10_000, limitsExhausted: u.limits.contains { $0.exhausted },
            hasLimits: !u.limits.isEmpty, drops: u.recentDrops,
            companies: u.byCompany.map {
                CompanyUsage(company: $0.company, fiveHours: w($0.fiveHours), sevenDays: w($0.sevenDays))
            },
            limits: u.limits.map {
                LimitItem(
                    unit: $0.unit, windowSecs: $0.windowSecs, cap: $0.cap, used: $0.used, warnPercent: $0.warnPercent,
                    exhausted: $0.exhausted)
            })
    }

    static func budget(_ b: Components.Schemas.SubjectBudget) -> BudgetItem {
        BudgetItem(
            id: b.id, kind: b.kind, subject: b.subject, company: b.company, period: b.period, periodKey: b.periodKey,
            tokenCap: b.tokenCap, usdCap: b.usdCapMicros, spent: b.spent, usdSpent: b.usdSpent, held: b.held,
            raised: b.raised, raisedUSD: b.raisedUsd, warnAt: b.warnAtPercent, hardStop: b.hardStop,
            exhausted: b.exhausted)
    }

    // MARK: mapping

    static func login(_ l: Components.Schemas.AccountLogin) -> LoginItem {
        LoginItem(
            id: l.id, provider: l.provider, label: l.label, runner: l.runner, state: l.state, url: l.url,
            reason: l.reason, accountID: l.accountId)
    }

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? Self.unknown }
    }

    static func provider(_ p: Components.Schemas.Provider) -> ProviderItem {
        ProviderItem(
            id: p.id, name: p.name, harness: p.harness, authVar: p.authVar, baseURL: p.baseUrl, delivery: p.delivery,
            loginMethods: p.loginMethods,
            models: p.models.map {
                ModelPriceItem(id: $0.id, inputMicro: $0.inputPerMtokMicro, outputMicro: $0.outputPerMtokMicro)
            }, pricedAt: p.pricedAt, builtin: p.builtin ?? false, keyPrefix: p.keyPrefix, testPath: p.testPath,
            version: p.version ?? 1)
    }

    static func account(_ a: Components.Schemas.ProviderAccount) -> AccountItem {
        AccountItem(
            id: a.id, provider: a.provider, label: a.label, maskedTail: a.maskedTail, baseURL: a.baseUrl,
            state: a.state, stateReason: a.stateReason, stateUntil: a.stateUntil, cap: a.cap,
            lastUsedAt: a.lastUsedAt, createdAt: a.createdAt, lastTest: a.lastTest.map { ($0.at, $0.result) },
            maxTokens: a.sessionLimits?.maxTokens, maxUSDMicros: a.sessionLimits?.maxUsdMicros, live: a.live,
            health: a.health.map {
                AccountHealthItem(
                    failStreak: $0.failStreak, authStreak: $0.authStreak, lastSuccessAt: $0.lastSuccessAt,
                    upstreamClass: $0.upstreamClass, planStatus: $0.planLimit?.status,
                    windows: ($0.planLimit?.windows ?? []).map {
                        PlanWindowItem(name: $0.name, utilization: $0.utilization, resetsAt: $0.resetsAt)
                    })
            })
    }

    static func chain(_ c: Components.Schemas.Chain) -> ChainItem {
        ChainItem(
            id: c.id, name: c.name, isDefault: c.isDefault,
            entries: c.entries.map {
                ChainEntryItem(pool: $0.pool, provider: $0.provider, harness: $0.harness, model: $0.model)
            })
    }

    static func newChain(_ name: String, _ entries: [ChainEntryDraft]) -> Components.Schemas.NewChain {
        .init(entries: entries.map { .init(model: $0.model, pool: $0.pool) }, name: name)
    }

    static func pool(_ p: Components.Schemas.Pool) -> PoolItem {
        PoolItem(id: p.id, name: p.name, provider: p.provider, isDefault: p.isDefault, members: p.members)
    }
}
