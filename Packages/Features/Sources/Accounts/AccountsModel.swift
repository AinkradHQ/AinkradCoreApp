import Admin
import AppKit
import CoreKit
import Foundation
import Observation
import Shell
import SwiftUI

/// The Core app: provider accounts, pools and bindings. It owns the lists, the Core service and the writes (each behind
/// Touch ID through the host), registers the launcher entries and Settings sections, and turns a failure into words.
@MainActor @Observable
public final class AccountsModel {
    let host: any AdminHost
    private(set) var service: (any AccountsService)?

    private(set) var providers: [ProviderItem] = []
    private(set) var accounts: [AccountItem] = []
    private(set) var pools: [PoolItem] = []
    private(set) var bindings: [BindingItem] = []
    private(set) var gate = GateState()
    var load: AccountsLoad = .loading
    /// A write came back `forbidden_scope`: this device can read but not change.
    var readOnly = false
    var page: AccountsPage = .overview
    var filter: AccountFilter = .all
    /// The account whose page is open in Accounts (nil: the list).
    var detail: Int64?
    var poolSelection: Int64?
    /// A subscription sign-in in the Connect sheet, while it runs (`SignIn.swift`).
    var signIn: SignInFlow?
    /// The keyboard's cursor tile on the page: "a-<account>", "m-<account>" (a pool member) or "b-<binding>".
    var cursor: String?
    /// A refusal from the Core for the row or control being written, in words.
    private(set) var writeError: [String: String] = [:]
    private(set) var busy: String?
    /// Opens a provider's own page. Tests and the demo replace it: they must never open a browser.
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var now: () -> Date = { Date() }

    public init(host: any AdminHost) { self.host = host }

    // MARK: connection

    public func attach(connection: CoreConnection) { use(LiveAccountsService(connection: connection)) }

    func use(_ service: any AccountsService) {
        self.service = service
        Task { await reload() }
    }

    public func detach() {
        service = nil
        providers = []
        accounts = []
        pools = []
        bindings = []
        gate = GateState()
        load = .loading
        readOnly = false
        detail = nil
        signIn = nil
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }
    /// An event from the Core that may change what these screens show.
    public func event(kind: String) {
        if kind.hasPrefix("account.") || kind.hasPrefix("pool.") || kind.hasPrefix("setting.") { resync() }
    }

    // MARK: derived

    func provider(_ id: String) -> ProviderItem? { providers.first { $0.id == id } }
    func providerName(_ id: String) -> String { provider(id)?.name ?? id }
    func account(_ id: Int64) -> AccountItem? { accounts.first { $0.id == id } }
    func pool(_ id: Int64) -> PoolItem? { pools.first { $0.id == id } }
    var needLook: [AccountItem] { accounts.filter { $0.phase.needsLook } }
    var readyCount: Int { accounts.filter { $0.phase == .active }.count }
    var selectedPool: PoolItem? { pool(poolSelection ?? -1) ?? pools.first { $0.isDefault } ?? pools.first }
    func members(of pool: PoolItem) -> [AccountItem] { pool.members.compactMap { account($0) } }
    func bindings(of pool: PoolItem) -> [BindingItem] { bindings.filter { $0.poolID == pool.id } }
    func pools(of account: AccountItem) -> [PoolItem] { pools.filter { $0.members.contains(account.id) } }
    func pools(for provider: String) -> [PoolItem] { pools.filter { $0.provider == provider } }
    func defaultPool(_ provider: String) -> PoolItem? { pools.first { $0.provider == provider && $0.isDefault } }
    /// The member tried first: the first one in the fallback order that is ready.
    func firstReady(in pool: PoolItem) -> AccountItem? { members(of: pool).first { $0.phase == .active } }
    /// Accounts of the pool's provider that are not in it yet.
    func candidates(for pool: PoolItem) -> [AccountItem] {
        accounts.filter { $0.provider == pool.provider && !pool.members.contains($0.id) }
    }
    var providersByUse: [(ProviderItem, [AccountItem])] {
        providers.compactMap { p in
            let g = accounts.filter { $0.provider == p.id && filter.matches($0) }
            return g.isEmpty ? nil : (p, g)
        }
    }
    /// Providers with no account yet, and a name for providers the list does not know.
    var spareProviders: [ProviderItem] { providers.filter { p in !accounts.contains { $0.provider == p.id } } }

    // MARK: loading

    func reload() async {
        guard let service else { return }
        if accounts.isEmpty && pools.isEmpty { load = .loading }
        do {
            async let p = service.providers()
            async let a = service.accounts()
            async let o = service.pools()
            async let b = service.bindings()
            (providers, accounts, pools, bindings) = try await (p, a, o, b)
            load = .ready
            if let d = detail, account(d) == nil { detail = nil }
        } catch { load = state(for: error) }
        gate = (try? await service.gate()) ?? GateState()
        let chip: PaneChip =
            switch load {
            case .ready: PaneChip("Connected", tone: .run, symbol: "checkmark.circle")
            default: PaneChip("Not loaded", tone: .queue, symbol: "exclamationmark.circle")
            }
        host.shell.updatePane("accounts", chip: chip)
    }

