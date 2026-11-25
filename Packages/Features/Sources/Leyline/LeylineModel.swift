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
    /// Shows a Core terminal (a host terminal the Core just opened) in the existing terminal pane. The app sets it; nil when
    /// there is no terminal app (the Debug demo), and the host page then says so.
    public var openTerminal: (@MainActor (String) async -> Void)?
    /// Tells the terminal pane of a host terminal whether the Core is recording it: nil = not recorded, else whether it is
    /// paused. The app sets it; the terminal app draws the "Recording" notice.
    public var markRecording: (@MainActor (String, Bool?) -> Void)?
    /// The paired device with this id (name, platform, key fingerprint), from the app's device list: who claimed a runner invite.
    public var deviceLookup: (@MainActor (String) -> RunnerClaimer?)?

    /// How the runner this host was made into is doing: online, and the AI tool being installed. The app sets it from the
    /// Runners list; nil shows the host's Runner card without live state.
    public var runnerGlance: (@MainActor (String) -> RunnerGlance?)?
    /// Opens a runner's page in Devices & Runners.
    public var openRunner: (@MainActor (String) -> Void)?

    var hosts: [HostItem] = []
    var keys: [KeyItem] = []
    var knownHosts: [KnownHostItem] = []
    var load: LeylineLoad = .notConnected
    /// The page: the hosts (map or list), or Keys.
    var page = LeylinePage.hosts
    /// "Type to find a host": typing anywhere on the page fills it.
    var filter = ""
    /// Map or List.
    var layout = LeylineLayout.map
    /// The selected host: the lit route on the map, the row in the list, the host panel.
    var selected: String?
    /// The group whose hosts are spread out on a big map.
    var openGroup: String?
    /// The host whose view is open (nil: the map or the list).
    var openID: String?
    var section = HostSection.terminal
    /// Each host's health, read from the Core's stored samples (at most once a minute).
    var healthByHost: [String: HostHealth] = [:]
    var healthReadAt: Date?
    /// The last things that happened on a host, read when it is selected.
    var activity: [String: [HostEvent]] = [:]
    /// What the Core does not send yet (see `HostExtras`): empty on a live Core.
    var extras: [String: HostExtras] = [:]
    /// The Add Host wizard while it is open.
    var wizard: AddHostFlow?
    /// Debug demo only: Add Host also draws what the Core cannot do yet (a stored password, a sign-in test before saving), so
    /// its screenshots show the whole design. Always false on a live Core.
    var previewGaps = false
    /// The terminal each host's view embeds, so coming back shows the same one.
    var hostTerminals: [String: String] = [:]
    /// Draws a Core terminal inside the host view. The app sets it; nil (the Debug demo) shows a stand-in.
    public var terminalView: (@MainActor (String) -> AnyView?)?
    /// The Core's project names, for Add Host's Project picker. The app sets it.
    public var projectNames: (@MainActor () -> [String])?
    /// A refusal from the Core (or the sheet's own check) for the write in flight, in words.
    private(set) var writeError: String?
    private(set) var busy = false
    /// A write came back `forbidden_scope`: this device can read but not change.
    private(set) var readOnly = false
    /// The Core's name, for "Reached through" (the Core this Mac is paired with).
    var coreName: String { host.shell.home.coreName.isEmpty ? "Home Core" : host.shell.home.coreName }
    #if DEBUG
    /// Snapshots only: the Make Runner state a host page opens in.
    var debugRunner: HostPageState.RunnerInstallState?
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
        selected = nil
        wizard = nil
        healthByHost = [:]
        healthReadAt = nil
        activity = [:]
        hostTerminals = [:]
        readOnly = false
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }

    /// An event from the Core that may change what the screens show.
    public func event(kind: String) {
        guard kind.hasPrefix("leyline.") else { return }
        resync()
        if kind == "leyline.session" { Task { await syncRecording() } }
    }

    // MARK: recording of host terminals

    /// Host terminals this app opened, by terminal id: the host, and the Core session once it is known.
    private var watched: [String: (host: String, session: String?)] = [:]

    func watchRecording(terminal: String, host: String) {
        watched[terminal] = (host, nil)
        Task { await syncRecording() }
    }

    /// Reads the Core's sessions for the terminals being watched and tells each pane whether it is recorded or paused.
    func syncRecording() async {
        guard let service else { return }
        for (terminal, w) in watched {
            guard let rows = try? await service.sessions(host: w.host),
                let row = rows.first(where: { $0.terminal == terminal })
            else { continue }
            watched[terminal]?.session = row.id
            if row.live {
                markRecording?(terminal, row.recorded ? row.paused : nil)
            } else {
                markRecording?(terminal, nil)
                watched[terminal] = nil
            }
        }
    }

    /// "Pause recording" on a terminal pane. Pausing needs no Touch ID (a person who sees a recording can stop it at once).
    public func pauseRecording(terminal: String) async {
        guard let service, let session = watched[terminal]?.session else { return }
        do { try await service.pauseRecording(session: session) } catch {
            host.shell.showToast(words(error), kind: .warn)
        }
        await syncRecording()
    }

    func reload() async {
        guard let service else { return }
        do {
            async let h = service.hosts()
            async let k = service.keys()
            async let n = service.knownHosts()
            hosts = try await h
            keys = try await k
            knownHosts = try await n
            load = .ready
            if selected.map({ id in !hosts.contains { $0.id == id } }) ?? true { selected = fleet.first?.id }
        } catch let e as LeylineFailure where e.status == 404 || e.status == 501 {
            load = .absent
        } catch {
            // Lists already on screen stay; only a first load that failed shows the failure.
            if hosts.isEmpty, keys.isEmpty { load = .failed(words(error)) }
        }
    }

    // MARK: derived

    /// Whether an address answers like an SSH server from the Core, for Add Host's live check.
    func checkHost(_ address: String, _ port: Int) async throws -> HostCheck {
        guard let service, !checkNeedsStepUp else { throw LeylineFailure.notYet }
        do { return try await service.checkHost(address: address, port: port) } catch let e as LeylineFailure
            where e.code == "step_up_required"
        {
            // The check needs a live step-up; typing never prompts for one, so it stays quiet until the person unlocks.
            checkNeedsStepUp = true
            throw e
        }
    }

    /// The Core refused a host check for want of a step-up: Add Host stops asking while it is typed into.
    var checkNeedsStepUp = false

    func hostItem(_ id: String?) -> HostItem? { id.flatMap { id in hosts.first { $0.id == id } } }
    func key(_ id: String?) -> KeyItem? { id.flatMap { id in keys.first { $0.id == id } } }
    var open: HostItem? { hostItem(openID) }

    /// The hosts Settings, Leyline, Options lets the page show (before the find field).
    var fleet: [HostItem] {
        LeylineOptions.filter(
            hosts, show: LeylineOptions.current, opened: LeylineOptions.opened(), mine: LeylineOptions.mine())
    }
    /// Whether a host matches "Type to find a host": its name, address, group or a tag.
    func matches(_ h: HostItem) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || h.name.lowercased().contains(q) || h.address.lowercased().contains(q)
            || (h.group ?? "").lowercased().contains(q) || h.tags.contains { $0.contains(q) }
    }
    /// The hosts after the find field: the list shows only these; the map dims the rest.
    var shown: [HostItem] { fleet.filter(matches) }
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

    /// Adds a host (a name and an address is enough: it asks first by default) from the advanced sheet, and closes it. Returns
    /// false when nothing was added; the sheet stays open with its error.
    @discardableResult
    func addHost(_ draft: HostDraft) async -> Bool {
        guard let made = await createHost(draft) else { return false }
        host.shell.closeDialog()
        host.shell.showToast("\(made.name) added")
        return true
    }

    /// Creates a host and selects it; nil (with `writeError`) when the Core or the check refused.
    func createHost(_ draft: HostDraft) async -> HostItem? {
        guard let service, !busy, mayWrite() else { return nil }
        if let p = Self.problem(draft) {
            writeError = p
            return nil
        }
        busy = true
        writeError = nil
        defer { busy = false }
        let made: HostItem
        do {
            made = try await host.elevated("Add the host \(draft.name).", done: "added", keepsEdit: true) {
                try await service.createHost(draft)
            }
        } catch is AdminDeclined {
            writeError = "Adding a host needs Touch ID. Try again and confirm it."
            return nil
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return nil
        }
        LeylineOptions.markMine(made.id)
        await reload()
        page = .hosts
        selected = made.id
        openGroup = made.group ?? HostGroup.shared
        return made
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

    /// The Core refused an RSA key under 2048 bits (its sentence starts this way).
    var keyTooWeak: Bool { writeError?.hasPrefix("This key is too weak") == true }

    /// Hands the Core a private key it keeps sealed. Needs Touch ID. The key text is not kept here.
    @discardableResult
    func importKey(name: String, privateKey: String, passphrase: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        guard HostRules.label(name) else {
            writeError = "Give the key a name of up to 64 characters."
            return false
        }
        // No format check here: OpenSSH and PEM keys both go to the Core, which decides and says why not.
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

    // MARK: navigation

    /// Opens a host's view on a tab: the terminal at once by default. An offline host stays on the page.
    func openHost(_ id: String, _ tab: HostSection = .terminal) {
        guard hostItem(id)?.light != .off else {
            host.shell.showToast("It is not answering. Leyline tries again every minute.", kind: .warn)
            return
        }
        selected = id
        section = tab
        LeylineOptions.markOpened(id)
        if LeylineOptions.calmOn { withAnimation(Motion.out(Motion.move)) { openID = id } } else { openID = id }
    }

    func closeHost() {
        if LeylineOptions.calmOn { withAnimation(Motion.out(Motion.move)) { openID = nil } } else { openID = nil }
    }

    func newHost() {
        guard !readOnly else { return }
        show()
        page = .hosts
        writeError = nil
        checkNeedsStepUp = false
        AddHostWizard.open(self)
    }

    /// ⌘N while the page is up: the same as Add Host.
    func newItem() { if openID == nil { newHost() } }

    func show() {
        let shell = host.shell
        var spec = PaneSpec(
            id: "leyline", title: "Leyline", sub: "Home Core", symbol: "point.3.connected.trianglepath.dotted",
            minWidth: 860
        ) { LeylineView(model: self) }
        spec.tab = "Leyline"
        spec.onNew = { [weak self] in self?.newItem() }
        shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
        // Settings, Apps, Leyline: Look (follows Appearance unless turned off) and Options.
        shell.settings.section(
            SettingsSection(
                id: "leyline", group: .apps, title: "Leyline", sub: "Its look and what it shows",
                symbol: "point.3.connected.trianglepath.dotted", order: 7,
                tabs: [
                    SettingsTab("look", "Look", order: 0) {
                        AppLookSection(appName: "Leyline", prefs: AppLookPrefs.shared("leyline"))
                            .foregroundStyle(GlassInk.primary)
                    },
                    SettingsTab("options", "Options", order: 1) { LeylineOptionsTab() },
                ]))
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
            "add-host", "Add Host", "Server, sign in, name, check · asks first by default", "plus",
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
