import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI

enum Load: Equatable {
    case idle, loading, ready
    case failed(String)
}

/// The list's filter (E6-3): every terminal, only sandboxes, or only this Mac's own real shells.
enum TerminalFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sandbox = "Sandbox"
    case thisMac = "This Mac"
    var id: String { rawValue }
    /// `thisMac`: the runner that is this Mac's own, whose terminals count as real even when the Core did not say.
    func matches(_ t: TerminalItem, thisMac: String?) -> Bool {
        let real = t.isReal || (t.sandbox == nil && t.runner == thisMac)
        return switch self {
        case .all: true
        case .sandbox: !real
        case .thisMac: real
        }
    }
}

/// The terminals of one machine, for the list's sections: This Mac first, then the others by name.
struct TerminalGroup: Identifiable, Equatable {
    let id: String
    var name: String
    var isThisMac: Bool
    var items: [TerminalItem]
}

/// What the runner detail shows for the no-op test.
enum NoopOutcome: Equatable {
    case running
    case answered(ms: Int)
    case failed(String)
}

/// The terminals feature: what the Core lists, the runners, the open panes and their sessions. Views read it; the Core is
/// reached only through `TerminalService`.
/// What a pane shows of the Core's recording of its terminal (output only, redacted by the Core).
public struct PaneRecording: Equatable, Sendable {
    public var paused: Bool
    public init(paused: Bool = false) { self.paused = paused }
}

@MainActor @Observable
public final class TerminalsModel {
    private(set) var items: [TerminalItem] = []
    var runners: [RunnerItem] = []
    private(set) var load: Load = .idle
    var filter: TerminalFilter = .all
    var selected: String?
    /// The runner whose page is open in the Runners pane (nil: the fleet).
    var runnerDetail: String?
    /// The summary tile that is on (mockup 12); nil shows every runner.
    var runnerFilter: RunnerFacts.Live?
    private(set) var noop: [String: NoopOutcome] = [:]
    private(set) var sessions: [String: TerminalSession] = [:]
    /// Why the last embedded terminal did not open.
    var embedError: String?
    /// Terminals whose bell rang since they were last opened.
    private(set) var rang: Set<String> = []
    /// Host load (1 minute average per core) of each runner, as this Mac read it on each look, oldest first. The Core reports
    /// only the current value, so the chart is what was sampled while the app watched.
    private(set) var loadSamples: [String: [Double]] = [:]
    var newTerminal: NewTerminalModel?
    /// Host terminals the Core is recording (Leyline), by terminal id: the pane says so and offers Pause. Leyline sets it.
    public var recording: [String: PaneRecording] = [:]
    /// Pauses the Core's recording of a terminal. Leyline owns the Core call, so the app sets this.
    public var pauseRecording: (@MainActor (String) async -> Void)?
    /// Runner control (N17, N19): the policy being applied, why one was refused, and each runner's tool installs.
    var policyBusy: Set<String> = []
    var policyNote: [String: RunnerNote] = [:]
    var installs: [String: [String: ToolInstall]] = [:]

    let host: any TerminalHost
    let service: any TerminalService
    private var reloading: Task<Void, Never>?
    private var registeredRunners: Set<String> = []
    @ObservationIgnored private var registeredTerminals: Set<String> = []

    public convenience init(host: any TerminalHost, connection: CoreConnection) {
        self.init(
            host: host,
            service: LiveTerminalService(
                connection: connection, localRunner: { [weak host] in await host?.localRunner }))
    }

    init(host: any TerminalHost, service: any TerminalService) {
        self.host = host
        self.service = service
    }

