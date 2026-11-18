import Foundation

/// Memory change sets on a real Core: the list, one set's rows, and Undo. Person-only routes that need the room open.
extension CoreBrainService {
    public var servesChanges: Bool { true }

    static let changePage = 50
    static let changeRowPage = 100

    public func changes(room: String, after: String?) async throws -> ChangesPage {
        let list = try await wrap { try await routes.changes(room: room, after: after, limit: Self.changePage) }
        return ChangesPage(changes: list.map(Self.memoryChange), hasMore: list.count >= Self.changePage)
    }

    static func memoryChange(_ w: ChangeWire) -> MemoryChange {
        MemoryChange(
            id: w.id, kind: MemoryChangeKind(rawValue: w.kind) ?? .distil, line: w.summary,
            at: SyncWords.date(w.at).map(Self.when) ?? "", undone: w.undoneAt != nil, rows: w.rows)
    }

    public func changeRows(room: String, change: String, after: Int?) async throws -> ChangeRowsPage {
        let d = try await wrap {
            try await routes.change(room: room, id: change, after: after, limit: Self.changeRowPage)
        }
        return ChangeRowsPage(
            rows: d.rows.map {
                ChangeRow(seq: $0.seq, record: $0.record, before: Self.image($0.before), after: Self.image($0.after))
            }, more: d.more)
    }

    static func image(_ w: ChangeImageWire?) -> MemoryImage? {
        w.map { MemoryImage(type: $0.type ?? "", text: $0.body ?? "", tags: $0.tags, sources: $0.sources) }
    }

    public func undoChange(room: String, change: String) async throws -> ChangeUndo {
        let u = try await wrap { try await routes.undo(room: room, id: change) }
        return ChangeUndo(restored: u.restored, skipped: u.skipped, alreadyUndone: u.alreadyUndone)
    }
}
