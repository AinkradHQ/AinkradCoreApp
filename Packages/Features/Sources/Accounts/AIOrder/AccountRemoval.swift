import CoreKit
import Foundation

/// Box for a value an `@Sendable` write op hands back.
private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T?
}

extension AccountsModel {
    /// How long the Undo toast may stay when the Core does not say (its window is 10 s).
    static let undoWindow: TimeInterval = 10

    /// Remove at once, no question: the Core keeps the account for a short window and the toast offers Undo. A Core below
    /// 0.10 has no such window, so there the confirmation dialog stays (`AIOrderView` picks).
    @discardableResult
    func removeWithUndo(_ a: AccountItem) async -> Bool {
        let index = orderIDs.firstIndex(of: a.id) ?? orderIDs.count
        let until = Box<Date>()
        let ok = await write(
            "delete-\(a.id)", reason: "Remove \(title(a)). You can undo it for a few seconds.", done: "", toast: false
        ) { until.value = try await $0.removeAccount(a.id) }
        guard ok else { return false }
        if detail == a.id { detail = nil }
        let deadline = until.value ?? now().addingTimeInterval(Self.undoWindow)
        removed = RemovedAccount(account: a, index: index, until: deadline)
        let name = title(a)
        host.shell.showToast(
            AccountNotes.removedWords(name, note: a.wipeNote), lifetime: max(1, deadline.timeIntervalSince(now()))
        ) { [weak self] in Task { @MainActor in await self?.undoRemoval(a.id) } }
        return true
    }

    /// Undo: ask the Core to restore it, read the order again and put the row back where it stood. Late is told, not tried.
    func undoRemoval(_ id: Int64) async {
        guard let r = removed, r.account.id == id else { return }
        guard r.canUndo(at: now()) else {
            removed = nil
            host.shell.showToast("Too late to undo. \(r.account.label) is gone.", kind: .error)
            return
        }
        let ok = await write(
            "restore-\(id)", reason: "Bring \(r.account.label) back.", done: "\(r.account.label) is back"
        ) { try await $0.restoreAccount(id) }
        guard ok else { return }
        removed = nil
        // The Core puts the seat back; the order is read again (`write` did), then the row goes to its old place.
        let ids = Self.placed(orderIDs, id: id, at: r.index)
        if ids != orderIDs { await reorder(ids, reason: "Put \(r.account.label) back where it was in the AI order.") }
    }

    /// `ids` with `id` at `index` (clamped); the others keep their order.
    nonisolated static func placed(_ ids: [Int64], id: Int64, at index: Int) -> [Int64] {
        var rest = ids.filter { $0 != id }
        rest.insert(id, at: min(max(0, index), rest.count))
        return rest
    }
}
