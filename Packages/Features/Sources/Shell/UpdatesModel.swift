import Foundation
import Observation

/// State behind Settings, Updates: the Core's check and its own update (followed through the restart), every runner's
/// version and update, Update everything, and this app's own updater (Sparkle, set by the app target). The Core's status is
/// shared with the Core pop-up through `publish` / `receive` (`ShellModel.coreUpdate`).
@MainActor @Observable
public final class UpdatesModel {
    public var source: (any UpdatesSource)? {
        didSet { if source == nil { reset() } }
    }
    /// Runs an action behind Touch ID (the app sets it). Throws `CancellationError` when the person did not unlock.
    public var gate: (@MainActor (String, @escaping @MainActor () async throws -> Void) async throws -> Void)?
    /// The runner this app hosts (`MacRunnerModel.runnerID`): it comes inside the app, so it never gets an Update button.
    public var macRunnerID: String?
    /// Hands a newer Core status to the shell, so the Core pop-up shows the same run.
    public var publish: (@MainActor (CoreUpdateStatus) -> Void)?

    public private(set) var supported = false
    public private(set) var checking = false
    public private(set) var check: CoreUpdateCheck?
    public private(set) var runners: [UpdatableRunner] = []
    /// Plain words for the last thing that went wrong; nil when nothing did. Never a raw error.
    public private(set) var failure: String?
    /// The Core updater's status as last read.
    public private(set) var core = CoreUpdateStatus()
    /// The Core's update while it runs, as the four steps the card shows.
    public private(set) var run: CoreRun?
    /// Runners Update everything still has to ask, in order (the first is the one being asked or updated).
    public private(set) var queue: [String] = []
    /// Runners asked to update whose updater has not started, with when they were asked.
    public private(set) var asked: [String: Date] = [:]
    /// Runners whose updater runs, with when this tab first saw it.
    public private(set) var updatingSince: [String: Date] = [:]
    /// Update everything is running: the Core first, then the runners.
    public private(set) var chaining = false
    public private(set) var finished: UpdatesFinished?
    /// The Core asked for a pause (429 `Retry-After`): Update everything and Try again wait until then.
    public private(set) var retryAt: Date?
    /// Set the moment Update everything is pressed, so a second press (or ⌘U) does nothing.
    public private(set) var pressed = false

    // This Mac app (Sparkle, set by the app target).
    public var appVersion = ""
    /// A version Sparkle is downloading in the background.
    public var appDownloading: String?
    /// A downloaded version that installs on restart.
    public var appReady: String?
    public var checkApp: (@MainActor () -> Void)?
    public var installApp: (@MainActor () -> Void)?

    /// The clock and the wait between polls; tests and the demo replace them.
    public var now: @MainActor () -> Date = { Date() }
    public var pause: @MainActor (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    #if DEBUG
    /// Demo walks: draw the Reduce Motion fallback without changing the Mac's setting.
    public var debugReduceMotion = false
    #endif

    @ObservationIgnored private var following = false
    @ObservationIgnored private var chainStart: Date?

    public init() {}

    private func reset() {
        supported = false
        check = nil
        runners = []
        asked = [:]
        updatingSince = [:]
        queue = []
        run = nil
        chaining = false
        pressed = false
        failure = nil
    }

    // MARK: reading

    public func load() async {
        guard let source else { return }
        supported = await source.supported()
        await loadRunners()
        await readCore()
    }

    public func loadRunners() async {
        guard let source, supported else { return }
        do {
            runners = try await source.runners()
            let t = now()
            for r in runners where r.updating && (asked[r.id] != nil || queue.contains(r.id)) {
                updatingSince[r.id] = updatingSince[r.id] ?? t
                asked[r.id] = nil
            }
            if run == nil { failure = nil }
        } catch { note(error) }
    }

    public func checkNow() async {
        guard let source, supported, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            check = try await source.check()
            failure = nil
        } catch { note(error) }
        await loadRunners()
    }

    /// The Core's status, read once. During a run a failed read is the restart gap, not an error.
    private func readCore() async {
        guard let source, supported else { return }
        do {
            receive(try await source.coreStatus())
        } catch {
            if run != nil { dropped() } else if !UpdatesOutcome.isCancellation(error) { note(error) }
        }
    }

