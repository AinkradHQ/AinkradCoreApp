#if DEBUG
import Foundation

/// Debug only: invented change sets for the Activity tab's memory view. No real memory text.
extension SampleBrainService {
    public func changes(room: String, after: String?) async throws -> ChangesPage {
        if scenario.activityError { throw BrainFailure("Core did not answer.", code: "changes_unavailable") }
        if scenario.noActivity || scenario.empty { return ChangesPage() }
        let all = Self.changeSets.map { c in
            MemoryChange(
                id: c.id, kind: c.kind, line: c.line, at: c.at, undone: undoneChanges.contains(c.id), rows: c.rows)
        }
        return ChangesPage(changes: all)
    }

    public func changeRows(room: String, change: String, after: Int?) async throws -> ChangeRowsPage {
        ChangeRowsPage(rows: Self.changeRows[change] ?? [])
    }

    public func undoChange(room: String, change: String) async throws -> ChangeUndo {
        if undoneChanges.contains(change) { return ChangeUndo(restored: [], skipped: [], alreadyUndone: true) }
        undoneChanges.insert(change)
        let rows = Self.changeRows[change] ?? []
        // The last row stands in for a record the person edited since: Undo keeps it.
        let kept = change == "chg-3" ? rows.suffix(1).map(\.record) : []
        return ChangeUndo(restored: rows.map(\.record).filter { !kept.contains($0) }, skipped: kept)
    }

    private static let changeSets: [MemoryChange] = [
        MemoryChange(
            id: "chg-4", kind: .distil, line: "Saved 2 · reinforced 1 · dropped 41", at: "today, 09:12", rows: 3),
        MemoryChange(id: "chg-3", kind: .ai, line: "Saved 2 · replaced 1", at: "today, 08:40", rows: 3),
        MemoryChange(id: "chg-2", kind: .tidy, line: "Merged 4 · replaced 1", at: "yesterday, 17:05", rows: 2),
        MemoryChange(id: "chg-1", kind: .purge, line: "Removed 12 archived for good", at: "10 Nov, 03:17"),
    ]

    private static let changeRows: [String: [ChangeRow]] = [
        "chg-4": [
            ChangeRow(
                seq: 1, record: "rec-a1", before: nil,
                after: MemoryImage(type: "decision", text: "Sample: releases ship from the release branch.", sources: ["src-01"])),
            ChangeRow(
                seq: 2, record: "rec-a2", before: MemoryImage(type: "fact", text: "Sample: the build takes 4 minutes."),
                after: MemoryImage(type: "fact", text: "Sample: the build takes 4 minutes.", sources: ["src-02", "src-03"])),
            ChangeRow(
                seq: 3, record: "rec-a3", before: nil,
                after: MemoryImage(type: "preference", text: "Sample: short commit subjects.", sources: ["src-04"])),
        ],
        "chg-3": [
            ChangeRow(
                seq: 1, record: "rec-b1", before: nil,
                after: MemoryImage(
                    type: "fact", text: "Sample: the staging box is rebuilt every Monday.",
                    sources: ["src-11", "src-12"])),
            ChangeRow(
                seq: 2, record: "rec-b2", before: nil,
                after: MemoryImage(type: "rule", text: "Sample: never deploy on Friday.", sources: ["src-13"])),
            ChangeRow(
                seq: 3, record: "rec-b3", before: MemoryImage(type: "task", text: "Sample: renew the certificate."),
                after: MemoryImage(type: "task", text: "Sample: renew the certificate before 1 Dec.", sources: ["src-14"])),
        ],
        "chg-2": [
            ChangeRow(
                seq: 1, record: "rec-c1", before: MemoryImage(type: "fact", text: "Sample: the team uses two trackers."),
                after: nil),
            ChangeRow(
                seq: 2, record: "rec-c2", before: MemoryImage(type: "fact", text: "Sample: the team uses one tracker."),
                after: MemoryImage(type: "fact", text: "Sample: the team uses one tracker, Linear.")),
        ],
    ]
}
#endif
