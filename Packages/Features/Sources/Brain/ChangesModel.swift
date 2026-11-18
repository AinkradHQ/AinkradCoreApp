import Foundation
import Observation

/// The Activity tab's memory view: the viewing room's change sets, one line each, with Undo and the rows behind "See
/// changes". Undo applies at once, with no confirmation (the Core leaves any record changed since alone); the
/// result says what was put back and what was kept.
@MainActor @Observable
public final class ChangesModel {
    public enum Phase: Equatable {
        case loading, ready
        case failed(String, code: String)
    }

    /// The rows of one expanded set, loaded on demand and paged.
    public struct Detail: Equatable {
        public var rows: [ChangeRow] = []
        public var more = false
        public var loading = true
        public var failed: String?
    }

    @ObservationIgnored weak var brain: BrainModel?
    @ObservationIgnored private var loadedRoom: String?

    public internal(set) var phase: Phase = .loading
    public private(set) var changes: [MemoryChange] = []
    public private(set) var hasMore = false
    public private(set) var expanded: Set<String> = []
    public private(set) var details: [String: Detail] = [:]
    public private(set) var undoing: Set<String> = []
    /// What Undo did, per set, so the line can say what was kept.
    public private(set) var results: [String: ChangeUndo] = [:]
    public private(set) var undoFailed: [String: String] = [:]

    init(brain: BrainModel) { self.brain = brain }

    var room: String? { brain?.viewingID }

    /// Called when the memory view appears or the viewing room changes.
    public func enter() {
        guard loadedRoom != room else { return }
        clear()
        loadedRoom = room
        Task { await load() }
    }

    func clear() {
        loadedRoom = nil
        changes = []
        hasMore = false
        expanded = []
        details = [:]
        results = [:]
        undoFailed = [:]
        undoing = []
        phase = .loading
    }

    func reset() { clear() }

    public func retry() { Task { await load() } }

    func load() async {
        guard let service = brain?.service, let room else { return }
        phase = .loading
        do {
            let page = try await service.changes(room: room, after: nil)
            guard room == self.room else { return }
            changes = page.changes
            hasMore = page.hasMore
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(BrainWords.failure(error), code: (error as? BrainFailure)?.code ?? "changes_unavailable")
        }
    }

    public func loadMore() {
        guard let service = brain?.service, let room, let last = changes.last?.id else { return }
        Task {
            do {
                let page = try await service.changes(room: room, after: last)
                guard room == self.room else { return }
                changes += page.changes.filter { c in !changes.contains { $0.id == c.id } }
                hasMore = page.hasMore
            } catch {
                brain?.host.shell.showToast(BrainWords.failure(error), kind: .warn)
            }
        }
    }

    // MARK: See changes

    public func toggle(_ id: String) {
        if expanded.remove(id) != nil { return }
        expanded.insert(id)
        if details[id] == nil { Task { await loadRows(id, after: nil) } }
    }

    public func moreRows(_ id: String) {
        guard let last = details[id]?.rows.last?.seq else { return }
        Task { await loadRows(id, after: last) }
    }

    func loadRows(_ id: String, after: Int?) async {
        guard let service = brain?.service, let room else { return }
        var d = details[id] ?? Detail()
        d.loading = true
        d.failed = nil
        details[id] = d
        do {
            let page = try await service.changeRows(room: room, change: id, after: after)
            guard room == self.room else { return }
            d.rows += page.rows
            d.more = page.more
        } catch {
            d.failed = BrainWords.failure(error)
        }
        d.loading = false
        details[id] = d
    }

    // MARK: Undo

    /// A row Undo left alone because the record changed since.
    public func kept(_ row: ChangeRow, in change: String) -> Bool {
        results[change]?.skipped.contains(row.record) == true
    }

    public func undo(_ id: String) {
        guard let service = brain?.service, let room, !undoing.contains(id) else { return }
        undoing.insert(id)
        undoFailed[id] = nil
        Task {
            defer { undoing.remove(id) }
            do {
                let done = try await service.undoChange(room: room, change: id)
                guard room == self.room else { return }
                results[id] = done
                if let i = changes.firstIndex(where: { $0.id == id }) {
                    let c = changes[i]
                    changes[i] = MemoryChange(
                        id: c.id, kind: c.kind, line: c.line, at: c.at, undone: true, rows: c.rows)
                }
                brain?.host.shell.showToast(Self.sentence(done), kind: done.skipped.isEmpty ? .ok : .info)
            } catch {
                undoFailed[id] = BrainWords.failure(error)
            }
        }
    }

    /// "Put back 4 memories. 2 changed since and were kept."
    static func sentence(_ u: ChangeUndo) -> String {
        if u.alreadyUndone { return "This was already undone. Nothing changed." }
        var s = "Put back \(BrainWords.plural(u.restored.count, "memory", "memories"))."
        if !u.skipped.isEmpty {
            s += " \(u.skipped.count) changed since and \(u.skipped.count == 1 ? "was" : "were") kept."
        }
        return s
    }
}
