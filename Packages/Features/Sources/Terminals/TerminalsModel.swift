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

enum TerminalFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case ended = "Ended"
    var id: String { rawValue }
    func matches(_ t: TerminalItem) -> Bool {
        switch self {
        case .all: true
        case .running: !t.isEnded
        case .ended: t.isEnded
        }
    }
}

/// What the runner detail shows for the no-op test.
enum NoopOutcome: Equatable {
    case running
    case answered(ms: Int)
    case failed(String)
}

/// The terminals feature: what the Core lists, the runners, the open panes and their sessions. Views read it; the Core is
/// reached only through `TerminalService`.
@MainActor @Observable
public final class TerminalsModel {
    private(set) var items: [TerminalItem] = []
    private(set) var runners: [RunnerItem] = []
    private(set) var load: Load = .idle
    var filter: TerminalFilter = .all
    var selected: String?
    /// The runner whose page is open in the Runners pane (nil: the fleet).
    var runnerDetail: String?
    private(set) var noop: [String: NoopOutcome] = [:]
    private(set) var sessions: [String: TerminalSession] = [:]
    /// Terminals whose bell rang since they were last opened.
    private(set) var rang: Set<String> = []
    /// Host load (1 minute average per core) of each runner, as this Mac read it on each look, oldest first. The Core reports
    /// only the current value, so the chart is what was sampled while the app watched.
    private(set) var loadSamples: [String: [Double]] = [:]
    var newTerminal: NewTerminalModel?

    let host: any TerminalHost
    let service: any TerminalService
    private var reloading: Task<Void, Never>?
    private var registeredRunners: Set<String> = []

    public convenience init(host: any TerminalHost, connection: CoreConnection) {
        self.init(host: host, service: LiveTerminalService(connection: connection))
    }

    init(host: any TerminalHost, service: any TerminalService) {
        self.host = host
        self.service = service
    }

    var shell: ShellModel { host.shell }
    var openCount: Int { items.filter { !$0.isEnded }.count }
    var shown: [TerminalItem] { items.filter(filter.matches) }
    func runner(_ id: String) -> RunnerItem? { runners.first { $0.id == id } }
    /// What a terminal is called on screen: the tab name the person gave it, else the machine it runs on.
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
            load = .ready
            for t in terminals { sessions[t.id]?.apply(item: t, runner: runner(t.runner)) }
            for s in sessions.values where !terminals.contains(where: { $0.id == s.id }) { await s.refresh() }
            syncRunners()
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

    func openRunners(_ id: String? = nil) {
        runnerDetail = id
        shell.openPane(
            PaneSpec(id: "runners", title: "Runners", sub: "Home Core", symbol: "server.rack", minWidth: 480) {
                RunnersView(model: self)
            })
        Task { await reload() }
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
                        if cmd == .forceQuit { self?.confirmForceQuit(session) } else { Task { _ = await session.run(cmd) } }
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
        guard !shell.panes.contains(where: { $0.id == "terminal-\(id)" }) else { return }
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

    /// New terminal with the defaults: the first ready runner, its login shell, opened after Touch ID with no sheet. When
    /// nothing is ready or the Core refuses, the advanced sheet opens with the reason.
    func quickNew() {
        Task {
            if runners.isEmpty { await reload() }
            let prefs = TerminalPrefs.shared
            let m = NewTerminalModel(model: self, runner: prefs.defaultRunner.isEmpty ? nil : prefs.defaultRunner)
            m.program = prefs.defaultShell
            guard m.canOpen else { return openNew(form: m) }
            await m.submit()
            if m.error != nil { openNew(form: m) }
        }
    }

    func openNew(runner: String? = nil, form: NewTerminalModel? = nil) {
        let m = form ?? NewTerminalModel(model: self, runner: runner)
        newTerminal = m
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
        items.insert(t, at: 0)
        openTerminal(t.id)
        await reload()
        if TerminalPrefs.shared.openFullPane {
            shell.activePane = "terminal-\(t.id)"
            shell.focusedPane = "terminal-\(t.id)"
        }
        shell.showToast("A terminal opened on \(name(of: t.runner))")
    }

    // MARK: runner no-op

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
    var canOpen: Bool { !busy && blockedReason == nil }

    /// Why Open is off, in plain words; nil when it can go.
    var blockedReason: String? {
        guard let c = chosen else {
            return model.runners.isEmpty ? "No runner is paired with this Core." : "Pick a runner to open it on."
        }
        if !c.online { return "That runner is offline." }
        if !c.hasPty { return "Terminals are off on that runner." }
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
                    runner: r.id, program: program.isEmpty ? nil : program, rows: 30, cols: 100)
            }
            await model.created(t)
        } catch is ElevationDeclined {
        } catch {
            self.error = Self.refusal(CoreError.unwrapping(error), runner: r.name)
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
            case "unsupported_command":
                return Refusal(
                    title: "\(runner) doesn’t offer that.", text: message, code: code, http: status)
            default: return Refusal(title: message, text: "", code: code, http: status)
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
