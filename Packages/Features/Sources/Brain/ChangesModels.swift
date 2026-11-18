import Foundation

// Memory change sets (B10-01): what the Core wrote to a room by itself, one set at a time, so a person can see it and Undo it.
// A set holds record text, so these shapes are for the person's screens only and never reach Activity's audit feed.

/// What made a change set. A purge keeps counts only: no rows to show, nothing to put back.
public enum MemoryChangeKind: String, Sendable, Hashable {
    case distil, checkpoint, ai, tidy, purge, archive
    public var label: String {
        switch self {
        case .distil: "Saved from your sessions"
        case .checkpoint: "Saved at a checkpoint"
        case .ai: "Proposed by AI"
        case .tidy: "Tidied"
        case .purge: "Removed for good"
        case .archive: "Archived"
        }
    }
    /// A purge deleted its rows, so it has nothing to expand and cannot be undone.
    public var hasRows: Bool { self != .purge }
}

/// One change set: the Core's own summary line ("Saved 5 · reinforced 3 · dropped 12"), when, and whether Undo already ran.
public struct MemoryChange: Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: MemoryChangeKind
    public let line: String
    public let at: String
    public let undone: Bool
    public let rows: Int
    public init(id: String, kind: MemoryChangeKind, line: String, at: String, undone: Bool = false, rows: Int = 0) {
        self.id = id
        self.kind = kind
        self.line = line
        self.at = at
        self.undone = undone
        self.rows = rows
    }
    public var canUndo: Bool { kind.hasRows && !undone }
}

public struct ChangesPage: Sendable, Equatable {
    public var changes: [MemoryChange]
    public var hasMore: Bool
    public init(changes: [MemoryChange] = [], hasMore: Bool = false) {
        self.changes = changes
        self.hasMore = hasMore
    }
}

/// A record as it was before or after a change.
public struct MemoryImage: Sendable, Hashable {
    public let type: String
    public let text: String
    public let tags: [String]
    /// Ids of the sources the record cites. The Core keeps ids, so that is what the person can be shown.
    public let sources: [String]
    public init(type: String, text: String, tags: [String] = [], sources: [String] = []) {
        self.type = type
        self.text = text
        self.tags = tags
        self.sources = sources
    }
}

/// One record a change set touched. No `before`: the change added it. No `after`: the change removed it.
public struct ChangeRow: Sendable, Hashable, Identifiable {
    public var id: Int { seq }
    public let seq: Int
    public let record: String
    public let before: MemoryImage?
    public let after: MemoryImage?
    public init(seq: Int, record: String, before: MemoryImage?, after: MemoryImage?) {
        self.seq = seq
        self.record = record
        self.before = before
        self.after = after
    }
    public var verb: String {
        switch (before, after) {
        case (nil, _): "Added"
        case (_, nil): "Removed"
        default: "Changed"
        }
    }
}

public struct ChangeRowsPage: Sendable, Equatable {
    public var rows: [ChangeRow]
    public var more: Bool
    public init(rows: [ChangeRow] = [], more: Bool = false) {
        self.rows = rows
        self.more = more
    }
}

/// What Undo did: records put back, and records left as they are because they changed since.
public struct ChangeUndo: Sendable, Equatable {
    public let restored: [String]
    public let skipped: [String]
    public let alreadyUndone: Bool
    public init(restored: [String], skipped: [String], alreadyUndone: Bool = false) {
        self.restored = restored
        self.skipped = skipped
        self.alreadyUndone = alreadyUndone
    }
}
