import Admin
import AppKit
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// A piece of the host page that is read from the Core.
enum PageLoad<T: Sendable>: Sendable {
    case idle, loading
    case ready(T)
    /// The Core has no route for it yet.
    case missing
    case failed(String)
    var value: T? { if case .ready(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}

/// Everything the open host's pages hold: health, the pre-set commands and their results, the files browser, history and the
/// replay, and the Mac-direct lease. One per open host space; it reads through the model's service and writes through the
/// model's guards (`mayWrite`, Touch ID), so a page never talks to the Core on its own.
@MainActor @Observable
final class HostPageState {
    let model: LeylineModel
    let hostID: String

    init(model: LeylineModel, hostID: String) {
        self.model = model
        self.hostID = hostID
        #if DEBUG
        if let r = model.debugRunner { runnerState = r }
        runs = model.debugRuns
        shown = model.debugShown
        #endif
    }

    var host: HostItem? { model.hostItem(hostID) }
    var service: (any LeylineService)? { model.service }
    var shell: ShellModel { model.host.shell }

    func words(_ e: any Error) -> String { model.words(e) }

    /// A read that can come back "not yet": the page shows the right words for it.
    private func read<T: Sendable>(_ op: (any LeylineService) async throws -> T) async -> PageLoad<T> {
        guard let service else { return .idle }
        do { return .ready(try await op(service)) } catch let e as LeylineFailure where e.isMissing {
            return .missing
        } catch {
            note(error)
            return .failed(words(error))
        }
    }

    // MARK: terminal

    private(set) var opening = false

    /// Opens an ssh terminal on the host and shows it in the existing terminal pane.
    func connect() async {
        guard let service, !opening, model.mayWrite() else { return }
        opening = true
        defer { opening = false }
        do {
            let id = try await service.openTerminal(host: hostID, rows: 24, cols: 80)
            await model.openTerminal?(id)
            model.watchRecording(terminal: id, host: hostID)
            shell.showToast("Terminal opened on \(host?.name ?? "the host")")
        } catch { shell.showToast(words(error), kind: .warn) }
    }

    // MARK: health

    var health: PageLoad<HostHealth> = .idle

    func loadHealth() async {
        if health.value == nil { health = .loading }
        health = await read { try await $0.health(host: hostID) }
    }

    // MARK: problems

    /// A failure that stops the whole page (a runner too old for ssh) is kept on the model, so every view of the host shows
    /// the one state card with its fix.
    func note(_ e: any Error) {
        guard let f = e as? LeylineFailure, HostProblem(f) != nil else { return }
        model.hostProblem[hostID] = f
    }

    var problem: HostProblem? { model.hostProblem[hostID].flatMap(HostProblem.init) }

    // MARK: commands

    var commands: PageLoad<[PresetCommand]> = .idle
    /// The latest run of each command on this host, by command id.
    private(set) var runs: [String: CommandRun] = [:]
    /// The command whose output the drawer under the cards shows.
    var shown: String?
    /// The card lit by the arrows (⏎ runs it).
    var lit: String?
    private(set) var saving = false
    private var polling: Set<String> = []

    /// The cards: the saved commands meant for this host, then the built-ins not saved yet.
    var items: [HostCommandList.Item] {
        guard let h = host else { return [] }
        return HostCommandList.items(saved: commands.value ?? [], host: h)
    }

    func loadCommands() async {
        if commands.value == nil { commands = .loading }
        commands = await read { try await $0.commands() }
    }

    /// One click. A built-in is saved first; a command marked "confirm" asks first, on the one confirm card, whose
    /// highlighted choice starts on Cancel.
    func tap(_ item: HostCommandList.Item) {
        guard model.mayWrite(), let h = host else { return }
        lit = item.id
        if item.builtIn {
            Task {
                guard let saved = await save(item.command) else { return }
                tap(HostCommandList.Item(command: saved, builtIn: false))
            }
            return
        }
        let c = item.command
        guard c.confirm else {
            Task { await run(c, confirmed: false) }
            return
        }
        let what = c.steps.count == 1 ? c.steps[0] : "\(c.steps.count) steps, in order, stopping at the first failure"
        shell.presentSheet(
            title: "Run “\(c.name)” on \(h.name)?",
            message: "\(what). The output is kept in History.",
            actions: [
                ShellSheetAction("Cancel"),
                ShellSheetAction("Run", primary: true) { [weak self] in Task { await self?.run(c, confirmed: true) } },
            ], symbol: "play.circle")
    }

    /// ⏎ runs the lit card; the arrows move the light in reading order.
    func runLit() -> Bool {
        guard let id = lit, let item = items.first(where: { $0.id == id }) else { return false }
        tap(item)
        return true
    }

    func moveLit(_ by: Int) {
        let all = items
        guard !all.isEmpty else { return }
        let at = all.firstIndex { $0.id == lit } ?? (by > 0 ? -1 : all.count)
        lit = all[min(all.count - 1, max(0, at + by))].id
    }

    /// Runs through the Core's gate; Touch ID only when the Core asks for it (`elevated` retries once it has it).
    func run(_ c: PresetCommand, confirmed: Bool) async {
        guard let service, let h = host else { return }
        runs[c.id] = CommandRun(id: "", commandName: c.name, state: .running, startedAt: Date())
        shown = c.id
        do {
            let id = try await model.host.elevated(
                "Run “\(c.name)” on \(h.name).", done: "started", keepsEdit: false
            ) { try await service.runCommand(c.id, host: hostID, confirmed: confirmed) }
            runs[c.id] = CommandRun(id: id, commandName: c.name, state: .running, startedAt: Date())
            await poll(c, run: id)
        } catch is AdminDeclined {
            runs[c.id] = nil
        } catch {
            runs[c.id] = nil
            note(error)
            shell.showToast(words(error), kind: .warn)
        }
    }

    /// Reads the run once a second until it is over (a run that waits for an approval stays "waiting" and is read less often).
    private func poll(_ c: PresetCommand, run id: String) async {
        guard let service, polling.insert(id).inserted else { return }
        defer { polling.remove(id) }
        let started = runs[c.id]?.startedAt
        for _ in 0..<600 {
            guard var r = try? await service.run(id, host: hostID, name: c.name) else { break }
            r.startedAt = started
            runs[c.id] = r
            if r.finished {
                await loadHistory()
                return
            }
            try? await Task.sleep(for: .seconds(r.state == .needsApproval ? 3 : 1))
            if Task.isCancelled { return }
        }
    }

    /// New Command's Save: one step for every host. A read-only command (safe for AI) may ask for Touch ID.
    func save(_ draft: CommandDraft) async -> Bool {
        guard draft.problem == nil else { return false }
        let c = PresetCommand(
            id: "", name: draft.name.trimmingCharacters(in: .whitespaces), description: "",
            steps: [draft.command.trimmingCharacters(in: .whitespaces)], scopeKind: nil, scopeValue: nil,
            readOnly: false, confirm: draft.confirm)
        guard let made = await save(c) else { return false }
        lit = made.id
        shell.showToast("\(made.name) saved")
        return true
    }

    private func save(_ c: PresetCommand) async -> PresetCommand? {
        guard let service, !saving, model.mayWrite() else { return nil }
        saving = true
        defer { saving = false }
        do {
            let made = try await model.host.elevated("Save the command \(c.name).", done: "saved", keepsEdit: true) {
                try await service.createCommand(
                    name: c.name, step: c.steps[0], readOnly: c.readOnly, confirm: c.confirm)
            }
            commands = .ready((commands.value ?? []) + [made])
            return made
        } catch is AdminDeclined {
            return nil
        } catch {
            shell.showToast(words(error), kind: .warn)
            return nil
        }
    }

    // MARK: files

    var path = "/"
    var entries: PageLoad<[RemoteFile]> = .idle
    var selected: RemoteFile?
    /// The text of the selected file, when it is small text the person may see.
    var preview: PageLoad<String> = .idle
    /// Files whose contents a person asked to see with Touch ID, for as long as this page is open.
    private var revealed: Set<String> = []
    var transfer: String?

    func loadFiles(_ p: String? = nil) async {
        if let p { path = p }
        selected = nil
        preview = .idle
        if entries.value == nil { entries = .loading }
        let at = path
        let r = await read { try await $0.files(host: hostID, path: at) }
        guard at == path else { return }
        // Folders first, then A to Z.
        entries =
            switch r {
            case .ready(let a):
                .ready(
                    a.sorted {
                        $0.isFolder != $1.isFolder
                            ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    })
            case .missing: .missing
            case .failed(let s): .failed(s)
            default: .idle
            }
    }

    func open(_ f: RemoteFile) { if f.isFolder { Task { await loadFiles(f.path) } } else { select(f) } }

    func select(_ f: RemoteFile) {
        selected = f
        preview = .idle
        guard !f.isFolder, f.kind == .file, !f.mayHoldSecrets || revealed.contains(f.path) else { return }
        Task { await loadPreview(f) }
    }

    func isLocked(_ f: RemoteFile) -> Bool { f.mayHoldSecrets && !revealed.contains(f.path) }

    /// "Show with Touch ID" on a file that may hold secrets.
    func reveal(_ f: RemoteFile) async {
        do {
            try await model.host.elevated(
                "Show \(f.name) from \(host?.name ?? "the host").", done: "shown", keepsEdit: false
            ) {}
        } catch { return }
        revealed.insert(f.path)
        await loadPreview(f)
    }

    private static let previewCap: Int64 = 256 << 10

    private func loadPreview(_ f: RemoteFile) async {
        guard let service else { return }
        guard (f.size ?? 0) <= Self.previewCap else {
            preview = .missing
            return
        }
        preview = .loading
        do {
            let d = try await service.download(host: hostID, path: f.path)
            guard selected == f else { return }
            // Text only: bytes that are not UTF-8 are a binary file, which is not drawn.
            preview = String(data: d, encoding: .utf8).map { .ready($0) } ?? .missing
        } catch { if selected == f { preview = .failed(words(error)) } }
    }

    // MARK: history and replay

    var history: PageLoad<[HostEvent]> = .idle
    var who: HostEvent.Who?
    private(set) var replaying: HostEvent?
    var recording: PageLoad<Recording> = .idle
    var position = 0.0
    var speed = 1.0
    private(set) var playing = false
    private var player: Task<Void, Never>?

    var shownHistory: [HostEvent] { HostTimeline.shown(history.value ?? [], who: who) }
    /// The history entry opened in the timeline.
    var opened: String?

    func loadHistory() async {
        if history.value == nil { history = .loading }
        history = await read { try await $0.history(host: hostID) }
    }

    func replay(_ e: HostEvent) async {
        guard let id = e.recording else { return }
        stop()
        replaying = e
        position = 0
        recording = .loading
        guard let service else { return }
        do {
            // A recording is terminal content: replaying it needs Touch ID.
            let r = try await model.host.elevated(
                "Replay this recording of \(host?.name ?? "the host").", done: "shown", keepsEdit: false
            ) { try await service.recording(id) }
            recording = .ready(r)
            play()
        } catch is AdminDeclined {
            recording = .idle
            replaying = nil
        } catch let e as LeylineFailure where e.isMissing {
            recording = .missing
        } catch { recording = .failed(words(error)) }
    }

    func play() {
        guard let r = recording.value, !playing else { return }
        if position >= r.length { position = 0 }
        playing = true
        player = Task { [weak self] in
            while let self, self.playing {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                self.position = min(r.length, self.position + 0.1 * self.speed)
                if self.position >= r.length { self.playing = false }
            }
        }
    }

    func stop() {
        playing = false
        player?.cancel()
        player = nil
    }

    func closePage() {
        stop()
        runnerWatch?.cancel()
    }

    // MARK: make it a runner

    enum RunnerInstallState: Equatable {
        case idle, starting
        /// The installer is running in the terminal; the invite ends at the date.
        case waiting(until: Date?)
        /// A runner paired: the device that claimed the invite.
        case paired(device: String)
        case expired
        /// The install on the host did not finish, and why.
        case failed(String)
    }

    private(set) var runnerState = RunnerInstallState.idle
    private var runnerWatch: Task<Void, Never>?

    /// One action: Touch ID, then the Core puts a one-time invite on the host and installs the runner there by itself over SSH
    /// (nothing to type: the system service with passwordless sudo, else a runner for that user), and waits for it to pair.
    func makeRunner() async {
        guard let service, let h = host, model.mayWrite() else { return }
        switch runnerState {
        case .starting, .waiting: return
        default: break
        }
        runnerState = .starting
        do {
            let install = try await model.host.elevated(
                "Install the Ainkrad runner on \(h.name).", done: "started", keepsEdit: false
            ) { try await service.makeRunner(host: h.id, rows: 24, cols: 80) }
            if let t = install.terminal { await model.openTerminal?(t) }  // an older Core still opens a terminal
            runnerState = .waiting(until: install.expiresAt)
            runnerWatch?.cancel()
            runnerWatch = Task { [weak self] in await self?.watchRunner(until: install.expiresAt) }
        } catch is AdminDeclined {
            runnerState = .idle
        } catch {
            runnerState = .idle
            shell.showToast(words(error), kind: .warn)
        }
    }

    /// Reads the host until the runner pairs or the invite (15 minutes, and a minute of grace) is over.
    private func watchRunner(until: Date?) async {
        let end = (until ?? Date().addingTimeInterval(900)).addingTimeInterval(60)
        while Date() < end, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            await model.reload()
            if let d = host?.runnerDevice {
                runnerState = .paired(device: d)
                return
            }
            if let i = host?.runnerInstall, i.state == "failed" {
                runnerState = .failed(i.reason ?? "The installer on the host failed.")
                return
            }
        }
        if !Task.isCancelled { runnerState = .expired }
    }

    /// The sheet before Make Runner: what it does, and that nothing is typed.
    func confirmRunner() {
        guard let h = host else { return }
        shell.presentSheet(
            title: "Make \(h.name) a runner?",
            message:
                "Ainkrad copies a one-time invite to the host and installs the runner there over SSH. Nothing to type. With passwordless sudo it installs the system service; without it, a runner for this user only (terminals; AI sessions need the system install). The invite ends in 15 minutes.",
            actions: [
                ShellSheetAction("Cancel"),
                ShellSheetAction("Make Runner", primary: true) { Task { await self.makeRunner() } },
            ], symbol: "server.rack")
    }

    // MARK: Mac-direct

    private(set) var direct: DirectLease?
    private(set) var directBusy = false

    /// Hands the Mac's own `ssh` the key for a few minutes, for this host only. Needs Touch ID (the key leaves the Core's
    /// sealed store for the Mac runner's agent).
    func startDirect() async {
        guard let service, let h = host, !directBusy, model.mayWrite() else { return }
        directBusy = true
        defer { directBusy = false }
        do {
            direct = try await model.host.elevated(
                "Let this Mac’s ssh use the key for \(h.name) for a few minutes.", done: "lent", keepsEdit: false
            ) { try await service.startDirect(host: h.id) }
        } catch is AdminDeclined {
        } catch { shell.showToast(words(error), kind: .warn) }
    }

    func stopDirect() async {
        guard let service, !directBusy else { return }
        directBusy = true
        defer { directBusy = false }
        do {
            try await service.stopDirect(host: hostID)
            direct = nil
        } catch { shell.showToast(words(error), kind: .warn) }
    }
}
