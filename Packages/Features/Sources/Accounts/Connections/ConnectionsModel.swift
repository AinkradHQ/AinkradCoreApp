import Admin
import AppKit
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI

/// Connections (CN1-CN7): the services Core signs in to for your agents. Its own pane beside Accounts, opened from the
/// launcher like Accounts. Reads come from the Core; every change goes through Touch ID like other admin writes.
@MainActor @Observable
public final class ConnectionsModel {
    let host: any AdminHost
    private(set) var service: (any ConnectionsService)?
    /// True while the screens run on stand-in data (Debug demo scenes only): a banner says so.
    private(set) var sample = false

    private(set) var kinds: [ConnKind] = []
    private(set) var items: [ConnItem] = []
    var load: AccountsLoad = .loading
    var filter: ConnFilter = .all
    /// The sign-in running in the Connect sheet.
    var flow: ConnFlow?
    /// The connection being signed in to again (its "Sign in again" button), instead of a new one.
    var again: Int64?
    /// GitHub's repository page is open; waiting for GitHub to say which were chosen.
    var installing = false
    /// The card the keyboard is on.
    var cursor: Int64?
    /// What the last Test of each connection said.
    var tested: [Int64: String] = [:]
    var testing: Int64?
    /// Set by the Debug scenes too (a Touch ID write can't run there), hence not private(set).
    var writeError: [String: String] = [:]
    var busy: String?
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// A macOS notification (id, title, body); the app routes it through the Agents notifier.
    @ObservationIgnored public var notify: ((String, String, String) -> Void)?
    @ObservationIgnored var pollEvery: Duration = .seconds(1)
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var catcher: LoopbackCatcher?

