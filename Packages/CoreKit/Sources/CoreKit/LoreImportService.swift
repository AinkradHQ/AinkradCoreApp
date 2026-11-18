import Foundation

/// One import run on the Core (`/modules/lore/v1/imports`, AinkradCore R4-01): Markdown files staged, reviewed, committed as
/// notes, and undoable. `flags` and `results` count items; their keys are camelCase after decoding (`tooLarge`).
public struct LoreImportRun: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    /// `mirror` (the project's repo copy in the Core) or `upload`.
    public var source: String
    public var project: String?
    public var repo: String?
    /// `staging`, `review`, `committing`, `committed`, `undoing`, `undone` or `abandoned`.
    public var state: String
    public var items: Int
    /// Items a commit would act on.
    public var include: Int
    /// Entries refused as unsafe, and entries ignored as unwanted: counted, never kept.
    public var refused: Int
    public var ignored: Int
    /// Why the run could not be read: a fixed sentence from the Core.
    public var error: String?
    /// Items by flag: `duplicate`, `changed`, `conflict`, `tooLarge`, `skipped`.
    public var flags: [String: Int]
    /// Items by what commit did: `created`, `updated`, `conflict`, `unchanged`, `skipped`.
    public var results: [String: Int]
    /// Items undo put back, and ones it left because the note changed after the import.
    public var undone: Int
    public var kept: Int
    public var createdAt: String
    public var committedAt: String?

    public init(
        id: String, source: String = "upload", project: String? = nil, repo: String? = nil, state: String = "review",
        items: Int = 0, include: Int = 0, refused: Int = 0, ignored: Int = 0, error: String? = nil,
        flags: [String: Int] = [:], results: [String: Int] = [:], undone: Int = 0, kept: Int = 0,
        createdAt: String = "", committedAt: String? = nil
    ) {
        self.id = id
        self.source = source
        self.project = project
        self.repo = repo
        self.state = state
        self.items = items
        self.include = include
        self.refused = refused
        self.ignored = ignored
        self.error = error
        self.flags = flags
        self.results = results
        self.undone = undone
        self.kept = kept
        self.createdAt = createdAt
        self.committedAt = committedAt
    }

    /// Items with no flag: notes this run would make.
    public var fresh: Int { max(items - flags.values.reduce(0, +), 0) }
    /// Items commit has dealt with so far (for a progress bar).
    public var handled: Int { results.values.reduce(0, +) }
}

/// One staged item, without its text. `flag`: `duplicate` (same text as the note it made), `changed` (the note it made is
/// unedited, so it would be updated), `conflict` (that note was edited here, so it is kept), `too_large` or `skipped`.
public struct LoreImportItem: Equatable, Sendable, Identifiable, Decodable {
    public var seq: Int
    public var path: String
    public var title: String
    public var tags: [String]
    public var project: String?
    public var flag: String?
    /// `include` or `skip`.
    public var mark: String
    public var matchNote: String?
    public var result: String?
    public var id: Int { seq }

    public init(
        seq: Int, path: String, title: String = "", tags: [String] = [], project: String? = nil, flag: String? = nil,
        mark: String = "include", matchNote: String? = nil, result: String? = nil
    ) {
        self.seq = seq
        self.path = path
        self.title = title
        self.tags = tags
        self.project = project
        self.flag = flag
        self.mark = mark
        self.matchNote = matchNote
        self.result = result
    }

    /// A commit never acts on these, whatever the mark says.
    public var locked: Bool { flag == "too_large" || flag == "skipped" }
}

/// A Markdown file read on this Mac, sent as text under its path inside the folder or zip.
public struct LoreImportFile: Equatable, Sendable, Encodable {
    public var path: String
    public var text: String
    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

/// The import routes. A Core or a test double without them answers "not implemented".
public protocol LoreImportService: Sendable {
    /// The runs, newest first (at most 50).
    func importRuns() async throws -> [LoreImportRun]
    func importRun(_ id: String) async throws -> LoreImportRun
    /// `repo`: reads the project's repo copy now (needs a project). Otherwise opens an upload run; `project` nil = personal.
    func startImport(repo: Bool, project: String?) async throws -> LoreImportRun
    /// At most 200 files and about 1 MiB a call.
    func addImportFiles(_ run: String, _ files: [LoreImportFile]) async throws -> LoreImportRun
    func addImportZip(_ run: String, _ zip: Data) async throws -> LoreImportRun
    /// Staging is over: items are flagged and the run is in review.
    func finishImport(_ run: String) async throws -> LoreImportRun
    func importItems(_ run: String, after: Int, limit: Int) async throws -> [LoreImportItem]
    /// `seqs` empty = every item.
    func markImportItems(_ run: String, seqs: [Int], include: Bool) async throws -> LoreImportRun
    /// The project new notes go to (nil = personal), for `seqs` (empty = every item).
    func moveImportItems(_ run: String, seqs: [Int], project: String?) async throws -> LoreImportRun
    /// Calling it again on a run that is committing resumes it.
    func commitImport(_ run: String) async throws -> LoreImportRun
    /// Calling it again on a run that is undoing resumes it.
    func undoImport(_ run: String) async throws -> LoreImportRun
    func abandonImport(_ run: String) async throws -> LoreImportRun
    /// An upload-like run whose Markdown the Mac made from Apple Notes (R4-03); project nil = personal.
    func startAppleNotesImport(project: String?) async throws -> LoreImportRun
    /// Stores one attachment (png, jpeg, gif, webp, heic or pdf, at most 10 MB) and returns its sha256, for `lore-attachment:<sha>`.
    func uploadAttachment(_ data: Data) async throws -> String
}

extension LoreImportService {
    public func startAppleNotesImport(project: String?) async throws -> LoreImportRun {
        throw CoreError.protocolViolation("This Core cannot import Apple Notes.")
    }
    public func uploadAttachment(_ data: Data) async throws -> String {
        throw CoreError.protocolViolation("This Core cannot store attachments.")
    }
}

extension LiveLoreService: LoreImportService {
    public func importRuns() async throws -> [LoreImportRun] {
        try await call("GET", "/imports", as: [LoreImportRun].self)
    }

