import Admin
import Foundation
import Observation

/// Which half of a room the Rooms page shows.
public enum RoomPaneMode: String, Sendable, Hashable { case items, settings }

/// A candidate being edited: the kind and text you are changing, held until you save or cancel.
public struct CandidateDraft: Sendable, Equatable {
    public let id: String
    public var kind: CandidateKind
    public var text: String
    var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Brain M3 state: the Inbox across rooms, each room's policy, and the runners' history collection. Candidate text lives
/// here only while the Brain is open on this Mac, and is cleared on detach and on a locked Mac.
@MainActor @Observable
public final class BrainCandidates {
    public enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    weak var brain: BrainModel?
    public internal(set) var phase: Phase = .idle
    public internal(set) var inbox = CandidateInbox()
    public var selectedID: String?
    public var kindFilter: CandidateKind?
    public var roomFilter: String?
    public internal(set) var draft: CandidateDraft?
    public internal(set) var busy = false
    public internal(set) var policies: [String: RoomPolicy] = [:]
    /// Each room's extra AI allows. A room is absent until the Core answers (a Core before access has no answer).
    public internal(set) var access: [String: RoomAccess] = [:]
    public var paneMode: RoomPaneMode = .items
    public internal(set) var runners: [RunnerHistory] = []
    /// The runner whose history collection the sheet is about to turn on.
    public var runnerSheet: RunnerHistory?
    /// The last failure in words, shown in the Inbox until it is dismissed.
    public internal(set) var notice: String?

    init(brain: BrainModel) { self.brain = brain }

    var service: (any BrainService)? { brain?.service }

    public func clear() {
        phase = .idle
        inbox = CandidateInbox()
        selectedID = nil
        draft = nil
        policies = [:]
        access = [:]
        runners = []
        runnerSheet = nil
        notice = nil
    }

    // MARK: Inbox

    public var items: [InboxCandidate] { inbox.items }
    public var visible: [InboxCandidate] {
        inbox.items.filter {
            (kindFilter == nil || $0.kind == kindFilter) && (roomFilter == nil || $0.room == roomFilter)
        }
    }
    public var selected: InboxCandidate? { items.first { $0.id == selectedID } ?? visible.first }
    /// Rooms that have something waiting, for the "All rooms" filter.
    public var rooms: [(id: String, name: String)] {
        var seen: Set<String> = []
        return items.compactMap { seen.insert($0.room).inserted ? ($0.room, $0.roomName) : nil }
    }

    public func load(quiet: Bool = false) async {
        guard let service, service.servesCandidates else { return }
        if !quiet { phase = .loading }
        do {
            inbox = try await service.candidates()
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
            phase = .ready
        } catch {
            phase = .failed(BrainWords.failure(error))
        }
    }

    public func select(_ id: String) {
        guard draft == nil || draft?.id == id else { return }
        selectedID = id
    }

    /// Accepts the candidate as it is.
    @discardableResult
    public func accept(_ id: String) async -> Bool {
        guard let c = items.first(where: { $0.id == id }) else { return false }
        if await settle(c, .accept) { brain?.host.shell.showToast("Accepted. Filed in \(c.roomName).") }
        return draft == nil && !items.contains { $0.id == id }
    }

    @discardableResult
    public func reject(_ id: String) async -> Bool {
        guard let c = items.first(where: { $0.id == id }) else { return false }
        if await settle(c, .reject) {
            brain?.host.shell.showToast("Rejected. It stays out of \(c.roomName).", kind: .info)
        }
        return !items.contains { $0.id == id }
    }

    // MARK: editing

    public func startEdit(_ id: String) {
        guard let c = items.first(where: { $0.id == id }) else { return }
        selectedID = id
        draft = CandidateDraft(id: id, kind: c.kind, text: c.text)
    }

    public func cancelEdit() { draft = nil }

    /// The form keeps the draft up to date so the list can say "Edited" while you type.
    func setDraft(kind: CandidateKind, text: String) {
        guard draft != nil else { return }
        draft?.kind = kind
        draft?.text = text
    }

    /// What the list shows beside a candidate you are editing.
    public func isEdited(_ c: InboxCandidate) -> Bool {
        guard let d = draft, d.id == c.id else { return c.edited }
        return d.text != c.text || d.kind != c.kind
    }

    /// Saves your change and accepts it. An empty text cannot be saved.
    @discardableResult
    public func saveEdit() async -> Bool {
        guard let d = draft, d.canSave, let c = items.first(where: { $0.id == d.id }) else { return false }
        let text = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard await settle(c, .edit(kind: d.kind, text: text, tags: c.tags)) else { return false }
        draft = nil
        brain?.host.shell.showToast("Saved and accepted. Filed in \(c.roomName).")
        return true
    }

