import Admin
import Foundation
import Observation

/// Room Settings' memory care and the Overview's room card: the retention count asked before retention is turned on, the
/// "Clean up memory…" run (check, apply, cancel, undo) and the card. It holds one room at a time; the room view's `.task`
/// calls `enter`, which also picks up a clean-up the Core is already running (a quit or a lock does not stop it).
@MainActor @Observable
public final class RoomCareModel {
    /// One run of "Clean up memory…", in the order a person sees it.
    public enum Cleanup: Equatable {
        case idle
        /// The dry run reads every source again and counts; nothing is written.
        case checking(RedistilRun?)
        /// The dry run's answer, waiting for Apply.
        case ready(RedistilRun)
        /// Apply is running (nil until the Core has answered Touch ID and the first status).
        case applying(RedistilRun?)
        case done(RedistilRun)
        /// The room has no sources to read again.
        case nothing
        case failed(String)
    }

    /// Retention the person picked and has not turned on yet, with the count the Core gave for it.
    public struct RetentionAsk: Equatable {
        public var days: Int
        public var preview: RetentionPreview?
        public var failed: String?
    }

    public enum CardState: Equatable {
        case loading
        /// This Core sends no card (or the room has none yet): the Overview shows nothing.
        case none
        case ready(RoomCard)
        case failed(String)
    }

    weak var brain: BrainModel?
    public internal(set) var roomID: String?
    public internal(set) var cleanup = Cleanup.idle
    /// A refusal that left the run as it was (a cancel that came too late), in words.
    public internal(set) var note: String?
    public internal(set) var retentionAsk: RetentionAsk?
    public internal(set) var card = CardState.loading
    @ObservationIgnored var pollEvery: Duration = .seconds(1)
    @ObservationIgnored private var runTask: Task<Void, Never>?

    init(brain: BrainModel) { self.brain = brain }

    var service: (any BrainService)? { brain?.service }
    var serves: Bool { service?.servesCare == true }

    public func clear() {
        runTask?.cancel()
        runTask = nil
        roomID = nil
        cleanup = .idle
        note = nil
        retentionAsk = nil
        card = .loading
    }

    /// The room on screen. A room change drops what the last one held, then looks for a run the Core has open.
    public func enter(_ room: String) async {
        focus(room)
        guard serves, let service, case .idle = cleanup else { return }
        do {
            if let r = try await service.redistilStatus(room: room), r.isOpen, roomID == room, case .idle = cleanup {
                cleanup = r.dryRun ? .checking(r) : .applying(r)
                follow(room, r)
            }
        } catch {}
    }

    /// Makes `room` the one this model holds, dropping what another room left.
    private func focus(_ room: String) {
        guard roomID != room else { return }
        clear()
        roomID = room
    }

    // MARK: Clean up memory…

    public var isBusy: Bool {
        switch cleanup {
        case .checking, .applying: true
        default: false
        }
    }

    /// The plain action: the dry run starts at once, with no sheet to fill in.
    public func check(_ room: String) {
        guard let service, !isBusy else { return }
        focus(room)
        note = nil
        cleanup = .checking(nil)
        runTask?.cancel()
        runTask = Task {
            do {
                let r = try await service.startRedistil(room: room, dryRun: true)
                guard roomID == room else { return }
                cleanup = .checking(r)
                await poll(room, r)
            } catch is CancellationError {} catch { fail(error, room) }
        }
    }

    /// Apply: Touch ID, then the real run. A declined Touch ID puts the dry run's answer back.
    public func apply(_ room: String) {
        guard case .ready(let plan) = cleanup, let service, let host = brain?.host else { return }
        note = nil
        cleanup = .applying(nil)
        runTask?.cancel()
        runTask = Task {
            do {
                let r = try await host.elevated(
                    "Clean up this room's memory.", done: "started", keepsEdit: false
                ) { try await service.startRedistil(room: room, dryRun: false) }
                guard roomID == room else { return }
                cleanup = .applying(r)
                await poll(room, r)
            } catch is AdminDeclined {
                cleanup = .ready(plan)
            } catch is CancellationError {} catch { fail(error, room) }
        }
    }

    /// Stops the open run; nothing is archived. A run already writing its result cannot be cancelled: the refusal says so.
    public func cancel(_ room: String) {
        guard let service, isBusy else { return }
        Task {
            do {
                _ = try await service.cancelRedistil(room: room)
                runTask?.cancel()
                guard roomID == room else { return }
                cleanup = .idle
                note = nil
            } catch is CancellationError {} catch { note = BrainWords.failure(error) }
        }
    }

    public func dismiss() {
        guard !isBusy else { return }
        cleanup = .idle
        note = nil
    }

