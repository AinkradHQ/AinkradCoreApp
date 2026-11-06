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
    var bindingList: [BindingItem] = []
    var gateState = GateState(mode: 1, providerAccounts: 0)
    var failure: (any Error)?
    private var calls: [String] = []
    var log: [String] { lock.withLock { calls } }
    private func note(_ s: String) throws {
        lock.withLock { calls.append(s) }
        if let failure { throw failure }
    }
    func providers() async throws -> [ProviderItem] { providerList }
    func accounts() async throws -> [AccountItem] { accountList }
    func pools() async throws -> [PoolItem] { poolList }
    func bindings() async throws -> [BindingItem] { bindingList }
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
    func bind(agent: String, pool p: Int64) async throws -> BindingItem {
        try note("bind \(agent) \(p)")
        let provider = poolList.first { $0.id == p }?.provider ?? "?"
        let b = BindingItem(agent: agent, provider: provider, poolID: p)
        bindingList.removeAll { $0.agent == agent && $0.provider == provider }
        bindingList.append(b)
        return b
    }
    func unbind(agent: String, provider: String) async throws {
        try note("unbind \(agent) \(provider)")
        bindingList.removeAll { $0.agent == agent && $0.provider == provider }
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
    var tested = TestedItem(result: "ok", latencyMs: 300)
    func runners() async throws -> [AccountRunner] { [] }
    func saveProvider(_ p: ProviderDraft, replacing: Bool) async throws {
        try note("saveProvider \(p.id) \(p.harness) \(p.authVar) \(p.keyPrefix) \(replacing)")
    }
    func deleteProvider(_ id: String) async throws { try note("deleteProvider \(id)") }
    var usageList: [UsageItem] = []
    var costList: [CostItem] = []
    func usage() async throws -> [UsageItem] { usageList }
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