    /// A status from anywhere (this tab's poll, or the shell's): moves the run's steps.
    public func receive(_ s: CoreUpdateStatus) {
        if s != core {
            core = s
            publish?(s)
        }
        let t = now()
        if s.running, run == nil {
            run = CoreRun(from: s.current, to: s.to ?? s.available ?? target ?? "", at: t)
        }
        guard var r = run else { return }
        if r.gapSince != nil {
            r.gapSince = nil
            r.backAt = t
            r.move(to: .restart, at: t)
        }
        switch s.phase {
        case .idle, .snapshot: break
        case .install: r.move(to: .install, at: t)
        case .restart: r.move(to: .restart, at: t)
        case .health: r.move(to: .health, at: t)
        case .done:
            run = nil
            failure = nil
            return
        case .rolledBack, .failed:
            run = nil
            if !chaining { pressed = false }
            return
        }
        run = r
    }

    /// The Core stopped answering mid-run: it is restarting. Before the install nothing restarts, so it is only a blip.
    private func dropped() {
        guard var r = run, r.step.rawValue >= CoreRun.Step.install.rawValue else { return }
        if r.gapSince == nil {
            r.gapSince = now()
            r.move(to: .restart, at: now())
        }
        run = r
    }

    /// Polls the Core every second while its update runs, through the restart (1, 2, 3 s between tries while it is down),
    /// until it is done or went back. Three minutes at most; the Core carries on by itself after that.
    public func follow() async {
        guard !following, let source else { return }
        following = true
        defer { following = false }
        let deadline = now().addingTimeInterval(180)
        var misses = 0
        while run != nil, !Task.isCancelled, now() < deadline {
            do {
                receive(try await source.coreStatus())
                misses = 0
            } catch {
                misses += 1
                dropped()
            }
            if run == nil { break }
            await pause(Double(min(3, max(1, misses))))
        }
        if run != nil, now() >= deadline {
            run = nil
            failure = "The update is taking longer than usual. The Core finishes it by itself."
        }
    }

    // MARK: what the tab says

    /// The Core's version now.
    public var coreVersion: String? {
        !core.current.isEmpty ? core.current : check?.current
    }

    /// A newer Core version to take, from the updater or from Check now.
    public var target: String? {
        if let v = core.available, v != coreVersion { return v }
        if check?.status == .available, let v = check?.latest, v != coreVersion { return v }
        return nil
    }

    public var hostRunner: UpdatableRunner? { runners.first { $0.builtIn } }
    public var macRunner: UpdatableRunner? { runners.first { !$0.builtIn && $0.id == macRunnerID } }
    /// The Linux (and other) runners Update everything asks one by one.
    public var otherRunners: [UpdatableRunner] { runners.filter { !$0.builtIn && $0.id != macRunnerID } }
    /// The Runners section: the Core host first, then the others. This Mac's runner sits under This Mac app.
    public var listed: [UpdatableRunner] { (hostRunner.map { [$0] } ?? []) + otherRunners }

    public func state(_ r: UpdatableRunner) -> RunnerUpdateState {
        if r.builtIn { return .withCore }
        if r.id == macRunnerID { return .withApp }
        if r.updating || updatingSince[r.id] != nil { return .updating }
        if asked[r.id] != nil { return .asked }
        if queue.contains(r.id) { return .queued }
        if !r.online { return .offline }
        return r.behind ? .behind : .upToDate
    }

    /// The runners an Update everything would ask after the Core.
    public var behind: [UpdatableRunner] { otherRunners.filter { state($0) == .behind } }

    /// Whether Update everything has something to do.
    public var canUpdateEverything: Bool { target != nil || !behind.isEmpty }

    public func waitLeft(at t: Date) -> Int? {
        guard let r = retryAt, r > t else { return nil }
        return Int(r.timeIntervalSince(t).rounded(.up))
    }

    public var hero: UpdatesHero {
        if run != nil { return .updating }
        if core.phase == .rolledBack || core.phase == .failed, !chaining { return .wentBack }
        if chaining { return .following }
        if finished != nil { return .done }
        if target != nil { return .available }
        if otherRunners.contains(where: { [.asked, .updating].contains(state($0)) }) { return .runner }
        if appDownloading != nil || appReady != nil { return .macApp }
        return .upToDate
    }

    // MARK: acting