    /// One decision. The candidate leaves the list only when the Core took it; the next one is selected.
    private func settle(_ c: InboxCandidate, _ d: CandidateDecision) async -> Bool {
        guard let service, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await service.decide(c.id, room: c.room, d)
            notice = nil
            let i = visible.firstIndex { $0.id == c.id } ?? 0
            inbox.items.removeAll { $0.id == c.id }
            if draft?.id == c.id { draft = nil }
            if selectedID == c.id { selectedID = visible.isEmpty ? nil : visible[min(i, visible.count - 1)].id }
            await brain?.reload()
            return true
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    public func dismissNotice() { notice = nil }

    // MARK: room policy

    public func policy(_ room: String) -> RoomPolicy? { policies[room] }

    public func loadPolicy(_ room: String) async {
        guard let service else { return }
        do {
            var p = try await service.policy(room: room)
            p.queued = max(p.queued, inbox.queued.first { $0.room == room }?.items ?? 0)
            policies[room] = p
        } catch { notice = BrainWords.failure(error) }
    }

    /// Changing what a room may send to a cloud provider, or what it files without a review, asks for Touch ID.
    @discardableResult
    public func change(_ room: String, _ change: PolicyChange, reason: String) async -> Bool {
        guard let service, let host = brain?.host else { return false }
        do {
            let p = try await host.elevated(reason, done: "changed", keepsEdit: false) {
                try await service.setPolicy(room: room, change)
            }
            policies[room] = p
            await load(quiet: true)
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    public func setModel(_ room: String, _ model: ModelPolicy) async {
        guard policies[room]?.model != model else { return }
        await change(
            room, PolicyChange(model: model),
            reason: model == .localOnly
                ? "Keep this room's text on your devices." : "Let this room send text to the approved cloud provider.")
    }

    public func setAutoAccept(_ room: String, _ on: Bool) async {
        guard let p = policies[room], p.autoAccept != on else { return }
        // Turning it on starts with Facts, the lowest risk; the person adds more after.
        await change(
            room, PolicyChange(autoAccept: on, kinds: on && p.kinds.isEmpty ? [.fact] : nil),
            reason: on
                ? "Accept candidates in this room without a review."
                : "Review every candidate in this room again.")
    }

    public func toggleKind(_ room: String, _ kind: CandidateKind) async {
        guard let p = policies[room], p.autoAccept else { return }
        var kinds = p.kinds
        if !kinds.insert(kind).inserted { kinds.remove(kind) }
        await change(room, PolicyChange(kinds: kinds), reason: "Change what this room accepts without a review.")
    }

    public func setMinSources(_ room: String, _ n: Int) async {
        guard let p = policies[room], p.minSources != n else { return }
        await change(room, PolicyChange(minSources: n), reason: "Change what this room accepts without a review.")
    }

    // MARK: runner history

    public func loadRunners() async {
        guard let service else { return }
        do { runners = try await service.runners() } catch { notice = BrainWords.failure(error) }
    }

    /// Off is one tap. On opens the sheet that says what is read, and every turn on asks for Touch ID.
    public func toggleRunner(_ id: String) async {
        guard let r = runners.first(where: { $0.id == id }), r.online else { return }
        if r.enabled {
            await apply(r, enabled: false)
        } else {
            runnerSheet = r
        }
    }

    public func closeRunnerSheet() { runnerSheet = nil }

    /// Turn On in the sheet: Touch ID, then the Core. A cancelled Touch ID leaves it off and the sheet open.
    @discardableResult
    public func turnOnRunner() async -> Bool {
        guard let s = runnerSheet, let service, let host = brain?.host else { return false }
        do {
            let saved = try await host.elevated(
                "Collect AI tool history on \(s.name).", done: "turned on", keepsEdit: false
            ) { try await service.setRunnerHistory(s.id, enabled: true) }
            if let i = runners.firstIndex(where: { $0.id == saved.id }) { runners[i] = saved }
            if saved.restarting {
                brain?.host.shell.showToast("\(saved.name) is restarting to share its history.", kind: .info)
            }
            runnerSheet = nil
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    private func apply(_ r: RunnerHistory, enabled: Bool) async {
        guard let service else { return }
        do {
            let saved = try await service.setRunnerHistory(r.id, enabled: enabled)
            if let i = runners.firstIndex(where: { $0.id == saved.id }) { runners[i] = saved }
        } catch { notice = BrainWords.failure(error) }
    }
}
