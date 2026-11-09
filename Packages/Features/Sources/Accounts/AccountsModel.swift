import Admin
import AppKit
import CoreKit
import Foundation
import Observation
import Shell
import SwiftUI

/// The Core app: provider accounts, pools and fallback chains. It owns the lists, the Core service and the writes (each behind
/// Touch ID through the host), registers the launcher entries and Settings sections, and turns a failure into words.
@MainActor @Observable
public final class AccountsModel {
    let host: any AdminHost
    private(set) var service: (any AccountsService)?

    private(set) var providers: [ProviderItem] = []
    private(set) var accounts: [AccountItem] = []
    private(set) var pools: [PoolItem] = []
    private(set) var chains: [ChainItem] = []
    private(set) var chainBindings: [ChainBindingItem] = []
    /// False when the Core refused to list chains: they are for admins, so a device without that scope sees none of them.
    private(set) var chainsAllowed = true
    var chainSelection: Int64?
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
    /// The account whose key is being tested now, and what the last test of each answered when it could not run.
    var testing: Int64?
    var testNote: [Int64: String] = [:]
    /// Budgets (Spend), read when the Spend pages open.
    var budgets: [BudgetItem] = []
    var spendLoad: AccountsLoad = .loading
    /// Costs and usage, the ledger and prices (Spend), read when their pages open.
    var usage: [UsageItem] = []
    var costs: [CostItem] = []
    var prices: [PriceItem] = []
    var costsLoad: AccountsLoad = .loading
    /// The usage limits on an account page, read when it opens.
    var limitsLoad: AccountsLoad = .loading
    var pricesLoad: AccountsLoad = .loading
    /// Opens a provider's own page. Tests and the demo replace it: they must never open a browser.
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var now: () -> Date = { Date() }

    /// Connections (GitHub, Jira…): its own pane, driven alongside the accounts.
    public let connections: ConnectionsModel