    public func importRun(_ id: String) async throws -> LoreImportRun {
        try await call("GET", "/imports/\(Self.seg(id))", as: LoreImportRun.self)
    }

    public func startImport(repo: Bool, project: String?) async throws -> LoreImportRun {
        struct Body: Encodable {
            let source: String
            let project: String?
        }
        return try await call(
            "POST", "/imports", Body(source: repo ? "mirror" : "upload", project: project), as: LoreImportRun.self)
    }

    public func startAppleNotesImport(project: String?) async throws -> LoreImportRun {
        struct Body: Encodable {
            let source: String
            let project: String?
        }
        return try await call("POST", "/imports", Body(source: "apple_notes", project: project), as: LoreImportRun.self)
    }

    public func uploadAttachment(_ data: Data) async throws -> String {
        struct Stored: Decodable { let sha256: String }
        let out = try await send("POST", Self.base + "/attachments", data)
        do { return try JSONDecoder().decode(Stored.self, from: out).sha256 } catch {
            throw CoreError.protocolViolation("The Core answered something this app does not know.")
        }
    }

    public func addImportFiles(_ run: String, _ files: [LoreImportFile]) async throws -> LoreImportRun {
        struct Body: Encodable { let items: [LoreImportFile] }
        return try await call(
            "POST", "/imports/\(Self.seg(run))/items", Body(items: files), as: LoreImportRun.self)
    }

    public func addImportZip(_ run: String, _ zip: Data) async throws -> LoreImportRun {
        let data = try await send("POST", Self.base + "/imports/\(Self.seg(run))/zip", zip)
        return try Self.decodeRun(data)
    }

    public func finishImport(_ run: String) async throws -> LoreImportRun {
        try await call("POST", "/imports/\(Self.seg(run))/finish", as: LoreImportRun.self)
    }

    public func importItems(_ run: String, after: Int, limit: Int) async throws -> [LoreImportItem] {
        try await call(
            "GET", "/imports/\(Self.seg(run))/items?after=\(after)&limit=\(limit)", as: [LoreImportItem].self)
    }

    public func markImportItems(_ run: String, seqs: [Int], include: Bool) async throws -> LoreImportRun {
        struct Body: Encodable {
            let seqs: [Int]
            let mark: String
        }
        return try await call(
            "PATCH", "/imports/\(Self.seg(run))/items", Body(seqs: seqs, mark: include ? "include" : "skip"),
            as: LoreImportRun.self)
    }

    public func moveImportItems(_ run: String, seqs: [Int], project: String?) async throws -> LoreImportRun {
        struct Body: Encodable {
            let seqs: [Int]
            let project: String?
            // `null` means personal, so the key is always sent.
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(seqs, forKey: .seqs)
                try c.encode(project, forKey: .project)
            }
            enum Keys: String, CodingKey { case seqs, project }
        }
        return try await call(
            "PATCH", "/imports/\(Self.seg(run))/items", Body(seqs: seqs, project: project), as: LoreImportRun.self)
    }

    public func commitImport(_ run: String) async throws -> LoreImportRun {
        try await call("POST", "/imports/\(Self.seg(run))/commit", as: LoreImportRun.self)
    }

    public func undoImport(_ run: String) async throws -> LoreImportRun {
        try await call("POST", "/imports/\(Self.seg(run))/undo", as: LoreImportRun.self)
    }

    public func abandonImport(_ run: String) async throws -> LoreImportRun {
        try await call("POST", "/imports/\(Self.seg(run))/abandon", as: LoreImportRun.self)
    }

    static func decodeRun(_ data: Data) throws -> LoreImportRun {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(LoreImportRun.self, from: data) } catch {
            throw CoreError.protocolViolation("The Core answered something this app does not know.")
        }
    }
}
