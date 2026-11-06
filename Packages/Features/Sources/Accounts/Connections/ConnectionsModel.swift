import Admin
import AppKit
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
    /// True while the screens run on stand-in data (Debug, until the Core serves connections): a banner says so.
    private(set) var sample = false

    private(set) var kinds: [ConnKind] = []
    private(set) var items: [ConnItem] = []
    private(set) var activity: [ConnActivity] = []
    var load: AccountsLoad = .loading
    var page: ConnPage = .list
    var filter: ConnFilter = .all
    var activityFilter: Int64?
    /// The sign-in running in the Connect sheet.
    var flow: ConnFlow?
    /// What the last Test of each connection said.
    var tested: [Int64: String] = [:]
    var testing: Int64?
    private(set) var writeError: [String: String] = [:]
    private(set) var busy: String?
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var pollEvery: Duration = .seconds(1)
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var catcher: LoopbackCatcher?

    public init(host: any AdminHost) { self.host = host }

    // MARK: connection

    /// The Core does not serve connections yet (C5). Debug builds show stand-in data, labelled; Release shows that.
    public func attach() {
        #if DEBUG
        use(SampleConnections(), sample: true)
        #endif
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
        activity = []
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
            }
        }
    }

    // MARK: derived

    func kind(_ id: String) -> ConnKind? { kinds.first { $0.id == id } }
    var liveKinds: [ConnKind] { kinds.filter(\.available) }
    var laterKinds: [ConnKind] { kinds.filter { !$0.available } }
    func items(of kind: String) -> [ConnItem] { items.filter { $0.kind == kind && filter.matches($0) } }
    func item(_ id: Int64) -> ConnItem? { items.first { $0.id == id } }
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
            async let a = service.activity(connection: nil)
            (kinds, items, activity) = try await (k, i, a)
            load = .ready
        } catch {
            load = .failed(code: "error", message: "The Core couldn't list connections. Nothing was changed.")
        }
    }

    // MARK: sign-in (CN2, CN7)

    func startFlow(_ kind: String) async {
        guard let service else { return }
        stopFlow()
        do {
            let f = try await service.start(kind: kind)
            flow = f
            if self.kind(kind)?.signIn == .browser { startCatcher(for: f) }
        } catch {
            flow = ConnFlow(
                id: "", kind: kind, userCode: nil, url: URL(string: "about:blank")!,
                step: .failed(
                    title: "Couldn't start the sign-in.",
                    fix: "Check that this Mac can reach your Core, then try again."))
        }
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
                guard case .waiting = f.step else { return }
                try? await Task.sleep(for: self.pollEvery)
                guard let next = try? await service.flow(f.id), self.flow?.id == f.id else { continue }
                self.flow = next
            }
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
        if let f = flow, !f.id.isEmpty, let service, !f.isConnected { Task { try? await service.cancel(f.id) } }
        flow = nil
    }

    /// CN7: listen on this Mac's loopback address only while an Atlassian sign-in is open, then hand the code to Core.
    private func startCatcher(for f: ConnFlow) {
        do {
            let c = try LoopbackCatcher(state: f.id) { [weak self] code in
                Task { @MainActor in
                    guard let self, let service = self.service, self.flow?.id == f.id else { return }
                    if let next = try? await service.deliver(f.id, code: code, state: f.id) { self.flow = next }
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
        tested[c.id] = (try? await service.test(c.id)) ?? "Couldn't reach your Core to test it."
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
            writeError[key] = "Your Core didn't take that. Nothing was changed; try again."
            return false
        }
    }

    // MARK: pane and launcher

    func show(_ page: ConnPage = .list) {
        self.page = page
        host.shell.openPane(
            PaneSpec(
                id: "connections", title: "Core", sub: "Connections", symbol: "link",
                chip: PaneChip("Connected", tone: .run, symbol: "checkmark.circle"), minWidth: 720
            ) { ConnectionsView(model: self) })
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