    public init(host: any AdminHost) { self.host = host }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        use(LiveConnectionsService(connection: connection))
    }

    func use(_ s: any ConnectionsService, sample: Bool = false) {
        service = s
        self.sample = sample
        Task { await reload() }
    }

    public func detach() {
        stopFlow()
        service = nil
        items = []
        load = .loading
    }

    public func event(kind: String) {
        guard kind.hasPrefix("connection.") else { return }
        Task {
            let before = Set(items.filter { $0.status == .needsLook }.map(\.id))
            await reload()
            // CN5: a sign-in that just started needing you is said once, in plain words.
            for c in items where c.status == .needsLook && !before.contains(c.id) {
                host.shell.showToast("\(c.name) needs you. \(c.reason ?? "") Open Connections to sign in again.")
                notify?(
                    "connection-\(c.id)", "\(c.name) needs you",
                    "\(c.reason ?? "This sign-in stopped working.") Open Ainkrad and press Sign in again.")
            }
        }
    }

    // MARK: derived

    func kind(_ id: String) -> ConnKind? { kinds.first { $0.id == id } }
    var liveKinds: [ConnKind] { kinds.filter(\.available) }
    var laterKinds: [ConnKind] { kinds.filter { !$0.available } }
    func items(of kind: String) -> [ConnItem] { items.filter { $0.kind == kind && filter.matches($0) } }
    func item(_ id: Int64) -> ConnItem? { items.first { $0.id == id } }
    /// The cards in the order they are drawn, for the arrows.
    var ordered: [ConnItem] { liveKinds.flatMap { items(of: $0.id) } }

    func move(_ step: Int) {
        let ids = ordered.map(\.id)
        guard !ids.isEmpty else { return }
        let i = cursor.flatMap { ids.firstIndex(of: $0) } ?? (step > 0 ? -1 : ids.count)
        cursor = ids[min(max(i + step, 0), ids.count - 1)]
    }

    /// A key on the card under the cursor: ↩ who can use it (or sign in again), T test, R rename, D default, ⌫ disconnect.
    func key(_ k: String) -> Bool {
        guard let c = cursor.flatMap(item) else { return false }
        switch k {
        case "↩":
            if c.status == .needsLook {
                ConnDialogs.openConnect(self, kind: c.kind, again: c.id)
            } else {
                ConnDialogs.openAccess(self, c)
            }
        case "t": Task { await test(c) }
        case "r": ConnDialogs.openRename(self, c)
        case "d": Task { await makeDefault(c) }
        case "⌫": ConnDialogs.openDisconnect(self, c)
        default: return false
        }
        return true
    }

    var needLook: Int { items.filter { $0.status == .needsLook }.count }
    var connected: Int { items.filter { $0.status == .connected }.count }

    /// What a connection may do and reach, as one sentence.
    func access(_ c: ConnItem) -> String {
        let k = kind(c.kind)
        let can = k?.capabilities.filter { c.allowed.contains($0.id) }.map { $0.title.lowercased() } ?? []
        let what = can.isEmpty ? "do nothing yet" : ListFormatter.localizedString(byJoining: can)
        let res = k?.resource ?? "places"
        let whereTo =
            c.only.map { $0.isEmpty ? "no \(res)" : $0.count == 1 ? $0[0] : "\($0.count) chosen \(res)" }
            ?? "all \(res)"
        return "Can \(what) in \(whereTo)."
    }

    // MARK: loading

    func reload() async {
        guard let service else { return }
        if items.isEmpty { load = .loading }
        do {
            async let k = service.kinds()
            async let i = service.connections()
            (kinds, items) = try await (k, i)
            // The defaults list is the truth for the "Default" badge; a member can't read it and keeps what the list said.
            if let d = try? await service.defaults() {
                items = items.map {
                    var c = $0
                    c.isDefault = d[c.kind] == c.id
                    return c
                }
            }
            load = .ready
        } catch {
            load = .failed(code: "error", message: ConnSay.plain(error))
        }
    }

    // MARK: sign-in (CN2, CN7)

    func startFlow(_ kind: String) async {
        guard let service else { return }
        stopFlow()
        if let why = host.pausedReason {
            host.shell.showToast(why)
            return
        }
        let name = self.kind(kind)?.name ?? kind
        do {
            let again = again
            let f = try await host.elevated("Sign in to \(name).", done: "changed", keepsEdit: false) {
                try await service.start(kind: kind, again: again)
            }
            flow = f
            if f.callbackState != nil || self.kind(kind)?.signIn == .browser { startCatcher(for: f) }
        } catch is AdminDeclined {
            failFlow(kind, "Nothing was started.", "Press Try again and confirm with Touch ID.")
        } catch {
            failFlow(kind, "Couldn't start the sign-in.", ConnSay.plain(error))
        }
    }

    private func failFlow(_ kind: String, _ title: String, _ fix: String) {
        flow = ConnFlow(
            id: "", kind: kind, userCode: nil, url: URL(string: "about:blank")!, step: .failed(title: title, fix: fix))
    }

    /// Opens the service's page and follows the sign-in until it needs the person again or ends.
    func openSignIn() {
        guard let f = flow else { return }
        opener(f.url)
        poll()
    }

    private func poll() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let f = self.flow, let service = self.service else { return }
                switch f.step {
                case .waiting: break
                case .chooseResources where self.installing: break
                default: return
                }
                try? await Task.sleep(for: self.pollEvery)
                guard let next = try? await service.flow(f.id), self.flow?.id == f.id else { continue }
                self.flow = next
                if next.step != f.step { await self.reload() }  // the connection exists now: the sheet shows it
            }
        }
    }

    /// GitHub's page for the Ainkrad app, where the person picks repositories; the sheet then waits for GitHub.
    func openInstall() {
        guard case .chooseResources(_, let install)? = flow?.step else { return }
        // GitHub sends the person back to this Mac with the installation's number; the connection is made from it.
        do {
            let c = try LoopbackCatcher(state: nil) { [weak self] number in
                Task { @MainActor in await self?.installed(number) }
            }
            c.start()
            catcher = c
        } catch {
            flow?.step = .failed(
                title: "This Mac couldn't wait for GitHub's answer.",
                fix: "Another app may be using the same address. Quit it or try again in a minute.")
            return
        }
        opener(install)
        installing = true
        poll()
    }

    private func installed(_ number: String) async {
        guard let f = flow, let service, let n = Int64(number) else { return }
        do {
            let why = "Let Core reach the repositories you chose."
            let c = try await host.elevated(why, done: "changed", keepsEdit: false) {
                try await service.install(kind: f.kind, installation: n)
            }
            await reload()
            if flow?.id == f.id { flow?.step = .connected(c.id) }
            catcher?.stop()
            catcher = nil
            installing = false
        } catch is AdminDeclined {
            installing = false
        } catch {
            flow?.step = .failed(title: "Couldn't use the repositories you chose.", fix: ConnSay.plain(error))
        }
    }

    /// GitHub: done choosing repositories on GitHub, or skipped. Jira: the site picked.
    func choose(site: String?) async {
        guard let f = flow, let service else { return }
        do {
            flow = try await service.choose(f.id, site: site)
            await reload()
        } catch {
            flow?.step = .failed(title: "Couldn't finish connecting.", fix: "Nothing was saved. Try again.")
        }
    }

    func stopFlow() {
        poller?.cancel()
        poller = nil
        catcher?.stop()
        catcher = nil
        installing = false
        again = nil
        if let f = flow, !f.id.isEmpty, let service, !f.isConnected { Task { try? await service.cancel(f.id) } }
        flow = nil
    }

    /// CN7: listen on this Mac's loopback address only while an Atlassian sign-in is open, then hand the code to Core.
    private func startCatcher(for f: ConnFlow) {
        do {
            // The redirect carries the Core's `state`, which is not the flow's id.
            let state = f.callbackState ?? f.id
            let c = try LoopbackCatcher(state: state) { [weak self] code in
                Task { @MainActor in
                    guard let self, let service = self.service, self.flow?.id == f.id else { return }
                    do {
                        self.flow = try await service.deliver(f.id, code: code, state: state)
                        await self.reload()
                    } catch {
                        self.flow?.step = .failed(title: "Couldn't finish the sign-in.", fix: ConnSay.plain(error))
                    }
                }
            }
            c.start()
            catcher = c
        } catch {
            flow?.step = .failed(
                title: "This Mac couldn't wait for Atlassian's answer.",
                fix: "Another app may be using the same address. Quit it or try again in a minute.")
        }
    }

    func addToken(kind: String, name: String, fields: [String: String], token: String) async -> Bool {
        await write("token", reason: "Connect \(name) with a token.", done: "\(name) is connected") {
            _ = try await $0.addToken(kind: kind, name: name, fields: fields, token: token)
        }
    }

    // MARK: actions on a connection (CN1, CN3)

    func test(_ c: ConnItem) async {
        guard let service else { return }
        testing = c.id
        defer { testing = nil }
        do { tested[c.id] = try await service.test(c.id) } catch { tested[c.id] = ConnSay.plain(error) }
    }

    func rename(_ c: ConnItem, to name: String) async -> Bool {
        await write("rename-\(c.id)", reason: "Rename \(c.name) to \(name).", done: "Renamed to \(name)") {
            try await $0.rename(c.id, to: name)
        }
    }

    func makeDefault(_ c: ConnItem) async {
        let k = kind(c.kind)?.name ?? c.kind
        await write("default-\(c.id)", reason: "Use \(c.name) first for \(k).", done: "\(c.name) is the \(k) default") {
            try await $0.setDefault(c.id)
        }
    }

    func clearDefault(_ c: ConnItem) async {
        let k = kind(c.kind)?.name ?? c.kind
        await write("cleardefault-\(c.id)", reason: "Stop using \(c.name) first for \(k).", done: "\(k) has no default")
        {
            try await $0.clearDefault(kind: c.kind)
        }
    }

    /// Replace the token behind a connection. The token goes in once and is not kept anywhere here.
    func replaceToken(_ c: ConnItem, token: String, fields: [String: String]) async -> Bool {
        await write("replace-\(c.id)", reason: "Replace the token for \(c.name).", done: "\(c.name) has a new token") {
            try await $0.replaceCredential(c.id, token: token, fields: fields)
        }
    }

    // MARK: app registration

    func loadApp(_ kind: String) async -> ConnAppLoad {
        guard let service else { return .failed("This Mac isn't connected to a Core.") }
        do { return .ready(try await service.app(kind: kind)) } catch CoreError.forbiddenScope {
            return .readOnly
        } catch {
            return .failed(ConnSay.plain(error))
        }
    }

    /// Only the changed fields are sent; secrets are never kept or shown again.
    func saveApp(_ kind: String, fields: [String: String]) async -> Bool {
        let name = self.kind(kind)?.name ?? kind
        return await write("app-\(kind)", reason: "Change the \(name) app registration.", done: "\(name) app saved") {
            _ = try await $0.setApp(kind: kind, fields: fields)
        }
    }

    func setAccess(_ c: ConnItem, allowed: Set<String>, only: [String]?) async -> Bool {
        await write("access-\(c.id)", reason: "Change what agents may do with \(c.name).", done: "Saved") {
            try await $0.setAccess(c.id, allowed: allowed, only: only)
        }
    }

    func disconnect(_ c: ConnItem) async -> Bool {
        await write(
            "delete-\(c.id)", reason: "Disconnect \(c.name). Agents lose access to it.",
            done: "\(c.name) is disconnected"
        ) {
            try await $0.delete(c.id)
        }
    }

    /// One write behind Touch ID, then everything read again. A refusal is kept in plain words under the control.
    @discardableResult
    private func write(
        _ key: String, reason: String, done: String,
        _ op: @escaping @Sendable (any ConnectionsService) async throws -> Void
    ) async -> Bool {
        guard let service else { return false }
        if let why = host.pausedReason {
            host.shell.showToast(why)
            return false
        }
        busy = key
        writeError[key] = nil
        defer { busy = nil }
        do {
            try await host.elevated(reason, done: "changed", keepsEdit: false) { try await op(service) }
            await reload()
            host.shell.showToast(done)
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            writeError[key] = ConnSay.plain(error)
            return false
        }
    }

    // MARK: pane and launcher

    /// "History" on a card: Settings, Audit, showing only this connection's rows.
    func openHistory(_ item: ConnItem) {
        host.shell.settings.open(
            "audit", handoff: ["audit.kind": "connection.", "audit.target": "connection:\(item.id)"])
        host.shell.open(.settings)
    }

    func show() {
        var spec = PaneSpec(
            id: "connections", title: "Connections", sub: "Home Core", symbol: "link",
            chip: PaneChip("Connected", tone: .run, symbol: "checkmark.circle"), minWidth: 720
        ) { ConnectionsView(model: self) }
        spec.tab = "Connections"
        host.shell.openPane(spec)
        Task { await reload() }
    }

    public func install() {
        let shell = host.shell
        shell.launcher.register(
            LauncherEntry(
                id: "connections", title: "Connections", sub: "GitHub, Jira and other services", symbol: "link",
                keywords: ["github", "jira", "sign in", "service"]
            ) { [weak self] in self?.show() })
        shell.launcher.register(
            LauncherEntry(
                id: "connections-connect", title: "Connect a service", sub: "Sign in to GitHub or Jira", symbol: "plus",
                keywords: ["github", "jira", "connect"], isAction: true
            ) { [weak self] in
                guard let self else { return }
                show()
                ConnDialogs.openConnect(self, kind: nil)
            })
    }
}