    /// Update everything (⌘U): the Core and the runner on its host first, then each other runner that is behind, one at
    /// a time, only after the Core's health check passed. This Mac app is not part of it (it has its own restart). The
    /// button locks the moment it is pressed; a 429 turns into the countdown, a declined Touch ID into nothing.
    public func updateEverything() async {
        guard let source, supported, !pressed, waitLeft(at: now()) == nil, canUpdateEverything else { return }
        pressed = true
        failure = nil
        finished = nil
        let started = now()
        chainStart = started
        if let to = target {
            guard await ask("Update the Core to \(to).", { try await source.startCore() }) else { return unlock() }
            chaining = true
            let t = now()
            run = CoreRun(from: coreVersion ?? "", to: to, at: t)
            var s = core
            s.phase = .snapshot
            s.to = to
            core = s
            publish?(s)
            await follow()
            await readCore()
            guard core.phase == .done || (core.phase == .idle && coreVersion == to) else {
                chaining = false
                return unlock()
            }
        }
        chaining = true
        await loadRunners()
        queue = behind.map(\.id)
        while let id = queue.first, !Task.isCancelled {
            await updateOne(id)
            queue.removeFirst()
        }
        chaining = false
        finished = UpdatesFinished(
            version: coreVersion ?? target ?? "", runners: listed.count,
            seconds: max(1, Int(now().timeIntervalSince(started).rounded())))
        unlock()
    }

    /// Asks one runner to update (⌥1…), behind Touch ID, and follows it until it is on the new version.
    public func update(runner id: String) async {
        guard asked[id] == nil, updatingSince[id] == nil, !queue.contains(id) else { return }
        await updateOne(id)
    }

    private func updateOne(_ id: String) async {
        guard let source else { return }
        let name = runners.first { $0.id == id }?.name ?? "this runner"
        asked[id] = now()
        guard await ask("Update \(name).", { try await source.updateRunner(id) }) else {
            asked[id] = nil
            return
        }
        // Asked → Updating → on the new version. Four minutes at most, then the runner finishes on its own.
        let deadline = now().addingTimeInterval(240)
        while !Task.isCancelled, now() < deadline {
            await pause(2)
            await loadRunners()
            guard let r = runners.first(where: { $0.id == id }) else { break }
            if r.updating {
                updatingSince[id] = updatingSince[id] ?? now()
                asked[id] = nil
            } else if !r.behind, updatingSince[id] != nil || asked[id].map({ now().timeIntervalSince($0) > 4 }) == true
            {
                break
            }
        }
        asked[id] = nil
        updatingSince[id] = nil
    }

    /// Runs one danger request behind the gate. False when it did not go through; the reason is already shown.
    private func ask(_ reason: String, _ op: @escaping @MainActor () async throws -> Void) async -> Bool {
        do {
            if let gate { try await gate(reason, op) } else { try await op() }
            retryAt = nil
            return true
        } catch {
            note(error)
            return false
        }
    }

    private func note(_ error: any Error) {
        switch UpdatesOutcome.of(error) {
        case .silent: break
        case .wait(let s): retryAt = now().addingTimeInterval(s)
        case .words(let w): failure = w
        }
    }

    private func unlock() {
        pressed = false
        chainStart = nil
    }

    /// Keeps the tab fresh while it shows: follows a Core update that started anywhere (the pop-up, the night run), runners
    /// every few seconds while one updates, else now and then.
    public func watch() async {
        await load()
        while !Task.isCancelled {
            if run != nil { await follow() }
            let busy = !asked.isEmpty || !updatingSince.isEmpty || runners.contains { $0.updating }
            await pause(busy ? 3 : 30)
            guard !Task.isCancelled else { return }
            await loadRunners()
            await readCore()
        }
    }

    /// The line beside Check now. `lastChecked` is the Core's record of the last check, for before one ran here.
    public func checkWords(lastChecked: Date?) -> String {
        guard supported else { return "This Core is too old to check for updates." }
        if checking { return "Checking…" }
        guard let c = check else {
            return lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet"
        }
        switch c.status {
        case .upToDate, .available: return "Checked \(c.at.formatted(.relative(presentation: .named)))"
        case .feedUnavailable:
            return c.reason.map { "Checked. \($0)" } ?? "Checked. No release feed is set up on this Core yet."
        }
    }

    #if DEBUG
    /// Tests: the Core stopped answering.
    func debugDrop() { dropped() }

    /// Demo scenes: made-up runners, a Core status and a run, no Core reached.
    public func debugSet(
        check: CoreUpdateCheck?, runners: [UpdatableRunner], core: CoreUpdateStatus = CoreUpdateStatus(),
        run: CoreRun? = nil, queue: [String] = [], asked: [String: Date] = [:], updating: [String: Date] = [:],
        finished: UpdatesFinished? = nil, retryAt: Date? = nil, chaining: Bool = false
    ) {
        supported = true
        self.check = check
        self.runners = runners
        self.core = core
        self.run = run
        self.queue = queue
        self.asked = asked
        updatingSince = updating
        self.finished = finished
        self.retryAt = retryAt
        self.chaining = chaining
        pressed = run != nil || chaining
        failure = nil
    }
    #endif
}
