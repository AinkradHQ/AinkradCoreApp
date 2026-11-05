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
    func bindings() async throws -> [BindingItem]
    /// `secrets.mode` and `secrets.provider_accounts`.
    func gate() async throws -> GateState
    func createPool(name: String, provider: String) async throws -> PoolItem
    func deletePool(_ id: Int64) async throws
    func setDefaultPool(_ id: Int64) async throws
    func addMember(pool: Int64, account: Int64) async throws
    func removeMember(pool: Int64, account: Int64) async throws
    func bind(agent: String, pool: Int64) async throws -> BindingItem
    func unbind(agent: String, provider: String) async throws
    func setState(account: Int64, state: String) async throws -> AccountItem
    func setCap(account: Int64, cap: Int64) async throws -> AccountItem
    func deleteAccount(_ id: Int64) async throws
    /// Subscription sign-in (KAN-441): start one on a runner, read where it is, hand it the approval code, stop it.
    func startLogin(provider: String, label: String, runner: String?) async throws -> LoginItem
    func login(_ id: String) async throws -> LoginItem
    func sendLoginCode(_ id: String, code: String) async throws -> LoginItem
    func cancelLogin(_ id: String) async throws
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
    func bindings() async throws -> [BindingItem] {
        try await run {
            try await client.listBindings().ok.body.json.map {
                BindingItem(agent: $0.agent, provider: $0.provider, poolID: $0.poolId)
            }
        }
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
    func bind(agent: String, pool: Int64) async throws -> BindingItem {
        try await run {
            let b = try await client.bindAgent(body: .json(.init(agent: agent, poolId: pool))).ok.body.json
            return BindingItem(agent: b.agent, provider: b.provider, poolID: b.poolId)
        }
    }
    func unbind(agent: String, provider: String) async throws {
        try await run { _ = try await client.unbindAgent(path: .init(agent: agent, provider: provider)).ok }
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

    // MARK: mapping

    static func login(_ l: Components.Schemas.AccountLogin) -> LoginItem {
        LoginItem(
            id: l.id, provider: l.provider, label: l.label, runner: l.runner, state: l.state, url: l.url,
            reason: l.reason, accountID: l.accountId)
    }

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreError.unwrapping(error) ?? Self.unknown }
    }

    static func provider(_ p: Components.Schemas.Provider) -> ProviderItem {
        ProviderItem(
            id: p.id, name: p.name, harness: p.harness, authVar: p.authVar, baseURL: p.baseUrl, delivery: p.delivery,
            loginMethods: p.loginMethods,
            models: p.models.map {
                ModelPriceItem(id: $0.id, inputMicro: $0.inputPerMtokMicro, outputMicro: $0.outputPerMtokMicro)
            }, pricedAt: p.pricedAt, builtin: p.builtin ?? false)
    }

    static func account(_ a: Components.Schemas.ProviderAccount) -> AccountItem {
        AccountItem(
            id: a.id, provider: a.provider, label: a.label, maskedTail: a.maskedTail, baseURL: a.baseUrl,
            state: a.state, stateReason: a.stateReason, stateUntil: a.stateUntil, cap: a.cap,
            lastUsedAt: a.lastUsedAt, createdAt: a.createdAt)
    }

    static func pool(_ p: Components.Schemas.Pool) -> PoolItem {
        PoolItem(id: p.id, name: p.name, provider: p.provider, isDefault: p.isDefault, members: p.members)
    }
}