    func state(for error: any Error) -> AccountsLoad {
        switch CoreError.unwrapping(error) {
        case .forbiddenScope: return .forbidden
        case .rateLimited(let after):
            host.rateLimited(retryAfter: after)
            return .failed(code: "rate_limited", message: "Too many requests. Nothing was changed.")
        case .some(let e): return .failed(code: Self.code(e), message: e.localizedDescription)
        case nil: return .failed(code: "unknown", message: error.localizedDescription)
        }
    }

    static func code(_ e: CoreError) -> String {
        switch e {
        case .forbiddenScope: "forbidden_scope"
        case .stepUpRequired: "step_up_required"
        case .rateLimited: "rate_limited"
        case .offline: "offline"
        case .sessionExpired: "session_expired"
        case .http(_, let c, _): c
        case .badRequest: "bad_request"
        default: "error"
        }
    }

    func code(_ error: any Error) -> String? { CoreError.unwrapping(error).map(Self.code) }

    /// One line for a refused write, with the Core's code.
    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        guard let e = CoreError.unwrapping(error) else { return error.localizedDescription }
        return "\(e.localizedDescription) (\(Self.code(e)))"
    }

    /// Writes are refused while the Core is unreachable or rate limiting: a toast says so.
    func mayWrite() -> Bool {
        guard let why = host.pausedReason else { return true }
        host.shell.showToast(why)
        return false
    }

    // MARK: writes

    /// Runs one write behind Touch ID, then reads everything again. True when the Core took it. A refusal is kept in
    /// `writeError[key]`; a person who did not elevate changes nothing and gets no error (the host shows its notice).
    @discardableResult
    func write(
        _ key: String, reason: String, done: String, keepsEdit: Bool = false,
        undo: (@MainActor () async -> Void)? = nil,
        _ op: @escaping @Sendable (any AccountsService) async throws -> Void
    ) async -> Bool {
        guard let service, mayWrite() else { return false }
        busy = key
        writeError[key] = nil
        defer { busy = nil }
        do {
            try await host.elevated(reason, done: "changed", keepsEdit: keepsEdit) { try await op(service) }
            await reload()
            if let undo {
                host.shell.showToast(done) { Task { @MainActor in await undo() } }
            } else {
                host.shell.showToast(done)
            }
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError[key] = words(error)
            return false
        }
    }

    func setEnabled(_ a: AccountItem, _ on: Bool) async {
        let key = "account-\(a.id)"
        await write(
            key,
            reason: on ? "Turn on \(a.label). Agents can use it again." : "Turn off \(a.label). New sessions skip it.",
            done: on ? "\(a.label) is on" : "\(a.label) is off. Running sessions keep going until they end.",
            undo: { [weak self] in await self?.setEnabled(a, !on) }
        ) { _ = try await $0.setState(account: a.id, state: on ? "active" : "disabled") }
    }

    func setCap(_ a: AccountItem, _ cap: Int64) async -> Bool {
        await write(
            "cap-\(a.id)", reason: "Change the session limit of \(a.label) to \(cap == 0 ? "none" : String(cap)).",
            done: "\(a.label): \(AccountsWords.capWords(cap).lowercased())", keepsEdit: true
        ) { _ = try await $0.setCap(account: a.id, cap: cap) }
    }

    func delete(_ a: AccountItem) async -> Bool {
        let ok = await write(
            "delete-\(a.id)", reason: "Delete \(a.label) and its key. This cannot be undone.",
            done: "\(a.label) deleted"
        ) { try await $0.deleteAccount(a.id) }
        if ok { detail = nil }
        return ok
    }

    func createPool(name: String, provider: String) async -> Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        let ok = await write(
            "new-pool", reason: "Create a \(providerName(provider)) pool named \(t).", done: "\(t) pool created",
            keepsEdit: true
        ) { _ = try await $0.createPool(name: t, provider: provider) }
        if ok, let made = pools.first(where: { $0.name == t && $0.provider == provider }) { poolSelection = made.id }
        return ok
    }

    func delete(_ p: PoolItem) async -> Bool {
        let ok = await write(
            "delete-pool-\(p.id)",
            reason: "Delete the pool \(p.name). Agents bound to it fall back to the default pool.",
            done: "\(p.name) deleted"
        ) { try await $0.deletePool(p.id) }
        if ok { poolSelection = nil }
        return ok
    }

    func makeDefault(_ p: PoolItem) async {
        let before = defaultPool(p.provider)
        var back: (@MainActor () async -> Void)?
        if let old = before { back = { [weak self] in await self?.makeDefault(old) } }
        await write(
            "default-\(p.id)", reason: "Make \(p.name) the default \(providerName(p.provider)) pool.",
            done: "\(p.name) is now the default",
            undo: back
        ) { try await $0.setDefaultPool(p.id) }
    }

    func add(_ a: AccountItem, to p: PoolItem) async -> Bool {
        await write(
            "member-\(p.id)", reason: "Add \(a.label) to \(p.name), last in its fallback order.",
            done: "\(a.label) added to \(p.name)", keepsEdit: true
        ) { try await $0.addMember(pool: p.id, account: a.id) }
    }

    func remove(_ a: AccountItem, from p: PoolItem) async {
        await write(
            "member-\(p.id)", reason: "Remove \(a.label) from \(p.name).", done: "\(a.label) removed from \(p.name)",
            undo: { [weak self] in _ = await self?.add(a, to: p) }
        ) { try await $0.removeMember(pool: p.id, account: a.id) }
    }

    /// The Core's rule for an agent id: 1 to 64 of `[A-Za-z0-9._:-]`.
    static func validAgent(_ s: String) -> Bool {
        guard (1...64).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || "._:-".unicodeScalars.contains($0)
        }
    }

    func bind(agent: String, to p: PoolItem) async -> Bool {
        let a = agent.trimmingCharacters(in: .whitespaces)
        let before = bindings.first { $0.agent == a && $0.provider == p.provider }
        return await write(
            "bind", reason: "Bind \(a) to \(p.name). It draws \(providerName(p.provider)) accounts from there.",
            done: "\(a) is bound to \(p.name)", keepsEdit: true,
            undo: { [weak self] in
                guard let self else { return }
                if let before, let old = self.pool(before.poolID) {
                    _ = await self.bind(agent: a, to: old)
                } else {
                    await self.unbind(BindingItem(agent: a, provider: p.provider, poolID: p.id), undoable: false)
                }
            }
        ) { _ = try await $0.bind(agent: a, pool: p.id) }
    }

    func unbind(_ b: BindingItem, undoable: Bool = true) async {
        let was = pool(b.poolID)
        var back: (@MainActor () async -> Void)?
        if undoable, let was { back = { [weak self] in _ = await self?.bind(agent: b.agent, to: was) } }
        await write(
            "unbind-\(b.id)",
            reason: "Unbind \(b.agent) from \(was?.name ?? "its pool"). It falls back to the default pool.",
            done: "\(b.agent) is unbound",
            undo: back
        ) { try await $0.unbind(agent: b.agent, provider: b.provider) }
    }

    // MARK: opening things

    func openProviderPage(_ provider: String) {
        if let site = ProviderSites.page(provider) { opener(site.url) }
    }

    func openSwitches() {
        host.shell.settings.selected = "switches"
        host.shell.open(.settings)
    }

    func openAudit() {
        host.shell.settings.selected = "audit"
        host.shell.open(.settings)
    }

    func show(_ page: AccountsPage, account id: Int64? = nil, pool: Int64? = nil) {
        self.page = page
        detail = page == .accounts ? id : nil
        if let pool { poolSelection = pool }
        let shell = host.shell
        shell.openPane(
            PaneSpec(
                id: "accounts", title: "Core", sub: "Accounts", symbol: "creditcard",
                chip: PaneChip("Connected", tone: .run, symbol: "checkmark.circle"), minWidth: 720
            ) { AccountsView(model: self) })
        Task { await reload() }
    }

    // MARK: launcher and Settings

    /// Launcher entries and the two Settings sections. Ids match the shell's own sample entries, so Demo mode keeps its own.
    public func install() {
        let shell = host.shell
        func entry(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String], action: Bool = false,
            _ run: @escaping @MainActor (AccountsModel) -> Void
        ) {
            shell.launcher.register(
                LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys, isAction: action) {
                    [weak self] in if let self { run(self) }
                })
        }
        entry(
            "core", "Core", "Accounts, pools and bindings", "creditcard",
            ["provider", "claude", "codex", "gemini", "budget"]
        ) {
            $0.show(.overview)
        }
        entry("accounts", "Accounts", "Provider accounts by provider", "creditcard", ["api key", "provider", "limits"])
        {
            $0.show(.accounts)
        }
        entry(
            "accounts-connect", "Connect an account", "Open the provider's own page", "plus", ["key", "login"],
            action: true
        ) {
            $0.show(.accounts)
            AccountDialogs.openConnect($0, provider: nil)
        }
        entry(
            "accounts-pools", "Account pools", "Which accounts serve which agents", "square.grid.2x2",
            ["pool", "default", "fallback"]
        ) {
            $0.show(.pools)
        }
        entry(
            "accounts-bindings", "Agent bindings", "Which pool each agent draws from", "link",
            ["bind", "agent", "pool"]
        ) {
            $0.show(.bindings)
        }
        shell.settings.section(
            SettingsSection(
                id: "accounts-link", group: .apps, title: "Accounts", symbol: "creditcard", order: 4
            ) {
                AccountsLinkSection(model: self)
            })
        shell.settings.section(
            SettingsSection(id: "accounts-gate", group: .security, title: "Real accounts", symbol: "lock", order: 3) {
                AccountsGateSection(model: self)
            })
    }
}
