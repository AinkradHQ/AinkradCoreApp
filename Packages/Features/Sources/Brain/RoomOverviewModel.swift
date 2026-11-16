import Foundation
import Observation

/// The room Overview tab: one room's written overview, its instructions for AI sessions and the sources behind each rule.
/// It reads and writes only through `RoomOverviewService`, holds one room at a time, and is cleared with the room view.
@MainActor @Observable
public final class RoomOverviewModel {
    public enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    weak var brain: BrainModel?
    public internal(set) var phase: Phase = .idle
    public internal(set) var current: RoomOverview?
    public internal(set) var roomID: String?
    public internal(set) var busy = false
    /// The last failure of a write or an instructions change, in words, shown above the content.
    public internal(set) var notice: String?
    public internal(set) var editing = false
    public var draft = ""
    /// The rule whose "from N items" popover is open.
    public var openRule: String?
    @ObservationIgnored var pollEvery: Duration = .seconds(2)
    /// Bumped by every `clear()` from outside (a room switch, inspect, a screen lock), so the tab's load task runs
    /// again: a load whose answer arrives after a clear is dropped, and without this the tab stayed on its skeleton.
    public private(set) var epoch = 0

    init(brain: BrainModel) { self.brain = brain }

    var service: (any RoomOverviewService)? { brain?.service?.overviewService }

    public func clear() {
        reset()
        epoch += 1
    }

    private func reset() {
        phase = .idle
        current = nil
        roomID = nil
        busy = false
        notice = nil
        editing = false
        draft = ""
        openRule = nil
    }

    public func load(_ room: String, quiet: Bool = false) async {
        guard let service else { return }
        if roomID != room {
            reset()
            roomID = room
        }
        if !quiet, current == nil { phase = .loading }
        do {
            let o = try await service.roomOverview(room: room)
            guard roomID == room else { return }
            current = o
            phase = .ready
        } catch is CancellationError {
        } catch {
            guard roomID == room else { return }
            if current == nil { phase = .failed(BrainWords.failure(error)) } else { notice = BrainWords.failure(error) }
        }
    }

    /// Asks the Core to write (or rewrite) and shows the writing state at once; the Core's answer follows by polling.
    public func write(_ room: String) async {
        guard let service, !busy else { return }
        busy = true
        defer { busy = false }
        notice = nil
        openRule = nil
        editing = false
        current?.state = .writing
        current?.progress = nil
        do {
            try await service.writeOverview(room: room)
        } catch is CancellationError {
        } catch { notice = BrainWords.failure(error) }
        await load(room, quiet: true)
    }

    /// Re-reads while the Core writes, until it is done. Cancelled with the view.
    public func watch(_ room: String) async {
        while !Task.isCancelled, roomID == room, current?.state == .writing {
            try? await Task.sleep(for: pollEvery)
            if Task.isCancelled { return }
            await load(room, quiet: true)
        }
    }

    // MARK: instructions

    public func startEdit() {
        draft = current?.instructionsText ?? ""
        editing = true
    }

    public func cancelEdit() { editing = false }

    public var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy }

    /// Saving what you wrote approves it: you have read it.
    public func save(_ room: String) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave, await setInstructions(room, text: text, approved: true) else { return }
        editing = false
    }

    public func approve(_ room: String) async {
        guard await setInstructions(room, text: nil, approved: true) else { return }
        brain?.host.shell.showToast("Instructions approved. AI sessions in this room use them.") {
            Task { @MainActor in _ = await self.setInstructions(room, text: nil, approved: false) }
        }
    }

    private func setInstructions(_ room: String, text: String?, approved: Bool) async -> Bool {
        guard let service, !busy else { return false }
        busy = true
        defer { busy = false }
        notice = nil
        do {
            try await service.setInstructions(room: room, text: text, approved: approved)
        } catch is CancellationError {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
        await load(room, quiet: true)
        return true
    }
}
