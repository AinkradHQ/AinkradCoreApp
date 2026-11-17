import Admin
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI

/// The Leyline app: the hosts gallery, the Keys page and the host space the gallery opens. It owns the lists, the Core service
/// and the writes (the ones that need it behind Touch ID, through the host), and registers the pane and the launcher entries.
@MainActor @Observable
public final class LeylineModel {
    let host: any AdminHost
    var service: (any LeylineService)?

    var hosts: [HostItem] = []
    var keys: [KeyItem] = []
    var knownHosts: [KnownHostItem] = []
    var load: LeylineLoad = .notConnected
    /// The page of the top bar (the gallery, or Keys).
    var page = LeylinePage.hosts
    /// The gallery's Filter field.
    var filter = ""
    /// The host whose space is open (nil: the gallery or Keys).
    var openID: String?
    var section = HostSection.overview
    /// The gallery cards ticked for a fleet run.
    var selection: Set<String> = []
    /// The gallery card the arrow keys are on.
    var cursor: String?
    /// ⌘N and Add Host: the quick pop-over under the button.
    var quickOpen = false
    var quickText = ""
    /// A refusal from the Core (or the sheet's own check) for the write in flight, in words.
    private(set) var writeError: String?
    private(set) var busy = false
    /// A write came back `forbidden_scope`: this device can read but not change.
    private(set) var readOnly = false
    /// The Core's name, for "Reached through" (the Core this Mac is paired with).
    var coreName: String { host.shell.home.coreName.isEmpty ? "Home Core" : host.shell.home.coreName }
    #if DEBUG
    /// Snapshots only: draws this card in its hover state.
    var debugHover: String?
    #endif

    public init(host: any AdminHost) { self.host = host }

    // MARK: connection

    public func attach(connection: CoreConnection) { use(LiveLeylineService(connection: connection)) }

    func use(_ service: any LeylineService) {
        self.service = service
        load = .loading
        Task { await reload() }
    }

    public func detach() {
        service = nil
        hosts = []
        keys = []
        knownHosts = []
        load = .notConnected
        openID = nil
        cursor = nil
        selection = []
        quickOpen = false
        readOnly = false
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }

    /// An event from the Core that may change what the screens show.
    public func event(kind: String) { if kind.hasPrefix("leyline.") { resync() } }

    func reload() async {
        guard let service else { return }
        do {
            async let h = service.hosts()
            async let k = service.keys()
            async let n = service.knownHosts()
            hosts = try await h
            keys = try await k
            knownHosts = try await n
            selection = selection.intersection(hosts.map(\.id))
            load = .ready
        } catch let e as LeylineFailure where e.status == 404 || e.status == 501 {
            load = .absent
        } catch {
            // Lists already on screen stay; only a first load that failed shows the failure.
            if hosts.isEmpty, keys.isEmpty { load = .failed(words(error)) }
        }
    }

    // MARK: derived

    func hostItem(_ id: String?) -> HostItem? { id.flatMap { id in hosts.first { $0.id == id } } }
    func key(_ id: String?) -> KeyItem? { id.flatMap { id in keys.first { $0.id == id } } }
    var open: HostItem? { hostItem(openID) }

    /// The gallery's cards after the Filter field.
    var shown: [HostItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty
            ? hosts
            : hosts.filter {
                $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
                    || ($0.group ?? "").lowercased().contains(q) || $0.tags.contains { $0.contains(q) }
            }
    }
    var groups: [HostGroup] { HostGroup.grouping(shown) }

    /// The hosts a key logs in to, for the "used by" chips.
    func usedBy(_ key: KeyItem) -> [HostItem] { hosts.filter { $0.keyID == key.id } }

    /// The host key pinned for a host, if the Core has one.
    func pinned(_ h: HostItem) -> KnownHostItem? { knownHosts.first { $0.host == h.name } }

    /// The names a host is reached through: the Core (or its runner), then each jump host, then the host itself.
    func route(_ h: HostItem) -> [String] {
        [h.viaRunner == nil ? coreName : "runner"] + h.jumpChain.map { hostItem($0)?.name ?? "a removed host" }
    }

