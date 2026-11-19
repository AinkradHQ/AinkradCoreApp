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
        #endif
    }

    var host: HostItem? { model.hostItem(hostID) }
    private var service: (any LeylineService)? { model.service }
    private var shell: ShellModel { model.host.shell }

    private func words(_ e: any Error) -> String { model.words(e) }

    /// A read that can come back "not yet": the page shows the right words for it.
    private func read<T: Sendable>(_ op: (any LeylineService) async throws -> T) async -> PageLoad<T> {
        guard let service else { return .idle }
        do { return .ready(try await op(service)) } catch let e as LeylineFailure where e.isMissing {
            return .missing
        } catch { return .failed(words(error)) }
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

    // MARK: commands

    var commands: PageLoad<[PresetCommand]> = .idle
    /// The latest run of each command on this host, by command id.
    private(set) var runs: [String: CommandRun] = [:]
    private var polling: Set<String> = []

    /// The presets that are meant for this host.
    var presets: [PresetCommand] {
        guard let h = host else { return [] }
        return (commands.value ?? []).filter { $0.fits(h) }
    }

    func loadCommands() async {
        if commands.value == nil { commands = .loading }
        commands = await read { try await $0.commands() }
    }

    /// One click. A command marked "confirm" asks first, on the one confirm card; Return runs it only after the card's own
    /// highlighted choice, which starts on Cancel.
    func tap(_ c: PresetCommand) {
        guard model.mayWrite() else { return }
        guard c.confirm, let h = host else {
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

    func run(_ c: PresetCommand, confirmed: Bool) async {
        guard let service else { return }
        runs[c.id] = CommandRun(id: "", commandName: c.name, state: .running)
        do {
            let id = try await service.runCommand(c.id, host: hostID, confirmed: confirmed)
            runs[c.id] = CommandRun(id: id, commandName: c.name, state: .running)
            await poll(c, run: id)
        } catch {
            runs[c.id] = nil
            shell.showToast(words(error), kind: .warn)
        }
    }

    /// Reads the run once a second until it is over (a run that waits for an approval stays "waiting" and is read less often).
    private func poll(_ c: PresetCommand, run id: String) async {
        guard let service, polling.insert(id).inserted else { return }
        defer { polling.remove(id) }
        for _ in 0..<600 {
            guard let r = try? await service.run(id, host: hostID, name: c.name) else { break }
            runs[c.id] = r
            if r.finished {
                await loadHistory()
                return
            }
            try? await Task.sleep(for: .seconds(r.state == .needsApproval ? 3 : 1))
            if Task.isCancelled { return }
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
    private(set) var transfer: String?

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

    /// Where a drag out gets its bytes: a real file in a temporary folder, made when Finder asks.
    nonisolated static func provider(for f: RemoteFile, host: String, service: any LeylineService) -> NSItemProvider {
        let p = NSItemProvider()
        let name = RemotePath.safeName(f.name)
        p.suggestedName = name
        p.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) {
            done in
            nonisolated(unsafe) let done = done  // called once, from the one task below
            Task {
                do {
                    let d = try await service.download(host: host, path: f.path)
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
                        UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try d.write(to: url, options: .atomic)
                    done(url, true, nil)
                } catch { done(nil, false, error) }
            }
            return nil
        }
        return p
    }

    func dragProvider(_ f: RemoteFile) -> NSItemProvider {
        guard let service, f.kind == .file else { return NSItemProvider() }
        return Self.provider(for: f, host: hostID, service: service)
    }

    /// Saves the file with the system panel ("Download").
    func download(_ f: RemoteFile) async {
        guard let service else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = RemotePath.safeName(f.name)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transfer = "Downloading \(f.name)…"
        defer { transfer = nil }
        do {
            try await service.download(host: hostID, path: f.path).write(to: url, options: .atomic)
            shell.showToast("\(f.name) saved")
        } catch { shell.showToast(words(error), kind: .warn) }
    }

    /// "Upload…": the system panel, then the same path a drop takes.
    func chooseUpload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    /// Files dropped in or chosen: folders are skipped, and a name that is already there asks before it is replaced.
    func upload(_ urls: [URL]) {
        guard model.mayWrite() else { return }
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        if files.count < urls.count { shell.showToast("Folders are not uploaded here. Drop files.", kind: .warn) }
        guard !files.isEmpty else { return }
        let have = Set((entries.value ?? []).map(\.name))
        let clash = files.filter { have.contains(RemotePath.safeName($0.lastPathComponent)) }
        guard !clash.isEmpty else { return start(files) }
        shell.presentSheet(
            title: clash.count == 1 ? "Replace “\(clash[0].lastPathComponent)”?" : "Replace \(clash.count) files?",
            message: "They already exist in \(path) on \(host?.name ?? "the host"). The old versions are overwritten.",
            actions: [
                ShellSheetAction("Cancel"),
                ShellSheetAction("Replace", destructive: true) { [weak self] in self?.start(files) },
            ])
    }

    private func start(_ files: [URL]) {
        Task {
            guard let service else { return }
            for url in files {
                let name = RemotePath.safeName(url.lastPathComponent)
                transfer = "Uploading \(name)…"
                do {
                    let data = try await Task.detached { try Data(contentsOf: url) }.value
                    // Writing a file on a host needs Touch ID, like a terminal.
                    try await model.host.elevated(
                        "Write \(name) to \(host?.name ?? "the host").", done: "written", keepsEdit: false
                    ) { try await service.upload(host: hostID, path: RemotePath.join(path, name), data: data) }
                } catch is AdminDeclined {
                    transfer = nil
                    return
                } catch {
                    transfer = nil
                    shell.showToast(words(error), kind: .warn)
                    await loadFiles()
                    return
                }
            }
            transfer = nil
            shell.showToast(files.count == 1 ? "Uploaded" : "Uploaded \(files.count) files")
            await loadFiles()
        }
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

    var shownHistory: [HostEvent] {
        let all = history.value ?? []
        guard let who else { return all }
        return all.filter { $0.who == who }
    }

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
    }

    private(set) var runnerState = RunnerInstallState.idle
    private var runnerWatch: Task<Void, Never>?

    /// One action: Touch ID, then the Core puts a one-time invite on the host, opens a terminal with the installer typed in
    /// (the person types the sudo password there) and waits for the runner to pair.
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
            await model.openTerminal?(install.terminal)
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
        }
        if !Task.isCancelled { runnerState = .expired }
    }

    /// The sheet before Make Runner: what it does, and that the sudo password is typed in the terminal, not given to Ainkrad.
    func confirmRunner() {
        guard let h = host else { return }
        shell.presentSheet(
            title: "Make \(h.name) a runner?",
            message:
                "Ainkrad copies a one-time invite to the host and opens a terminal that installs the runner as root. You type the sudo password there; Ainkrad never sees it. The invite ends in 15 minutes.",
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