    var shell: ShellModel { host.shell }
    var openCount: Int { items.filter { !$0.isEnded }.count }
    /// The list as sections, one per machine (E6-3).
    var groups: [TerminalGroup] {
        let mac = host.thisMacRunnerID
        let visible = items.filter { filter.matches($0, thisMac: mac) }
        return Dictionary(grouping: visible, by: \.runner)
            .map { TerminalGroup(id: $0.key, name: name(of: $0.key), isThisMac: $0.key == mac, items: $0.value) }
            .sorted { ($0.isThisMac ? 0 : 1, $0.name) < ($1.isThisMac ? 0 : 1, $1.name) }
    }
    /// Every shown terminal in the order the sections draw them: the order the arrow keys walk.
    var shown: [TerminalItem] { groups.flatMap(\.items) }
    /// The machine ⌘T opens on: the last one used, else the default, else the best ready one (nil lets the form choose).
    var quickRunner: String? {
        let prefs = TerminalPrefs.shared
        for id in [prefs.lastRunner, prefs.defaultRunner] where !id.isEmpty {
            if let r = runner(id), RunnerStatus(r) != .off, r.hasPty { return id }
        }
        return nil
    }
    func runner(_ id: String) -> RunnerItem? { runners.first { $0.id == id } }
    /// What a terminal is called on screen: the tab name the person gave it, else the machine it runs on.
    /// A fresh look at the runners the Core lists, by name (the Add runner wizard watches this for the new one).
    public func freshRunnerNames() async -> [String] {
        await reload()
        return runners.map(\.name)
    }

    /// "Yes" or "No (reason)": whether AI sessions on this runner can use the Core's accounts; nil when not reported.
    public func accountsAnswer(forRunner id: String) -> String? {
        runners.first { $0.id == id }.flatMap { RunnerFacts(runner: $0).accountsAnswer }
    }

    /// Whether the Core lists this runner as online; nil when it is not in the list yet.
    public func isOnline(runner id: String) -> Bool? {
        runners.first { $0.id == id }.map { [.ok, .busy].contains(RunnerFacts(runner: $0).status) }
    }

    /// Called after every look at the Core's terminals, so Home can refresh its Terminals widget.
    public var changed: (@MainActor () -> Void)?

    /// What the Home Terminals widget shows: the live terminals, where each runs, and the last lines of the ones this
    /// Mac has open (the Core keeps no screen, so the others show none).
    public func homeFacts() -> [HomeSnapshot.TerminalFact] {
        items.filter { !$0.isEnded }.map { t in
            let mac = t.runner == host.thisMacRunnerID
            let lines = (sessions[t.id]?.surface.visibleText() ?? "").split(whereSeparator: \.isNewline)
                .map { String($0.trimmingCharacters(in: .whitespaces).prefix(80)) }.filter { !$0.isEmpty }.suffix(3)
            return .init(
                id: t.id, name: displayName(ofTerminal: t.id) ?? t.id, place: mac ? "This Mac" : name(of: t.runner),
                onThisMac: mac, lines: Array(lines))
        }
    }

