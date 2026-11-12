import Admin
import CoreUI
import Foundation
import Observation

/// What the Inbox holds on screen right now. Content lives only here, for the one viewing room, and `clear()` runs before
/// any room switch, seal, expired lease or Mac lock. Nothing in it is logged or saved.
@MainActor @Observable
public final class InboxState {
    public enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
        case refused(String)
    }
    public struct Done: Identifiable, Equatable {
        public let id = UUID()
        public let kind: String
        public let text: String
        public let tone: Tone
    }

    public internal(set) var phase: Phase = .idle
    public var list: InboxList = .waiting
    public internal(set) var data: RoomInbox?
    public internal(set) var captures: [Capture] = []
    public var selected: Set<String> = []
    /// Per-item failure sentence, shown on the card with "Try again".
    public internal(set) var errors: [String: String] = [:]
    /// Conflicts you asked to see again later: they stay and ring the bell.
    public internal(set) var later: Set<String> = []
    public internal(set) var done: [Done] = []
    /// Changes made here while offline.
    public internal(set) var queued = 0

    public init() {}

    public func count(_ l: InboxList) -> Int {
        switch l {
        case .waiting: data?.waiting.count ?? 0
        case .conflicts: data?.conflicts.count ?? 0
        case .blocked: data?.blocked.count ?? 0
        case .noRoom: captures.count
        }
    }

    public func clear() {
        phase = .idle
        data = nil
        captures = []
        selected = []
        errors = [:]
        later = []
        done = []
        queued = 0
    }
}

extension BrainModel {
    /// A room cloud agents could reach: Touch ID asks before anything goes into it.
    func widens(_ room: RoomSummary) -> Bool { room.mode.widens || room.provider == .approvedCloud }

    // MARK: loading

    /// Reads the viewing room's Inbox and the unclassified list. A sealed room reads nothing; the list of captures needs no room.
    public func loadInbox(quiet: Bool = false) async {
        guard let service else { return }
        let st = inboxState
        let id = viewingID
        if !quiet { st.phase = .loading }
        do {
            let caps = try await service.captures()
            guard viewingID == id else { return }
            st.captures = caps
            st.selected.formIntersection(Set(caps.map(\.id)))
            guard let r = viewing, r.lock == nil else {
                st.data = nil
                st.phase = .ready
                return
            }
            let d = try await service.inbox(room: r.id)
            guard viewingID == id else { return }
            st.data = d
            st.phase = .ready
        } catch {
            guard viewingID == id else { return }
            st.data = nil
            let sentence = BrainWords.failure(error)
            st.phase = (error as? BrainFailure)?.code == "refused" ? .refused(sentence) : .failed(sentence)
        }
    }

    public func retryInbox() { Task { await loadInbox() } }

    // MARK: running a change

    /// Runs one change. `ask` is the Touch ID reason, or nil when none is needed. A cancelled Touch ID leaves everything unchanged.
    @discardableResult
    func inboxRun(
        _ action: InboxAction, ask: String?, item: String, kind: String, text: String, tone: Tone = .done,
        toast: String
    ) async -> InboxOutcome {
        guard let service else { return .failed }
        let st = inboxState
        busy = "inbox"
        defer { busy = nil }
        do {
            if let ask {
                try await host.elevated(ask, done: "done", keepsEdit: false) { try await service.perform(action) }
            } else {
                try await service.perform(action)
            }
            let offline = overview?.flags.offlineQueued != nil
            if offline { st.queued += 1 }
            st.errors[item] = nil
            st.done.insert(.init(kind: kind, text: offline ? text + ", queued to sync" : text, tone: tone), at: 0)
            host.shell.showToast(toast)
            await reload()
            await loadInbox(quiet: true)
            return .done
        } catch is AdminDeclined {
            host.shell.showToast("Cancelled. Nothing changed.", kind: .info)
            return .cancelled
        } catch {
            st.errors[item] = BrainWords.failure(error)
            return .failed
        }
    }

    // MARK: waiting

    public func candidate(_ id: String) -> Candidate? { inboxState.data?.waiting.first { $0.id == id } }

    /// Approves a waiting memory. One that reads like an instruction needs `confirmed` first.
    @discardableResult
    public func approve(
        _ id: String, edit: CandidateEdit? = nil, options: ApproveOptions? = nil, confirmed: Bool = false
    ) async -> InboxOutcome {
        guard let c = candidate(id) else { return .failed }
        if c.flag != nil, !confirmed { return .needsConfirm }
        let offline = overview?.flags.offlineQueued != nil
        return await inboxRun(
            .approve(id: id, room: c.room, edit: edit, options: options), ask: nil, item: id, kind: "Approved",
            text: edit == nil ? "Approved: \(c.title)" : "Approved with your edit: \(edit?.title ?? c.title)",
            toast: offline ? "Approved. It waits to sync." : "Approved. AI sessions can use it now.")
    }

    @discardableResult
    public func reject(_ id: String) async -> InboxOutcome {
        guard let c = candidate(id) else { return .failed }
        return await inboxRun(
            .reject(id: id, room: c.room), ask: nil, item: id, kind: "Rejected", text: "Rejected: \(c.title)",
            tone: .fail, toast: "Rejected. The proposer is told it was not used.")
    }

    // MARK: conflicts