    /// Undo of the result line: the same change-set Undo the Activity tab has, so it says what it kept in the same words.
    public func undo(_ change: String) { brain?.changes.undo(change) }

    /// What Undo did, once it has.
    public func undone(_ change: String) -> ChangeUndo? { brain?.changes.results[change] }

    /// "See changes" in Activity: its memory view, reloaded so the clean-up's change set is the first line.
    public func openActivity() {
        guard let brain else { return }
        brain.changes.reset()
        if brain.activity.views.contains(.memory) { brain.activity.view = .memory }
        brain.show(.activity)
    }

    private func follow(_ room: String, _ run: RedistilRun) {
        runTask?.cancel()
        runTask = Task { await poll(room, run) }
    }

    /// Asks again until the run is no longer open. Dropped when the room on screen changes or the run is cancelled.
    private func poll(_ room: String, _ first: RedistilRun) async {
        guard let service else { return }
        var run = first
        while run.isOpen {
            try? await Task.sleep(for: pollEvery)
            if Task.isCancelled || roomID != room { return }
            do {
                guard let r = try await service.redistilStatus(room: room), r.id == run.id else {
                    cleanup = .idle
                    return
                }
                run = r
                if run.isOpen { cleanup = run.dryRun ? .checking(run) : .applying(run) }
            } catch is CancellationError {
                return
            } catch {
                fail(error, room)
                return
            }
        }
        guard roomID == room else { return }
        switch run.state {
        case .done: cleanup = run.dryRun ? .ready(run) : .done(run)
        case .cancelled: cleanup = .idle
        default:
            cleanup = .failed(
                run.detail.isEmpty
                    ? "The clean-up did not finish. Start it again within 24 hours to pick up where it stopped."
                    : run.detail)
        }
    }

    private func fail(_ error: Error, _ room: String) {
        guard roomID == room else { return }
        if (error as? BrainFailure)?.code == "nothing_to_redistil" {
            cleanup = .nothing
        } else {
            cleanup = .failed(BrainWords.failure(error))
        }
    }

    // MARK: retention

    /// A pick of N days: the Core counts what it would compact first, and nothing changes until the person turns it on.
    public func askRetention(_ room: String, days: Int) {
        guard let service else { return }
        focus(room)
        retentionAsk = RetentionAsk(days: days)
        Task {
            do {
                let p = try await service.retentionPreview(room: room, days: days)
                guard roomID == room, retentionAsk?.days == days else { return }
                retentionAsk?.preview = p
            } catch is CancellationError {} catch {
                guard roomID == room, retentionAsk?.days == days else { return }
                retentionAsk?.failed = BrainWords.failure(error)
            }
        }
    }

    public func cancelRetention() { retentionAsk = nil }

    /// Turn On: Touch ID and the Core's step-up, in `BrainCandidates.change`. Only after the count has been shown.
    public func confirmRetention(_ room: String) async {
        guard let ask = retentionAsk, ask.preview != nil, let c = brain?.candidates else { return }
        let done = await c.change(
            room, PolicyChange(retentionDays: ask.days),
            reason: "Remove the text of sources older than \(ask.days) days in this room for good.")
        if done, roomID == room { retentionAsk = nil }
    }

    /// Back to Keep: compaction already done stays done, new sources are no longer touched.
    public func keepEverything(_ room: String) async {
        retentionAsk = nil
        _ = await brain?.candidates.change(
            room, PolicyChange(retentionDays: 0), reason: "Keep every source in this room again.")
    }

    // MARK: room card

    public func loadCard(_ room: String) async {
        guard serves, let service else {
            card = .none
            return
        }
        focus(room)
        if case .ready = card {} else { card = .loading }
        do {
            let c = try await service.roomCard(room: room)
            guard roomID == room else { return }
            card = c.map { .ready($0) } ?? .none
        } catch is CancellationError {} catch {
            guard roomID == room else { return }
            card = .failed(BrainWords.failure(error))
        }
    }
}

extension BrainCandidates {
    /// One Auto-save row. The whole list goes to the Core, so a type this screen has no row for is kept as it was.
    public func toggleSave(_ room: String, _ kind: CandidateKind) async {
        guard let p = policies[room] else { return }
        var types = p.savedTypes
        let on = types.insert(kind.wireType).inserted
        if !on { types.remove(kind.wireType) }
        await change(
            room, PolicyChange(types: types),
            reason: on
                ? "Save \(kind.plural.lowercased()) in this room without a review."
                : "Review \(kind.plural.lowercased()) in this room before they are saved.")
    }

    public func setDailyDistils(_ room: String, _ n: Int) async {
        guard let p = policies[room], p.dailyDistils != n else { return }
        await change(
            room, PolicyChange(dailyDistils: n), reason: "Change how many times a day this room distils by itself.")
    }
}
