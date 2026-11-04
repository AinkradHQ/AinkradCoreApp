#if DEBUG
import Admin
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
            ]
        }
        lazy var accountList: [AccountItem] = [
            a(1, "claude-api-metered", "anthropic", "active", "x9Lm", 4, used: 7_200),
            a(
                2, "claude-api-batch", "anthropic", "cooling", "k2Tq", 4, used: 1_100,
                reason: "Rate limit from the provider", until: 2_460),
            a(3, "codex-api", "openai", "active", "b2Rt", 0, used: 660),
            a(
                4, "codex-api-ci", "openai", "unhealthy", "r7Vd", 2, used: 86_400,
                reason: "The provider refused the key"),
            a(5, "gemini-key", "google", "active", "Qp0s", 4, used: 10_800),
            a(
                6, "gemini-spare", "google", "disabled", "d1Zn", 4, used: 777_600,
                reason: "Disabled while the key is replaced"),
        ]
        func a(
            _ id: Int64, _ label: String, _ provider: String, _ state: String, _ tail: String, _ cap: Int64,
            used: TimeInterval, reason: String? = nil, until: TimeInterval? = nil
        ) -> AccountItem {
            AccountItem(
                id: id, provider: provider, label: label, maskedTail: tail, baseURL: "https://api.example.com",
                state: state,
                stateReason: reason, stateUntil: until.map { now.addingTimeInterval($0) }, cap: cap,
                lastUsedAt: now.addingTimeInterval(-used), createdAt: now.addingTimeInterval(-9_000_000))
        }
        var poolList = [
            PoolItem(id: 1, name: "Default", provider: "anthropic", isDefault: true, members: [1, 2]),
            PoolItem(id: 2, name: "Client work", provider: "anthropic", isDefault: false, members: [1]),
            PoolItem(id: 3, name: "Default", provider: "openai", isDefault: true, members: [3, 4]),
            PoolItem(id: 4, name: "Default", provider: "google", isDefault: true, members: [5, 6]),
            PoolItem(id: 5, name: "Research", provider: "google", isDefault: false, members: []),
        ]
        var bindingList = [
            BindingItem(agent: "atlas", provider: "anthropic", poolID: 2),
            BindingItem(agent: "ines", provider: "anthropic", poolID: 2),
            BindingItem(agent: "vesper", provider: "openai", poolID: 3),
        ]
        var gateState = GateState(mode: 1, providerAccounts: 1)
        func providers() async throws -> [ProviderItem] { providerList }
        func accounts() async throws -> [AccountItem] { accountList }
        func pools() async throws -> [PoolItem] { poolList }
        func bindings() async throws -> [BindingItem] { bindingList }
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
        func bind(agent: String, pool: Int64) async throws -> BindingItem {
            let provider = poolList.first { $0.id == pool }?.provider ?? ""
            bindingList.removeAll { $0.agent == agent && $0.provider == provider }
            let b = BindingItem(agent: agent, provider: provider, poolID: pool)
            bindingList.append(b)
            return b
        }
        func unbind(agent: String, provider: String) async throws {
            bindingList.removeAll { $0.agent == agent && $0.provider == provider }
        }
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
                createdAt: old.createdAt)
            accountList = accountList.map { $0.id == id ? new : $0 }
            return new
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
        "account-ready",
        "account-cooling", "account-unhealthy", "account-disabled", "pools", "pools-second", "bindings",
        "bindings-empty",
        "budgets", "costs", "ledger", "prices", "activity", "connect", "delete-account", "cap", "new-pool", "bind",
        "add-member",
        "delete-pool", "touchid-cancelled", "read-only", "state-loading", "state-error", "state-scope", "launcher",
        "settings-gate",
    ]

    private let model: AccountsModel
    private let setNotice: @MainActor (AdminNotice?) -> Void
    public init(model: AccountsModel, setNotice: @escaping @MainActor (AdminNotice?) -> Void) {
        self.model = model
        self.setNotice = setNotice
    }

    public func show(_ scene: String) async {
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
        model.opener = { _ in }
        switch scene {
        case "overview-gate-off": svc.gateState = GateState(mode: 0, providerAccounts: 0)
        case "overview-gate-throwaway": svc.gateState = GateState(mode: 1, providerAccounts: 0)
        case "overview-empty":
            svc.accountList = []
            svc.poolList = svc.poolList.map {
                PoolItem(id: $0.id, name: $0.name, provider: $0.provider, isDefault: $0.isDefault, members: [])
            }
        case "bindings-empty": svc.bindingList = []
        default: break
        }
        model.use(svc)
        try? await Task.sleep(for: .milliseconds(500))
        let page: AccountsPage =
            switch scene {
            case "accounts", "accounts-need", "account-ready", "account-cooling", "account-unhealthy",
                "account-disabled", "connect", "delete-account", "cap":
                .accounts
            case "pools", "pools-second", "new-pool", "add-member", "delete-pool", "touchid-cancelled": .pools
            case "bindings", "bindings-empty", "bind": .bindings
            case "budgets", "costs", "ledger", "prices", "activity": AccountsPage(rawValue: scene)!
            default: .overview
            }
        let detail: Int64? =
            switch scene {
            case "account-ready", "delete-account", "cap": 1
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
        case "delete-account": AccountDialogs.openDelete(model, model.account(1)!)
        case "cap": AccountDialogs.openCap(model, model.account(1)!)
        case "new-pool": AccountDialogs.openNewPool(model)
        case "bind": AccountDialogs.openBind(model, pool: nil)
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