    /// The higher source this choice would override, or nil.
    public func overridden(_ c: Conflict, _ choice: ConflictChoice) -> Authority? {
        guard choice != .both else { return nil }
        let (win, lose) = choice == .first ? (c.a, c.b) : (c.b, c.a)
        return lose.authority.rank > win.authority.rank ? lose.authority : nil
    }

    @discardableResult
    public func keep(_ id: String, _ choice: ConflictChoice) async -> InboxOutcome {
        guard let c = inboxState.data?.conflicts.first(where: { $0.id == id }) else { return .failed }
        let ask = overridden(c, choice).map {
            "This overrides a higher source (\($0.label)) in \(room(c.room)?.name ?? "this room")."
        }
        let text =
            choice == .both
            ? "Kept both, each with its own scope. The resolution is saved as a record."
            : "Kept the \(choice == .first ? "first" : "second"): the other is replaced and stays in history."
        return await inboxRun(
            .keep(id: id, room: c.room, choice), ask: ask, item: id, kind: "Resolved", text: text,
            toast: "Conflict settled")
    }

    public func askLater(_ id: String) {
        inboxState.later.insert(id)
        host.shell.showToast("It stays here and in the bell.", kind: .info)
    }

    // MARK: blocked

    @discardableResult
    public func redact(_ id: String) async -> InboxOutcome {
        guard let b = inboxState.data?.blocked.first(where: { $0.id == id }) else { return .failed }
        let r = await inboxRun(
            .redact(id: id, room: b.room), ask: nil, item: id, kind: "Redacted",
            text: "Secret removed. The cleaned note now waits in Waiting.",
            toast: "Secret removed. The note waits for you.")
        if r == .done { inboxState.list = .waiting }
        return r
    }

    @discardableResult
    public func discard(_ id: String) async -> InboxOutcome {
        guard let b = inboxState.data?.blocked.first(where: { $0.id == id }) else { return .failed }
        return await inboxRun(
            .discard(id: id, room: b.room), ask: "Discard a blocked note. It is wiped from this Mac.", item: id,
            kind: "Discarded", text: "Discarded after review", tone: .fail, toast: "Discarded")
    }

    // MARK: no room yet

    public func capture(_ id: String) -> Capture? { inboxState.captures.first { $0.id == id } }

    /// Why moving memories between rooms waits, or nil.
    public var movePause: String? {
        health == .paused ? "Moving memories between rooms waits until you clear the check in Checks." : nil
    }

    @discardableResult
    public func assign(_ ids: [String], to roomID: String, mode: MoveMode) async -> InboxOutcome {
        guard let target = room(roomID), target.lock == nil, !ids.isEmpty else { return .failed }
        if let p = movePause {
            notice = "Paused. \(p)"
            return .failed
        }
        let n = ids.count
        let word = mode == .copy ? "Copied" : "Assigned"
        let ask =
            widens(target)
            ? "Put \(BrainWords.plural(n, "capture", "captures")) into \(target.name), which cloud AI sessions can reach."
            : nil
        let r = await inboxRun(
            .assign(ids: ids, room: roomID, mode: mode), ask: ask, item: ids[0], kind: word,
            text: mode == .copy
                ? "Copied to \(target.name); the original stays in the inbox"
                : "Moved to \(target.name), waiting for approval",
            toast: "\(word) to \(target.name)")
        if r == .done { inboxState.selected.subtract(ids) }
        return r
    }

    @discardableResult
    public func split(_ id: String, into roomIDs: [String]) async -> InboxOutcome {
        let targets = roomIDs.compactMap { room($0) }.filter { $0.lock == nil }
        guard targets.count == roomIDs.count, !targets.isEmpty else { return .failed }
        if let p = movePause {
            notice = "Paused. \(p)"
            return .failed
        }
        let ask = targets.contains(where: widens) ? "Split a capture into rooms that cloud AI sessions can reach." : nil
        return await inboxRun(
            .split(id: id, rooms: roomIDs), ask: ask, item: id, kind: "Split",
            text: "Split in two and assigned, both parts waiting for approval", toast: "Split and assigned")
    }

    @discardableResult
    public func markPrivate(_ ids: [String]) async -> InboxOutcome {
        let r = await inboxRun(
            .markPrivate(ids: ids),
            ask: "Mark \(BrainWords.plural(ids.count, "capture", "captures")) private. They are scrubbed and blocked.",
            item: ids.first ?? "", kind: "Marked private", text: "Scrubbed and blocked. It will not be searched.",
            tone: .fail, toast: "Marked private")
        if r == .done { inboxState.selected.subtract(ids) }
        return r
    }

    @discardableResult
    public func exclude(_ ids: [String]) async -> InboxOutcome {
        let r = await inboxRun(
            .exclude(ids: ids),
            ask: "Exclude \(BrainWords.plural(ids.count, "capture", "captures")). They never enter any room.",
            item: ids.first ?? "", kind: "Excluded", text: "Refused and wiped. It never enters any room.",
            tone: .fail, toast: "Excluded")
        if r == .done { inboxState.selected.subtract(ids) }
        return r
    }

    @discardableResult
    public func deleteCaptures(_ ids: [String]) async -> InboxOutcome {
        let r = await inboxRun(
            .delete(ids: ids),
            ask:
                "Delete \(BrainWords.plural(ids.count, "capture", "captures")) after review. The raw captures are wiped from this Mac.",
            item: ids.first ?? "", kind: "Deleted", text: "Deleted after review", tone: .fail, toast: "Deleted")
        if r == .done { inboxState.selected.subtract(ids) }
        return r
    }
}
