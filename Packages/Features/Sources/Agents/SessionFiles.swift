import Foundation

/// One entry of a session's folder.
public struct FolderEntry: Equatable, Sendable, Identifiable {
    public var name: String
    public var dir: Bool
    public var size: Int64?
    public var id: String { name }
    public init(name: String, dir: Bool, size: Int64? = nil) {
        self.name = name
        self.dir = dir
        self.size = size
    }
}

/// One directory level of a session's folder (the Core lists a level at a time, capped).
public struct FolderListing: Equatable, Sendable {
    public var dir: String
    public var entries: [FolderEntry]
    public var truncated: Bool
    public init(dir: String, entries: [FolderEntry], truncated: Bool = false) {
        self.dir = dir
        self.entries = entries
        self.truncated = truncated
    }
}