    // MARK: words

    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        if let e = error as? LeylineFailure {
            return e.status == 404 && load == .ready ? "That is gone. Reload and try again." : e.sentence
        }
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return error.localizedDescription }
        return e.localizedDescription
    }

    /// Writes are refused while the Core is unreachable or rate limiting: a toast says so.
    func mayWrite() -> Bool {
        if readOnly {
            host.shell.showToast("This device can look at hosts but not change them.", kind: .warn)
            return false
        }
        guard let why = host.pausedReason else { return true }
        host.shell.showToast(why)
        return false
    }

    func clearWriteError() { writeError = nil }
    func setWriteError(_ s: String?) { writeError = s }

    // MARK: writes

    /// Checks a draft the way the Core will, in words; nil when it passes.
    static func problem(_ d: HostDraft) -> String? {
        if !HostRules.label(d.name) { return "Give the host a name of up to 64 characters." }
        if !HostRules.address(d.address) { return "The address is a name or IP address, with no spaces." }
        if !HostRules.username(d.username) { return "The user is letters, digits, dots, dashes and underscores." }
        if !HostRules.port(d.port) { return "The port is a number from 1 to 65535." }
        if let g = d.group, !HostRules.label(g) { return "The group is up to 64 characters." }
        return nil
    }

    /// Adds a host (a name and an address is enough: it asks first by default). The new host opens. Returns false when
    /// nothing was added; the sheet or pop-over stays open with its error.
    @discardableResult
    func addHost(_ draft: HostDraft) async -> Bool {
        guard let service, !busy, mayWrite() else { return false }
        if let p = Self.problem(draft) {
            writeError = p
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        let made: HostItem
        do { made = try await service.createHost(draft) } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return false
        }
        quickOpen = false
        quickText = ""
        await reload()
        page = .hosts
        host.shell.closeDialog()
        host.shell.showToast("\(made.name) added")
        return true
    }

    /// Saves the edit sheet: every field it owns goes in one change.
    @discardableResult
    func saveHost(_ id: String, _ draft: HostDraft) async -> Bool {
        guard let service, !busy, mayWrite() else { return false }
        if let p = Self.problem(draft) {
            writeError = p
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        do { _ = try await service.patchHost(id, .edit(draft)) } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return false
        }
        await reload()
        host.shell.closeDialog()
        host.shell.showToast("Saved")
        return true
    }

    /// The three-choice AI rule. "Allowed" lets AI run commands without asking, so it needs Touch ID; the two safer ones do not.
    func setRule(_ h: HostItem, _ rule: AIRule) async {
        guard let service, !busy, rule != h.aiRule, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            if rule == .allowed {
                try await host.elevated(
                    "Let AI run commands on \(h.name) without asking.", done: "changed", keepsEdit: false
                ) { _ = try await service.patchHost(h.id, .rule(rule)) }
            } else {
                _ = try await service.patchHost(h.id, .rule(rule))
            }
            await reload()
        } catch is AdminDeclined {
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            host.shell.showToast(words(error), kind: .warn)
        }
    }

    /// Makes a key in the Core (its private half never leaves it). Needs Touch ID.
    @discardableResult
    func generateKey(name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        guard HostRules.label(name) else {
            writeError = "Give the key a name of up to 64 characters."
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        do {
            try await host.elevated("Make the key \(name) in the Core.", done: "created", keepsEdit: true) {
                _ = try await service.generateKey(name: name)
            }
        } catch is AdminDeclined {
            return false
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return false
        }
        await reload()
        host.shell.closeDialog()
        host.shell.showToast("\(name) made. Its private half stays in the Core.")
        return true
    }

    /// Hands the Core a private key it keeps sealed. Needs Touch ID. The key text is not kept here.
    @discardableResult
    func importKey(name: String, privateKey: String, passphrase: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        guard HostRules.label(name) else {
            writeError = "Give the key a name of up to 64 characters."
            return false
        }
        guard privateKey.contains("BEGIN OPENSSH PRIVATE KEY") else {
            writeError = "Paste an OpenSSH private key (it starts with BEGIN OPENSSH PRIVATE KEY)."
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        do {
            try await host.elevated("Import the key \(name) into the Core.", done: "imported", keepsEdit: true) {
                _ = try await service.importKey(
                    name: name, privateKey: privateKey, passphrase: passphrase.isEmpty ? nil : passphrase)
            }
        } catch is AdminDeclined {
            return false
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return false
        }
        await reload()
        host.shell.closeDialog()
        host.shell.showToast("\(name) imported")
        return true
    }

    // MARK: selection

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: navigation

    func openHost(_ id: String) {
        section = .overview
        withAnimation(Motion.out(Motion.move)) { openID = id }
    }

    func closeHost() {
        withAnimation(Motion.out(Motion.move)) { openID = nil }
    }

    func newHost() {
        guard !readOnly else { return }
        show()
        page = .hosts
        quickText = ""
        writeError = nil
        quickOpen = true
    }

    /// ⌘N while the gallery is up: the same as Add Host.
    func newItem() { if openID == nil { newHost() } }

    func show() {
        let shell = host.shell
        var spec = PaneSpec(
            id: "leyline", title: "Leyline", sub: "Home Core", symbol: "point.3.connected.trianglepath.dotted",
            minWidth: 720
        ) { LeylineView(model: self) }
        spec.tab = "Leyline"
        spec.onNew = { [weak self] in self?.newItem() }
        shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
        func entry(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String], action: Bool = false,
            _ run: @escaping @MainActor (LeylineModel) -> Void
        ) {
            shell.launcher.register(
                LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys, isAction: action) {
                    [weak self] in if let self { run(self) }
                })
        }
        entry(
            "leyline", "Leyline", "Your hosts, their keys and how to reach them",
            "point.3.connected.trianglepath.dotted", ["ssh", "host", "server", "key", "terminal"]
        ) { $0.show() }
        entry(
            "add-host", "Add Host", "user@address and Return · asks first by default", "plus",
            ["ssh", "server", "create", "host"], action: true
        ) { $0.newHost() }
        entry(
            "add-host-advanced", "Add Host (advanced)…", "Key, jump hosts, group and tags, AI rule",
            "slider.horizontal.3",
            ["ssh", "server", "create", "host", "jump"], action: true
        ) {
            $0.show()
            $0.page = .hosts
            HostDialogs.openAdd($0, login: "")
        }
        entry(
            "generate-key", "Generate Key", "A new SSH key, sealed in the Core · needs Touch ID", "key",
            ["ssh", "keypair", "create"], action: true
        ) {
            $0.show()
            $0.page = .keys
            KeyDialogs.openGenerate($0)
        }
    }
}