    public func displayName(ofTerminal id: String) -> String? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return shell.tabNames["terminal-\(id)"] ?? name(of: item.runner)
    }

    func name(of runner: String) -> String { self.runner(runner)?.name ?? runner }
    func onRunner(_ id: String) -> Int { items.filter { $0.runner == id && !$0.isEnded }.count }

    // MARK: data

    /// A refetch of both lists, coalesced: many events in a burst cost one request.
    public func resync() {
        guard reloading == nil else { return }
        reloading = Task {
            try? await Task.sleep(for: .milliseconds(250))
            await reload()
            reloading = nil
        }
    }

    /// The event stream said something: terminal and runner events mean "look again".
    public func event(kind: String) {
        if kind.hasPrefix("terminal.") || kind.hasPrefix("runner.") { resync() }
    }

    func reload() async {
        if items.isEmpty && runners.isEmpty { load = .loading }
        do {
            async let t = service.terminals()
            async let r = service.runners()
            let (terminals, fleet) = try await (t, r)
            items = terminals.sorted(by: Self.order)
            runners = fleet.sorted { $0.name < $1.name }
            for r in runners { sampleLoad(r) }
            applyReported()
            load = .ready
            for t in terminals { sessions[t.id]?.apply(item: t, runner: runner(t.runner)) }
            for s in sessions.values where !terminals.contains(where: { $0.id == s.id }) { await s.refresh() }
            syncRunners()
            syncLauncherTerminals()
            changed?()
        } catch { load = .failed(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription) }
    }

    #if DEBUG
    func debugSeedLoad(_ id: String, _ values: [Double]) { loadSamples[id] = values }
    #endif

    func sampleLoad(_ r: RunnerItem) {
        guard r.online, let p = r.perCore else { return }
        var list = loadSamples[r.id] ?? []
        list.append(p)
        if list.count > 60 { list.removeFirst(list.count - 60) }
        loadSamples[r.id] = list
    }

    private static func order(_ a: TerminalItem, _ b: TerminalItem) -> Bool {
        if a.isEnded != b.isEnded { return !a.isEnded }
        return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
    }

    // MARK: launcher and bell

    /// Launcher entries and the bell for runner problems. Ids match the shell's own sample entries, so Demo mode keeps its own.
    /// One Touch ID unlocks every terminal: when the session is elevated, each pane waiting on "Verify to reattach"
    /// attaches again on its own (Ahmed, 2026-11-05).
    private func followElevation() {
        withObservationTracking {
            _ = shell.elevatedUntil
            _ = shell.lock  // the app unlock stands for the elevation
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.host.isElevated {
                    for s in self.sessions.values where s.waitsForVerify { Task { await s.attach(prompt: false) } }
                }
                self.followElevation()
            }
        }
    }

    public func install() {
        followElevation()
        shell.settings.section(
            SettingsSection(
                id: "terminal", group: .apps, title: "Terminals", sub: "Look, screen, surface and defaults",
                symbol: "terminal", order: 10
            ) { TerminalSettingsView(model: self) })
        let l = shell.launcher
        l.register(
            LauncherEntry(
                id: "settings.terminal", title: "Terminals settings", sub: "Look, screen, surface and defaults",
                symbol: "gearshape", keywords: ["appearance", "theme", "font", "transparency", "terminal"]
            ) { [weak self] in
                self?.shell.settings.selected = "terminal"
                self?.shell.open(.settings)
            })
        l.register(
            LauncherEntry(
                id: "terminals", title: "Terminals", sub: "Your terminals", symbol: "terminal",
                keywords: ["rune", "shell", "zsh", "bash"]
            ) { [weak self] in self?.openList() })
        // Quick by default, advanced on request (Ahmed, 2026-11-05): New terminal opens one at once with the defaults;
        // the advanced sheet picks the runner and the shell.
        l.register(
            LauncherEntry(
                id: "new-terminal", title: "New terminal", sub: "Opens at once on the best runner · needs Touch ID",
                symbol: "terminal", keywords: ["shell", "rune"], isAction: true
            ) { [weak self] in self?.quickNew() })
        l.register(
            LauncherEntry(
                id: "new-terminal-advanced", title: "New terminal (advanced)…",
                sub: "Choose the runner and the shell", symbol: "slider.horizontal.3",
                keywords: ["shell", "rune", "runner", "zsh", "bash"], isAction: true
            ) { [weak self] in self?.openNew() })
        l.register(
            LauncherEntry(
                id: "runners", title: "Runners", sub: "Load, drivers and isolation of each runner",
                symbol: "server.rack", keywords: ["runner", "machine", "load"]
            ) { [weak self] in self?.openRunners() })
    }

    /// One launcher entry per terminal that is still there (⌘K → Terminals), opening its pane.
    private func syncLauncherTerminals() {
        let live = items.filter { ["created", "running"].contains($0.status) }
        let ids = Set(live.map(\.id))
        for gone in registeredTerminals.subtracting(ids) { shell.launcher.unregister("terminal-\(gone)") }
        for t in live {
            shell.launcher.register(
                LauncherEntry(
                    id: "terminal-\(t.id)", title: displayName(ofTerminal: t.id) ?? "Terminal",
                    sub: "On \(name(of: t.runner))", symbol: "terminal", keywords: ["terminal", "shell", name(of: t.runner)]
                ) { [weak self] in self?.openTerminal(t.id) })
        }
        registeredTerminals = ids
    }

    /// One launcher entry per runner, and a bell item for each runner that is off or slow.
    private func syncRunners() {
        for r in runners where !registeredRunners.contains(r.id) {
            registeredRunners.insert(r.id)
            shell.launcher.register(
                LauncherEntry(
                    id: "runner-\(r.id)", title: "Runner \(r.name)", sub: Self.spec(r), symbol: "server.rack",
                    keywords: ["runner", r.name]
                ) { [weak self] in self?.openRunners(r.id) })
        }
        for id in registeredRunners where !runners.contains(where: { $0.id == id }) {
            registeredRunners.remove(id)
            shell.launcher.unregister("runner-\(id)")
        }
        for r in runners {
            let id = "runner-\(r.id)"
            switch RunnerStatus(r) {
            case .off:
                shell.bell.add(
                    BellItem(
                        id: id, kind: .runner, title: "\(r.name) disconnected",
                        sub: "Its terminals can't be reached until it's back.", time: "now",
                        actions: [BellAction("View runner", primary: true) { [weak self] in self?.viewRunner(r.id) }]))
            case .degraded:
                shell.bell.add(
                    BellItem(
                        id: id, kind: .runner, title: "\(r.name) is slow to answer",
                        sub: "It missed two check-ins in a row.", time: "now",
                        actions: [BellAction("View runner", primary: true) { [weak self] in self?.viewRunner(r.id) }]))
            default: shell.bell.remove(id)
            }
        }
    }

    private func viewRunner(_ id: String) {
        shell.bellOpen = false
        openRunners(id)
    }

    static func spec(_ r: RunnerItem) -> String {
        [r.arch, r.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: panes

    func openList() {
        var spec = PaneSpec(
            id: "terminals", title: "Terminals", sub: "Home Core", symbol: "terminal",
            chip: PaneChip("Home Core", tone: .queue, symbol: "server.rack"), minWidth: 560
        ) { TerminalsListView(model: self) }
        spec.tab = "Terminals"
        shell.openPane(spec)
        Task { await reload() }
    }

    public func openRunners(_ id: String? = nil) {
        runnerDetail = id
        shell.openPane(
            PaneSpec(id: "runners", title: "Runners", sub: "Home Core", symbol: "server.rack", minWidth: 480) {
                RunnersView(model: self)
            })
        Task { await reload() }
    }

    /// Opens the pane of a terminal the Core made elsewhere (a Leyline host terminal): reads the list first so it is known.
    public func openRemote(_ id: String) async {
        await reload()
        openTerminal(id)
    }

    /// Opens a terminal's pane. `attach`: connect at once (a terminal this app just made, or one nobody else holds).
    public func openTerminal(_ id: String, attach: Bool = true) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        selected = id
        rang.remove(id)
        let session: TerminalSession
        if let s = sessions[id] {
            session = s
        } else {
            session = TerminalSession(item: item, runner: runner(item.runner), service: service, host: host)
            session.onBell = { [weak self] in self?.bell(id) }
            session.onChange = { [weak self] in self?.paneChanged(id) }
            sessions[id] = session
        }
        let pane = "terminal-\(id)"
        shell.openPane(
            PaneSpec(id: pane, title: "Rune", sub: name(of: item.runner), symbol: "terminal", minWidth: 560) {
                // The screen draws its own background in its theme's colour: the pane gives the rim only.
                TerminalPaneView(model: self, session: session).paneLook(nil, own: true)
            })
        shell.setPaneMenu(pane) { [weak self, weak session] in
            guard let self, let session else { return [] }
            return self.menu(for: session)
        }
        paneChanged(id)
        if attach, item.status == "running" || item.status == "created", item.attached == 0 || session.isAttached {
            Task { await session.attach() }
        } else if attach, item.status == "exited" {
            Task { await session.attach() }
        }
    }

    /// A terminal pane's tab menu: what it is, then running command, detach and end, enabled by the pane's state.
    func menu(for session: TerminalSession) -> [PaneMenuItem] {
        let v = session.view
        let live = v.controls == .running
        let canEnd = v.controls == .running || v.controls == .endOnly
        var items = [PaneMenuItem(v.info, symbol: "info.circle", enabled: false)]
        if v.controls == .ended {
            items.append(PaneMenuItem("Close Pane", symbol: "xmark") { [weak self] in self?.closePane(session.id) })
            return items
        }
        let commands: [RunningCommand] = [.stop, session.paused ? .resume : .pause, .forceQuit]
        items.append(
            PaneMenuItem(
                "Running command…", symbol: "bolt", enabled: live,
                children: commands.map { cmd in
                    PaneMenuItem(cmd.title, symbol: cmd.symbol, destructive: cmd == .forceQuit, help: cmd.help) {
                        [weak self] in
                        if cmd == .forceQuit {
                            self?.confirmForceQuit(session)
                        } else {
                            Task { _ = await session.run(cmd) }
                        }
                    }
                }))
        items.append(PaneMenuItem("Detach", symbol: "eject", enabled: live) { session.detach() })
        items.append(
            PaneMenuItem("End Terminal…", symbol: "stop.circle", destructive: true, enabled: canEnd) { [weak self] in
                self?.confirmEnd(session)
            })
        return items
    }

    /// Acts on a terminal from the list: its session if this Mac has one, else one made without attaching.
    func session(for id: String) -> TerminalSession? {
        if sessions[id] == nil { openTerminal(id, attach: false) }
        return sessions[id]
    }

    func confirmEnd(_ session: TerminalSession) {
        guard TerminalPrefs.shared.confirmEnd else {
            Task { _ = await session.end() }
            return
        }
        shell.presentSheet(
            title: "End this terminal?",
            message:
                "The terminal on \(session.machine) and everything running in it will stop. Closing the pane only detaches. This needs Touch ID.",
            actions: [
                ShellSheetAction("Keep it"),
                ShellSheetAction("End terminal", destructive: true) { Task { _ = await session.end() } },
            ], symbol: "stop.circle")
    }

    func confirmForceQuit(_ session: TerminalSession) {
        shell.presentSheet(
            title: "Force quit the running command?",
            message:
                "\(RunningCommand.forceQuit.help) Try Stop it first. The terminal on \(session.machine) stays open. This needs Touch ID.",
            actions: [
                ShellSheetAction("Keep it running"),
                ShellSheetAction("Force quit", destructive: true) { Task { _ = await session.run(.forceQuit) } },
            ], symbol: "xmark.octagon")
    }

    func paneChanged(_ id: String) {
        guard let s = sessions[id] else { return }
        let v = s.view
        shell.updatePane(
            "terminal-\(id)", sub: .some(s.machine),
            chip: .some(PaneChip(v.chip.label, tone: v.chip.tone, symbol: v.chip.symbol)))
    }

    /// The pane went away (its close button, ⌘W): detach, never stop the terminal.
    func paneClosed(_ id: String) {
        guard !shell.allPanes.contains(where: { $0.id == "terminal-\(id)" }) else { return }
        sessions[id]?.shutDown()
        sessions[id] = nil
        Task { await reload() }
    }

    func closePane(_ id: String) {
        shell.closePane("terminal-\(id)")
        shell.showToast("Pane closed. The terminal stays in the list while it exists")
    }

    private func bell(_ id: String) {
        rang.insert(id)
        let name = name(of: items.first { $0.id == id }?.runner ?? "")
        shell.bell.add(
            BellItem(
                id: "terminal-bell-\(id)", kind: .event, title: "Bell in a terminal on \(name)", sub: "terminal bell",
                time: "now", actions: [BellAction("Open", primary: true) { [weak self] in self?.openFromBell(id) }]))
    }

    private func openFromBell(_ id: String) {
        shell.bell.remove("terminal-bell-\(id)")
        shell.bellOpen = false
        openTerminal(id)
    }

    // MARK: new terminal

    /// New terminal with the defaults: the first ready runner, the Ainkrad shell, opened after Touch ID with no sheet. When
    /// nothing is ready or the Core refuses, the advanced sheet opens with the reason.
    func quickNew() {
        Task {
            if runners.isEmpty { await reload() }
            let m = NewTerminalModel(model: self, runner: quickRunner)
            guard m.canOpen else { return openNew(form: m) }
            await m.submit()
            if m.error != nil { openNew(form: m) }
        }
    }

    /// Opens a terminal on `runner` at once, in AI session `session`'s folder when given; the New terminal sheet shows only
    /// if that fails. A session whose folder is unknown or gone falls back to the home folder.
    public func open(on runner: String, session: String? = nil) {
        Task {
            if runners.isEmpty { await reload() }
            let m = NewTerminalModel(model: self, runner: runner)
            m.session = session
            guard m.canOpen else { return openNew(form: m) }
            await m.submit()
            if m.error != nil { openNew(form: m) }
        }
    }

    /// A terminal for an embedded view (an AI session's Terminal tab): created in `session`'s folder on `runner` and attached, with
    /// no pane of its own. nil when it could not open (the reason is in `embedError`).
    func embed(on runner: String, session: String) async -> TerminalSession? {
        embedError = nil
        if runners.isEmpty { await reload() }
        let form = NewTerminalModel(model: self, runner: runner)
        form.session = session
        guard form.canOpen else {
            embedError = form.blockedReason
            return nil
        }
        do {
            let t = try await host.elevated(
                "Open a terminal in this AI session's folder. This approval covers this terminal only.", done: "opened",
                keepsEdit: true
            ) { try await self.service.create(runner: runner, program: nil, session: session, rows: 30, cols: 100) }
            items.insert(t, at: 0)
            let s = TerminalSession(item: t, runner: self.runner(t.runner), service: service, host: host)
            s.onBell = { [weak self] in self?.bell(t.id) }
            s.onChange = { [weak self] in self?.paneChanged(t.id) }
            sessions[t.id] = s
            await s.attach()
            return s
        } catch is ElevationDeclined {
            return nil
        } catch {
            embedError = NewTerminalModel.refusal(CoreError.unwrapping(error), runner: name(of: runner)).title
            return nil
        }
    }

    func openNew(runner: String? = nil, form: NewTerminalModel? = nil) {
        let m = form ?? NewTerminalModel(model: self, runner: runner ?? quickRunner)
        newTerminal = m
        Task { await m.loadProjects() }
        host.clearElevationNotice()
        shell.present(
            ShellDialog(
                id: "new-terminal",
                onClose: { [weak self] in
                    self?.newTerminal = nil
                    self?.host.clearElevationNotice()
                }
            ) { NewTerminalView(model: self, form: m) })
        Task { await reload() }
    }

    func created(_ t: TerminalItem) async {
        shell.closeDialog()
        TerminalPrefs.shared.lastRunner = t.runner
        items.insert(t, at: 0)
        openTerminal(t.id)
        await reload()
        if TerminalPrefs.shared.openFullPane {
            shell.activePane = "terminal-\(t.id)"
            shell.focusedPane = "terminal-\(t.id)"
        }
        shell.showToast("A terminal opened on \(name(of: t.runner))")
    }

    // MARK: runner management (N18, N19)

    func confirmRename(_ r: RunnerItem) {
        shell.present(ShellDialog(id: "runner-rename") { RenameRunnerDialog(model: self, runner: r) })
    }

    func confirmRevoke(_ r: RunnerItem) {
        let agents = host.runnerHost?.agentWork(on: r.id).count ?? 0
        shell.present(
            ShellDialog(id: "runner-revoke", onClose: { [weak self] in self?.host.clearElevationNotice() }) {
                RevokeRunnerDialog(model: self, runner: r, agents: agents, terminals: self.onRunner(r.id))
            })
    }

    /// nil when it worked, else why not.
    func renameRunner(_ id: String, to name: String) async -> String? {
        guard let h = host.runnerHost else { return "This build cannot rename runners." }
        let why = await h.renameRunner(id, to: name)
        if why == nil { await reload() }
        return why
    }

    func revokeRunner(_ id: String) async -> String? {
        guard let h = host.runnerHost else { return "This build cannot revoke runners." }
        let why = await h.revokeRunner(id)
        if why == nil {
            runnerDetail = nil
            await reload()
        }
        return why
    }

    // MARK: runner no-op

    /// The runner's no-op test, answered in a line (the Add flow's last screen).
    public func test(runner id: String) async -> String {
        await runNoop(id)
        switch noop[id] {
        case .answered(let ms)?: return "It answered in \(ms) ms."
        case .failed(let why)?: return "The test did not go through. \(why)"
        default: return "The test did not finish."
        }
    }

    func runNoop(_ id: String) async {
        noop[id] = .running
        do { noop[id] = .answered(ms: try await service.noop(id)) } catch {
            noop[id] = .failed(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

/// A runner's state in one word, as the prototype sorts them: ok, degraded, busy (over the per-core limit), off.
enum RunnerStatus: Equatable {
    case ok, degraded, busy, off
    /// Per-core load above which a runner refuses new work by default.
    static let busyPerCore = 4.0
    init(_ r: RunnerItem) {
        if !r.online {
            self = .off
        } else if r.degraded {
            self = .degraded
        } else if (r.perCore ?? 0) > Self.busyPerCore {
            self = .busy
        } else {
            self = .ok
        }
    }
    var label: String {
        switch self {
        case .ok: "Online"
        case .degraded: "Degraded"
        case .busy: "Busy"
        case .off: "Disconnected"
        }
    }
    var tone: Tone {
        switch self {
        case .ok: .run
        case .degraded, .busy: .warn
        case .off: .fail
        }
    }
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle"
        case .degraded: "exclamationmark.triangle"
        case .busy: "gauge.with.dots.needle.100percent"
        case .off: "wifi.slash"
        }
    }
}

/// The New terminal sheet: pick a runner, say what it starts, open. Refusals land inline with the Core's code.
@MainActor @Observable
final class NewTerminalModel {
    var runner: String?
    var program = ""
    /// Start in this AI session's folder (the Core resolves the path).
    var session: String?
    /// Open in a project's folder (the sandbox shares only that folder), not the sandbox home.
    var inProject = false
    var projectID: Int?
    private(set) var projects: [TerminalProject] = []
    private(set) var busy = false
    private(set) var error: Refusal?
    private unowned let model: TerminalsModel

    struct Refusal: Equatable {
        var title: String
        var text: String
        var code: String
        var http: Int
    }

    init(model: TerminalsModel, runner: String?) {
        self.model = model
        self.runner = runner ?? model.runners.first(where: { RunnerStatus($0) != .off && $0.hasPty })?.id
    }

    var chosen: RunnerItem? { runner.flatMap { model.runner($0) } }
    /// The chosen machine is this Mac's own runner: a real shell, the only one (D-17).
    var isThisMac: Bool { runner != nil && runner == model.host.thisMacRunnerID }

    /// `NewTerminal.project`: a real shell on this Mac that starts in a project's folder (a cwd, not a mount).
    var projectParam: Int? { isThisMac && inProject && session == nil ? projectID : nil }

    /// `NewTerminal.sandbox`: this Mac is `real`; an AI session's folder names itself; else the sandbox home or a project.
    var sandbox: String? {
        if isThisMac { return "real" }
        if session != nil { return nil }
        if inProject, let p = projectID { return "project:\(p)" }
        return "home"
    }

    func loadProjects() async {
        projects = (try? await model.service.projects()) ?? []
        if projectID == nil { projectID = projects.first?.id }
    }
    var canOpen: Bool { !busy && blockedReason == nil }

    /// Why Open is off, in plain words; nil when it can go.
    var blockedReason: String? {
        guard let c = chosen else {
            return model.runners.isEmpty ? "No runner is paired with this Core." : "Pick a runner to open it on."
        }
        if !c.online { return "That runner is offline." }
        if !c.hasPty { return "Terminals are off on that runner." }
        if inProject, session == nil, projectID == nil { return "Pick a project." }
        return nil
    }

    func pick(_ id: String) {
        runner = id
        error = nil
    }

    func submit() async {
        guard !busy else { return }
        guard let r = chosen, blockedReason == nil else {
            error = Refusal(title: blockedReason ?? "Pick a runner to open it on.", text: "", code: "", http: 0)
            return
        }
        error = nil
        busy = true
        defer { busy = false }
        let program = program.trimmingCharacters(in: .whitespaces)
        do {
            let t = try await model.host.elevated(
                "Open a terminal on \(r.name). This approval covers this terminal only.", done: "opened",
                keepsEdit: true
            ) {
                try await self.model.service.create(
                    runner: r.id, program: program.isEmpty ? nil : program, session: self.session,
                    sandbox: self.sandbox, project: self.projectParam, rows: 30, cols: 100)
            }
            await model.created(t)
        } catch is ElevationDeclined {
        } catch {
            let e = CoreError.unwrapping(error)
            // The session's folder is unknown, gone or on another runner: open in the home folder instead.
            if session != nil, case .http(_, let code, _)? = e, code.hasPrefix("session_") {
                session = nil
                busy = false
                return await submit()
            }
            self.error = Self.refusal(e, runner: r.name)
        }
    }

    static func refusal(_ e: CoreError?, runner: String) -> Refusal {
        switch e {
        case .http(let status, let code, let message)?:
            switch code {
            case "limit_reached":
                return Refusal(title: "Too many terminals.", text: message, code: code, http: status)
            case "runner_offline":
                return Refusal(
                    title: "\(runner) is not connected.",
                    text:
                        "It dropped off after this list was loaded. Pick another runner, or wait for it to reconnect.",
                    code: code, http: status)
            case "runner_busy":
                return Refusal(
                    title: "\(runner) is too busy right now.",
                    text:
                        "New work is refused while its load is over the limit. Try again in a moment or use another runner.",
                    code: code, http: status)
            case "real_terminal_refused":
                return Refusal(
                    title: "A real shell is only for this Mac.",
                    text: "Open it from this Mac's own app, on this Mac's runner. Other machines open a sandbox.",
                    code: code, http: status)
            case "runner_update_required":
                return Refusal(
                    title: "Update this runner to open terminals.",
                    text: "\(runner) is too old to open a terminal safely. Runners update themselves; try again soon.",
                    code: code, http: status)
            case "project_folder_unknown":
                return Refusal(
                    title: "That project has no folder on \(runner) yet.",
                    text: "Start a session in the project on this machine, or open the sandbox home.",
                    code: code, http: status)
            case "unsupported_command":
                return Refusal(
                    title: "\(runner) doesn’t offer that.", text: message, code: code, http: status)
            default:
                // The runner's own words name the flag; say what to do about it.
                if message.contains("--terminal-user") {
                    return Refusal(
                        title:
                            "This runner was started with --terminal-user; restart it without it to open terminals.",
                        text: "", code: code, http: status)
                }
                return Refusal(title: message, text: "", code: code, http: status)
            }
        case .forbiddenScope?:
            return Refusal(
                title: "This device may not open terminals.", text: "It needs the terminal scope.",
                code: "forbidden_scope",
                http: 403)
        case let other?:
            return Refusal(title: other.localizedDescription, text: "", code: "error", http: 0)
        case nil: return Refusal(title: "The terminal was not opened.", text: "", code: "error", http: 0)
        }
    }
}