    public init(host: any AdminHost) {
        self.host = host
        connections = ConnectionsModel(host: host)
    }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        use(LiveAccountsService(connection: connection))
        connections.attach(connection: connection)
    }

    func use(_ service: any AccountsService) {
        self.service = service
        usage = []
        limitsLoad = .loading
        Task { await reload() }
    }

    public func detach() {
        connections.detach()
        service = nil
        providers = []
        accounts = []
        pools = []
        chains = []
        chainBindings = []
        chainsAllowed = true
        gate = GateState()
        load = .loading
        readOnly = false
        detail = nil
        signIn = nil
        usage = []
        limitsLoad = .loading
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }
    /// An event from the Core that may change what these screens show.
    public func event(kind: String) {
        connections.event(kind: kind)
        // A sign-in's own events move it on at once; the one-second poll stays as the fallback.
        if kind.hasPrefix("account.login."), let id = signIn?.login, !signInEnded { Task { await refreshSignIn(id) } }
        let kinds = ["account.", "pool.", "chain.", "setting."]
        if kinds.contains(where: kind.hasPrefix) { resync() }
    }

    // MARK: derived

    /// "Claude account Work": how an event names an account. Nil until the account is known.
    public func accountName(_ id: Int64) -> String? {
        account(id).map { "\(providerName($0.provider)) account \($0.label)" }
    }
    public func poolName(_ id: Int64) -> String? { pool(id)?.name }
    func provider(_ id: String) -> ProviderItem? { providers.first { $0.id == id } }
    func providerName(_ id: String) -> String { provider(id)?.name ?? id }
    func account(_ id: Int64) -> AccountItem? { accounts.first { $0.id == id } }
    func pool(_ id: Int64) -> PoolItem? { pools.first { $0.id == id } }
    var needLook: [AccountItem] { needLookAccounts }
    var readyCount: Int { readyAccounts }
    var selectedPool: PoolItem? { pool(poolSelection ?? -1) ?? pools.first { $0.isDefault } ?? pools.first }
    func members(of pool: PoolItem) -> [AccountItem] { pool.members.compactMap { account($0) } }
    func chain(_ id: Int64) -> ChainItem? { chains.first { $0.id == id } }
    var selectedChain: ChainItem? { chain(chainSelection ?? -1) ?? chains.first { $0.isDefault } ?? chains.first }
    func chains(using pool: PoolItem) -> [ChainItem] { chains.filter { $0.entries.contains { $0.pool == pool.id } } }
    func agents(of chain: ChainItem) -> [ChainBindingItem] { chainBindings.filter { $0.chain == chain.id } }
    func pools(of account: AccountItem) -> [PoolItem] { pools.filter { $0.members.contains(account.id) } }
    func pools(for provider: String) -> [PoolItem] { pools.filter { $0.provider == provider } }
    func defaultPool(_ provider: String) -> PoolItem? { pools.first { $0.provider == provider && $0.isDefault } }
    /// The member tried first: the first one in the fallback order that is ready.
    func firstReady(in pool: PoolItem) -> AccountItem? { members(of: pool).first { verdict($0).isReady } }
    /// Accounts of the pool's provider that are not in it yet.
    func candidates(for pool: PoolItem) -> [AccountItem] {
        accounts.filter { $0.provider == pool.provider && !pool.members.contains($0.id) }
    }
    var providersByUse: [(ProviderItem, [AccountItem])] {
        providers.compactMap { p in
            let g = accounts.filter { $0.provider == p.id && filter.matches($0, verdict: verdict($0)) }
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
            (providers, accounts, pools) = try await (p, a, o)
            load = .ready
            await reloadChains(service)
            if let d = detail, account(d) == nil { detail = nil }
        } catch { load = state(for: error) }
        // The verdict on every card needs the limits and budgets too; a device without `admin` just gets none.
        await reloadLimits()
        await reloadBudgets()
        gate = (try? await service.gate()) ?? GateState()
        let chip: PaneChip =
            switch load {
            case .ready: PaneChip("Connected", tone: .run, symbol: "checkmark.circle")
            default: PaneChip("Not loaded", tone: .queue, symbol: "exclamationmark.circle")
            }
        host.shell.updatePane("accounts", chip: chip)
    }

    /// Chains and their agents are admin only: a refusal hides them, it is not an error of the page.
    private func reloadChains(_ service: any AccountsService) async {
        do {
            async let c = service.chains()
            async let b = service.chainBindings()
            (chains, chainBindings) = try await (c, b)
            chainsAllowed = true
        } catch {
            chains = []
            chainBindings = []
            chainsAllowed = CoreError.unwrapping(error) != .forbiddenScope
        }
        if page == .chains && !chainsAllowed { page = .pools }
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

    /// Say why a sheet opened, in the sheet's own error line (nil clears it).
    func note(_ key: String, _ text: String?) { writeError[key] = text }

    /// The next free `pool-N` (the Core wants lowercase, so not "Pool 3").
    func nextPoolName() -> String {
        var n = pools.count + 1
        while pools.contains(where: { $0.name == "pool-\(n)" }) { n += 1 }
        return "pool-\(n)"
    }

    /// New pool, the quick way: the first provider (what the sheet preselects), a generated name, no members, then selected.
    /// With no provider, or when the Core refuses, the sheet opens and says why.
    func quickPool() async {
        guard let provider = providers.first?.id else {
            return AccountDialogs.openNewPool(self, reason: "No provider yet. Connect an account first.")
        }
        if await createPool(name: nextPoolName(), provider: provider) { return }
        // A declined Touch ID changes nothing and opens nothing; a refusal opens the sheet with the Core's words.
        if let why = writeError["new-pool"] { AccountDialogs.openNewPool(self, reason: why) }
    }

    func delete(_ p: PoolItem) async -> Bool {
        let ok = await write(
            "delete-pool-\(p.id)",
            reason: "Delete the pool \(p.name).",
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

    // MARK: chains

    /// The next free `chain-N`.
    func nextChainName() -> String {
        var n = chains.count + 1
        while chains.contains(where: { $0.name == "chain-\(n)" }) { n += 1 }
        return "chain-\(n)"
    }

    /// New chain, the quick way: a generated name and the first pool of each provider, up to the default pool, then
    /// selected. With no pool, or when the Core refuses, the sheet opens and says why.
    func quickChain() async {
        guard let first = pools.first(where: { $0.isDefault }) ?? pools.first else {
            return AccountDialogs.openChain(
                self, editing: nil, reason: "No pool yet. Make a pool with an account first.")
        }
        if await createChain(name: nextChainName(), entries: [ChainEntryDraft(pool: first.id, model: nil)]) { return }
        if let why = writeError["chain"] { AccountDialogs.openChain(self, editing: nil, reason: why) }
    }

    func createChain(name: String, entries: [ChainEntryDraft]) async -> Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        let ok = await write(
            "chain", reason: "Create the chain \(t) with \(entries.count) pool\(entries.count == 1 ? "" : "s").",
            done: "\(t) chain created", keepsEdit: true
        ) { _ = try await $0.createChain(name: t, entries: entries) }
        if ok, let made = chains.first(where: { $0.name == t }) { chainSelection = made.id }
        return ok
    }

    func replace(_ c: ChainItem, name: String, entries: [ChainEntryDraft]) async -> Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        let was = c.entries.map { ChainEntryDraft(pool: $0.pool, model: $0.model) }
        return await write(
            "chain", reason: "Change the chain \(c.name). Running sessions keep the chain they started with.",
            done: "\(t) saved", keepsEdit: true,
            undo: { [weak self] in
                guard let self, let now = self.chain(c.id) else { return }
                _ = await self.replace(now, name: c.name, entries: was)
            }
        ) { _ = try await $0.replaceChain(c.id, name: t, entries: entries) }
    }

    func delete(_ c: ChainItem) async -> Bool {
        let ok = await write(
            "delete-chain-\(c.id)",
            reason: "Delete the chain \(c.name). Agents bound to it fall back to the default chain.",
            done: "\(c.name) deleted"
        ) { try await $0.deleteChain(c.id) }
        if ok { chainSelection = nil }
        return ok
    }

    func makeDefault(_ c: ChainItem) async {
        let before = chains.first { $0.isDefault }
        var back: (@MainActor () async -> Void)?
        if let old = before { back = { [weak self] in await self?.makeDefault(old) } }
        await write(
            "chain-default-\(c.id)", reason: "Make \(c.name) the default chain.",
            done: "\(c.name) is now the default", undo: back
        ) { try await $0.setDefaultChain(c.id) }
    }

    /// Agents the app knows: every one bound to a chain, then the ones bound from here before. The Core has no agent list.
    var knownAgents: [String] {
        let bound = chainBindings.map(\.agent)
        let recent = UserDefaults.standard.stringArray(forKey: "accounts.recentAgents") ?? []
        return Array(NSOrderedSet(array: bound + recent)) as? [String] ?? bound
    }
    func boundChain(of agent: String) -> ChainItem? {
        chainBindings.first { $0.agent == agent }.flatMap { chain($0.chain) }
    }

    func bind(agent: String, to c: ChainItem) async -> Bool {
        let a = agent.trimmingCharacters(in: .whitespaces)
        let before = chainBindings.first { $0.agent == a }.flatMap { chain($0.chain) }
        let ok = await write(
            "bind-chain", reason: "Bind \(a) to \(c.name). Its sessions draw accounts from that chain.",
            done: "\(a) is bound to \(c.name)", keepsEdit: true,
            undo: { [weak self] in
                guard let self else { return }
                if let before {
                    _ = await self.bind(agent: a, to: before)
                } else {
                    await self.unbind(a, undoable: false)
                }
            }
        ) { _ = try await $0.bindAgent(a, chain: c.id) }
        if ok {
            let d = UserDefaults.standard
            d.set(
                Array(([a] + (d.stringArray(forKey: "accounts.recentAgents") ?? [])).prefix(12)),
                forKey: "accounts.recentAgents")
        }
        return ok
    }

    func unbind(_ agent: String, undoable: Bool = true) async {
        let was = chainBindings.first { $0.agent == agent }.flatMap { chain($0.chain) }
        var back: (@MainActor () async -> Void)?
        if undoable, let was { back = { [weak self] in _ = await self?.bind(agent: agent, to: was) } }
        await write(
            "unbind-\(agent)",
            reason: "Unbind \(agent) from \(was?.name ?? "its chain"). It falls back to the default chain.",
            done: "\(agent) is unbound", undo: back
        ) { try await $0.unbindAgent(agent) }
    }

    // MARK: opening things

    func openProviderPage(_ provider: String) {
        if let site = ProviderSites.page(provider) { opener(site.url) }
    }

    /// The Runners pane (Terminals registers it in the launcher).
    func openRunners() { host.shell.launcher.entry("runners")?.run() }

    func openSwitches() {
        host.shell.settings.selected = "switches"
        host.shell.open(.settings)
    }

    /// Chains are defined here; agents are bound where work starts: Settings, Agents and chains (Agents registers the page).
    func openChainBinding() {
        host.shell.settings.selected = "agent-chains"
        host.shell.open(.settings)
    }

    func openAudit() {
        host.shell.settings.selected = "audit"
        host.shell.open(.settings)
    }

    /// "Raise budget…" from an ended session: the Raise dialog for that account's spent budget when it is known, else the
    /// Budgets page.
    public func raiseBudget(forAccount account: Int64?) {
        let spent = budgets.filter(\.exhausted)
        let mine = account.flatMap { id in spent.first { $0.kind == "account" && $0.subject == String(id) } }
        show(.budgets)
        if let b = mine ?? (spent.count == 1 ? spent.first : nil) { AccountDialogs.openRaise(self, b) }
    }

    func show(_ page: AccountsPage, account id: Int64? = nil, pool: Int64? = nil) {
        self.page = page
        detail = page == .accounts ? id : nil
        if let pool { poolSelection = pool }
        let shell = host.shell
        var spec = PaneSpec(
            id: "accounts", title: "Accounts", sub: "Home Core", symbol: "creditcard",
            chip: PaneChip("Connected", tone: .run, symbol: "checkmark.circle"), minWidth: 720
        ) { AccountsView(model: self) }
        spec.tab = "Accounts"
        shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher and Settings

    /// Launcher entries and the two Settings sections. Ids match the shell's own sample entries, so Demo mode keeps its own.
    public func install() {
        connections.install()
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
            "core", "Accounts overview", "Accounts, pools and chains", "creditcard",
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
            "new-pool", "New pool", "Makes an empty pool at once · needs Touch ID", "plus", ["create", "pool"],
            action: true
        ) { m in Task { await m.quickPool() } }
        entry(
            "new-pool-advanced", "New pool (advanced)…", "Name it and choose the provider", "slider.horizontal.3",
            ["create", "pool", "provider"], action: true
        ) { AccountDialogs.openNewPool($0) }
        entry(
            "new-chain", "New chain", "Makes a chain from your default pool at once · needs Touch ID", "plus",
            ["create", "chain", "fallback"], action: true
        ) { m in Task { await m.quickChain() } }
        entry(
            "new-chain-advanced", "New chain (advanced)…", "Name it and choose its pools and models",
            "slider.horizontal.3", ["create", "chain", "fallback", "pool"], action: true
        ) { AccountDialogs.openChain($0, editing: nil) }
        entry(
            "accounts-chains", "Fallback chains", "Which pools a session tries, in order", "link",
            ["chain", "default", "fallback", "failover"]
        ) {
            $0.show(.chains)
        }
        entry(
            "accounts-pools", "Account pools", "Which accounts serve which agents", "square.grid.2x2",
            ["pool", "default", "fallback"]
        ) {
            $0.show(.pools)
        }
        shell.settings.section(
            SettingsSection(
                id: "accounts-link", group: .apps, title: "Accounts", symbol: "creditcard", order: 4
            ) {
                AccountsLinkSection(model: self)
            })
    }
}
