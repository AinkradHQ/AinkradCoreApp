import CoreKit
import Foundation
import Shell

@testable import Accounts
@testable import Admin

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    private(set) var reasons: [String] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw AdminDeclined() }
        return try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

func account(_ id: Int64, _ label: String, provider: String = "anthropic", state: String = "active", cap: Int64 = 4)
    -> AccountItem
{
    AccountItem(
        id: id, provider: provider, label: label, maskedTail: "x9Lm", baseURL: "https://api.example.com", state: state,
        stateReason: nil, stateUntil: nil, cap: cap, lastUsedAt: nil, createdAt: Date(timeIntervalSince1970: 1_000))
}

func pool(_ id: Int64, _ name: String, provider: String = "anthropic", def: Bool = false, members: [Int64] = [])
    -> PoolItem
{
    PoolItem(id: id, name: name, provider: provider, isDefault: def, members: members)
}

final class FakeService: AccountsService, @unchecked Sendable {
    private let lock = NSLock()
    var providerList = [
        ProviderItem(
            id: "anthropic", name: "Anthropic API", harness: "claude", authVar: "ANTHROPIC_API_KEY",
            baseURL: "https://api.anthropic.com", delivery: ["env"], loginMethods: ["paste"], models: [], pricedAt: nil,
            builtin: true)
    ]
    var accountList: [AccountItem] = []
    var poolList: [PoolItem] = []
    var chainList: [ChainItem] = []
    var chainBindingList: [ChainBindingItem] = []
    var gateState = GateState(mode: 1, providerAccounts: 0)
    var failure: (any Error)?
    /// What listing chains throws (a device without `admin`), apart from `failure`.
    var chainsFailure: (any Error)?
    private var calls: [String] = []
    var log: [String] { lock.withLock { calls } }
    private func note(_ s: String) throws {
        lock.withLock { calls.append(s) }
        if let failure { throw failure }
    }
    func providers() async throws -> [ProviderItem] { providerList }
    func accounts() async throws -> [AccountItem] { accountList }
    func pools() async throws -> [PoolItem] { poolList }
    func gate() async throws -> GateState { gateState }
    func createPool(name: String, provider: String) async throws -> PoolItem {
        try note("createPool \(name) \(provider)")
        let p = pool(Int64(poolList.count + 10), name, provider: provider)
        poolList.append(p)
        return p
    }
    func deletePool(_ id: Int64) async throws {
        try note("deletePool \(id)")
        poolList.removeAll { $0.id == id }
    }
    func setDefaultPool(_ id: Int64) async throws {
        try note("default \(id)")
        poolList = poolList.map { pool($0.id, $0.name, provider: $0.provider, def: $0.id == id, members: $0.members) }
    }
    func addMember(pool p: Int64, account a: Int64) async throws {
        try note("add \(p) \(a)")
        poolList = poolList.map {
            $0.id == p ? pool($0.id, $0.name, provider: $0.provider, def: $0.isDefault, members: $0.members + [a]) : $0
        }
    }
    func removeMember(pool p: Int64, account a: Int64) async throws {
        try note("remove \(p) \(a)")
        poolList = poolList.map {
            $0.id == p
                ? pool($0.id, $0.name, provider: $0.provider, def: $0.isDefault, members: $0.members.filter { $0 != a })
                : $0
        }
    }
    func chains() async throws -> [ChainItem] {
        if let chainsFailure { throw chainsFailure }
        return chainList
    }
    private func entries(_ drafts: [ChainEntryDraft]) -> [ChainEntryItem] {
        drafts.map { d in
            ChainEntryItem(
                pool: d.pool, provider: poolList.first { $0.id == d.pool }?.provider ?? "?", harness: "claude",
                model: d.model)
        }
    }
    func createChain(name: String, entries drafts: [ChainEntryDraft]) async throws -> ChainItem {
        try note("createChain \(name) \(drafts.map { "\($0.pool):\($0.model ?? "-")" }.joined(separator: ","))")
        let c = ChainItem(
            id: Int64(chainList.count + 10), name: name, isDefault: chainList.isEmpty, entries: entries(drafts))
        chainList.append(c)
        return c
    }
    func replaceChain(_ id: Int64, name: String, entries drafts: [ChainEntryDraft]) async throws -> ChainItem {
        try note("replaceChain \(id) \(name) \(drafts.count)")
        let c = ChainItem(
            id: id, name: name, isDefault: chainList.first { $0.id == id }?.isDefault ?? false,
            entries: entries(drafts))
        chainList = chainList.map { $0.id == id ? c : $0 }
        return c
    }
    func deleteChain(_ id: Int64) async throws {
        try note("deleteChain \(id)")
        chainList.removeAll { $0.id == id }
        chainBindingList.removeAll { $0.chain == id }
    }
    func setDefaultChain(_ id: Int64) async throws {
        try note("defaultChain \(id)")
        chainList = chainList.map { ChainItem(id: $0.id, name: $0.name, isDefault: $0.id == id, entries: $0.entries) }
    }
    func chainBindings() async throws -> [ChainBindingItem] {
        if let chainsFailure { throw chainsFailure }
        return chainBindingList
    }
    func bindAgent(_ agent: String, chain: Int64) async throws -> ChainBindingItem {
        try note("bindAgent \(agent) \(chain)")
        let b = ChainBindingItem(agent: agent, chain: chain)
        chainBindingList.removeAll { $0.agent == agent }
        chainBindingList.append(b)
        return b
    }
    func unbindAgent(_ agent: String) async throws {
        try note("unbindAgent \(agent)")
        chainBindingList.removeAll { $0.agent == agent }
    }
    func setState(account id: Int64, state: String) async throws -> AccountItem {
        try note("state \(id) \(state)")
        accountList = accountList.map {
            $0.id == id ? account($0.id, $0.label, provider: $0.provider, state: state, cap: $0.cap) : $0
        }
        return accountList.first { $0.id == id }!
    }
    func setCap(account id: Int64, cap: Int64) async throws -> AccountItem {
        try note("cap \(id) \(cap)")
        accountList = accountList.map {
            $0.id == id ? account($0.id, $0.label, provider: $0.provider, state: $0.state, cap: cap) : $0
        }
        return accountList.first { $0.id == id }!
    }
    var loginItem = LoginItem(
        id: "lg_1", provider: "claude-sub", label: "claude-plan", runner: "r_1", state: "open_url",
        url: "https://claude.ai/oauth/authorize?test", reason: nil, accountID: nil)
    func startLogin(provider: String, label: String, runner: String?) async throws -> LoginItem {
        try note("startLogin \(provider) \(label)")
        return loginItem
    }
    func login(_ id: String) async throws -> LoginItem { loginItem }
    func sendLoginCode(_ id: String, code: String) async throws -> LoginItem {
        try note("sendLoginCode \(id)")
        return loginItem
    }
    func cancelLogin(_ id: String) async throws { try note("cancelLogin \(id)") }
    var runnerList = [AccountRunner(id: "r_1", name: "linux-01", online: true)]
    var lastKey = ""
    func createAccount(provider: String, label: String, key: String, runners: [String]) async throws -> AccountItem {
        try note("createAccount \(provider) \(label) \(runners.joined(separator: ","))")
        lastKey = key
        let a = account(Int64(accountList.count + 50), label, provider: provider)
        accountList.append(a)
        return a
    }
    func replaceSecret(account id: Int64, key: String, runners: [String]?) async throws {
        try note("replaceSecret \(id) \(runners == nil ? "keep" : "set")")
        lastKey = key
    }
    func setSecretsSwitch(_ key: String, _ value: Int64) async throws { try note("switch \(key) \(value)") }
    var tested = TestedItem(result: "ok", latencyMs: 300)
    func runners() async throws -> [AccountRunner] { runnerList }
    func saveProvider(_ p: ProviderDraft, replacing: Bool) async throws {
        try note("saveProvider \(p.id) \(p.harness) \(p.authVar) \(p.keyPrefix) \(replacing)")
    }
    func deleteProvider(_ id: String) async throws { try note("deleteProvider \(id)") }
    var usageList: [UsageItem] = []
    var costList: [CostItem] = []
    var usageFailure: (any Error)?
    func usage() async throws -> [UsageItem] {
        if let usageFailure { throw usageFailure }
        return usageList
    }
    func setLimit(account id: Int64, _ d: LimitDraft) async throws {
        try note("setLimit \(id) \(d.unit) \(d.windowSecs) \(d.cap) \(d.warnPercent)")
    }
    func clearLimit(account id: Int64, unit: String, windowSecs: Int64) async throws {
        try note("clearLimit \(id) \(unit) \(windowSecs)")
    }
    func costs(account: Int64?) async throws -> [CostItem] { costList }
    func prices() async throws -> [PriceItem] { [] }
    func setPrice(_ p: PriceDraft) async throws {
        try note("setPrice \(p.provider) \(p.model) \(p.input) \(p.output) \(p.cache)")
    }
    var budgetList: [BudgetItem] = []
    func budgets() async throws -> [BudgetItem] { budgetList }
    func setBudget(_ b: BudgetDraft) async throws {
        try note("setBudget \(b.kind) \(b.subject) \(b.period) \(b.tokenCap)")
    }
    func deleteBudget(_ id: Int64) async throws { try note("deleteBudget \(id)") }
    func raiseBudget(_ id: Int64, periodKey: String, tokens: Int64?, usdMicros: Int64?) async throws {
        try note("raiseBudget \(id) \(periodKey) \(tokens ?? 0) \(usdMicros ?? 0)")
    }
    func test(account: Int64) async throws -> TestedItem {
        try note("test \(account)")
        return tested
    }
    func setSessionLimits(account: Int64, maxTokens: Int64?, maxUSDMicros: Int64?) async throws {
        try note(
            "setSessionLimits \(account) \(maxTokens.map(String.init) ?? "nil") \(maxUSDMicros.map(String.init) ?? "nil")"
        )
    }
    func deleteAccount(_ id: Int64) async throws {
        try note("deleteAccount \(id)")
        accountList.removeAll { $0.id == id }
        poolList = poolList.map {
            pool($0.id, $0.name, provider: $0.provider, def: $0.isDefault, members: $0.members.filter { $0 != id })
        }
    }
}
