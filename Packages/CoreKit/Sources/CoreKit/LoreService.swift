import AinkradClient
import Foundation

/// One Lore note as the Core holds it (`/modules/lore/v1`, AinkradCore R1-01 + R1-02). `text` is the Markdown document.
public struct LoreNote: Equatable, Sendable {
    public var id: String
    /// `note` or `daily`.
    public var kind: String
    /// A daily note's local date, `YYYY-MM-DD`.
    public var day: String?
    /// The project id as text; nil = personal.
    public var project: String?
    public var title: String
    public var rev: Int
    public var text: String
    public var trashed: Bool

    public init(
        id: String, kind: String = "note", day: String? = nil, project: String? = nil, title: String = "", rev: Int = 1,
        text: String = "", trashed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.day = day
        self.project = project
        self.title = title
        self.rev = rev
        self.text = text
        self.trashed = trashed
    }
}

extension LoreNote: Identifiable {}

/// What a save did (T2): `saved`, `merged` (both sides kept, `note.text` is the merge), `conflict` or `base_lost`
/// (the client's lines won, the old head is kept as `version`).
public struct LoreSaveResult: Equatable, Sendable {
    public var note: LoreNote
    public var outcome: String
    public var version: String?
    public init(note: LoreNote, outcome: String, version: String? = nil) {
        self.note = note
        self.outcome = outcome
        self.version = version
    }
    /// The Core kept text the head no longer has, as a version.
    public var keptVersion: Bool { outcome == "conflict" || outcome == "base_lost" }
}

/// A matched word inside a snippet: UTF-8 byte offsets into `LoreSnippet.text` (the Core counts bytes).
public struct LoreSpan: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// A stretch of a note on one line, with the matched words. Note text: untrusted, shown as plain text only.
public struct LoreSnippet: Equatable, Sendable {
    public var text: String
    public var matches: [LoreSpan]
    public init(text: String, matches: [LoreSpan] = []) {
        self.text = text
        self.matches = matches
    }
}

/// One search hit (R2-02): the note without its text, which ranking found it, the best section's heading.
public struct LoreHit: Equatable, Sendable {
    public var note: LoreNote
    /// `text`, `meaning` or `both`.
    public var via: String
    public var heading: String?
    public var snippet: LoreSnippet
    public init(note: LoreNote, via: String = "text", heading: String? = nil, snippet: LoreSnippet) {
        self.note = note
        self.via = via
        self.heading = heading
        self.snippet = snippet
    }
}

public struct LoreSearchResult: Equatable, Sendable {
    public var hits: [LoreHit]
    /// false = the Core's model is absent or still loading: these are word matches only.
    public var semantic: Bool
    public init(hits: [LoreHit], semantic: Bool) {
        self.hits = hits
        self.semantic = semantic
    }
}

/// What `GET /search` and `GET /notes` filter on. `tag` filters a search only (the list route has no tag filter).
public struct LoreFilter: Equatable, Sendable {
    /// `active` or `trashed`.
    public var state: String
    /// `note`, `daily` or nil for both.
    public var kind: String?
    /// A project id as text; nil = every note.
    public var project: String?
    public var tag: String?
    public init(state: String = "active", kind: String? = nil, project: String? = nil, tag: String? = nil) {
        self.state = state
        self.kind = kind
        self.project = project
        self.tag = tag
    }
}

/// A note that links to the open one (`GET /notes/{id}/backlinks`). `context` is note text: outside data, shown as plain text.
public struct LoreBacklink: Equatable, Sendable, Identifiable, Decodable {
    /// The linking note's id.
    public var note: String
    public var title: String
    public var heading: String
    public var context: String
    public var project: String?
    public var id: String { note + "#" + heading + "#" + context }
    public init(note: String, title: String, heading: String = "", context: String = "", project: String? = nil) {
        self.note = note
        self.title = title
        self.heading = heading
        self.context = context
        self.project = project
    }
}

/// One saved text of a note (`GET /notes/{id}/versions`, no text). `kind`: `auto`, `named` or `conflict`.
public struct LoreVersion: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var kind: String
    public var name: String?
    public var rev: Int
    /// `person:d_…`, `session:as_…` or `system`.
    public var origin: String
    /// ISO 8601 text as the Core wrote it.
    public var createdAt: String
    public init(
        id: String, kind: String = "auto", name: String? = nil, rev: Int = 1, origin: String = "system",
        createdAt: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rev = rev
        self.origin = origin
        self.createdAt = createdAt
    }
}

/// A tag of a live note and how many notes carry it (`GET /tags`, minor 95).
public struct LoreTagCount: Equatable, Sendable, Decodable, Identifiable {
    public var tag: String
    public var count: Int
    public var id: String { tag }
    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

/// A note imported from a file an AI session wrote (`GET /session-docs`, minor 95, D-28). Edits to the note are
/// written back to `path` in the session's folder. `sessionTitle` is the session's first prompt line.
public struct LoreSessionDoc: Equatable, Sendable, Decodable, Identifiable {
    public var note: String
    public var session: String
    public var path: String
    public var title: String
    public var sessionTitle: String?
    public var project: String?
    public var updatedAt: String
    public var id: String { note }
    public init(
        note: String, session: String, path: String, title: String = "", sessionTitle: String? = nil,
        project: String? = nil, updatedAt: String = ""
    ) {
        self.note = note
        self.session = session
        self.path = path
        self.title = title
        self.sessionTitle = sessionTitle
        self.project = project
        self.updatedAt = updatedAt
    }
    /// The file's name without its folders.
    public var fileName: String { path.split(separator: "/").last.map(String.init) ?? path }
}

/// What the Lore space asks of the Core. Errors are `CoreError` (`http(404/501)` = no Lore module on this Core).
public protocol LoreService: Sendable {
    /// The daily note of `day` (`YYYY-MM-DD`), created empty on first use.
    func today(_ day: String) async throws -> LoreNote
    /// The daily note of `day` when one exists (never creates it).
    func daily(_ day: String) async throws -> LoreNote?
    func note(_ id: String) async throws -> LoreNote
    func create(text: String, project: String?) async throws -> LoreNote
    func save(_ id: String, baseRev: Int, text: String) async throws -> LoreSaveResult
    /// Project ids (as text) and names, for the project chip.
    func projectNames() async throws -> [String: String]
    /// Hybrid search, best first (the Core needs at least one word). `GET /search`.
    func search(_ query: String, filter: LoreFilter, limit: Int) async throws -> LoreSearchResult
    /// Notes without their text, newest change first (at most 500). `GET /notes`.
    func list(filter: LoreFilter) async throws -> [LoreNote]
    /// Takes a note out of the trash. `PATCH /notes/{id}`.
    func restore(_ id: String) async throws -> LoreNote
    /// The R1-06 zip of every note, or of one project's. `GET /export`.
    func export(project: String?) async throws -> Data
    /// The live notes linking to this one, newest first (R1-04).
    func backlinks(_ id: String) async throws -> [LoreBacklink]
    /// The note's versions, newest first, without text.
    func versions(_ id: String) async throws -> [LoreVersion]
    /// One version's text.
    func versionText(_ id: String, version: String) async throws -> String
    /// Restore = a normal save at the head; `version` of the result is an auto version of the replaced text, so
    /// restoring that one undoes this.
    func restore(_ id: String, version: String) async throws -> LoreSaveResult
    /// Moves a note to a project (nil = personal).
    func move(_ id: String, project: String?) async throws -> LoreNote
    /// Puts a note in the trash (30 days, restorable). `PATCH /notes/{id}`.
    func trash(_ id: String) async throws -> LoreNote
    /// Tags of live notes with their counts, most used first. `GET /tags` (Core minor 95).
    func tags() async throws -> [LoreTagCount]
    /// Notes imported from AI session files, newest first. `GET /session-docs` (Core minor 95).
    func sessionDocs() async throws -> [LoreSessionDoc]
}

/// A Core (or a test double) without these routes answers "not implemented", like an old Core does.
extension LoreService {
    public func trash(_ id: String) async throws -> LoreNote {
        throw CoreError.http(status: 501, code: "not_implemented", message: "This Core cannot trash notes.")
    }
    public func tags() async throws -> [LoreTagCount] { [] }
    public func sessionDocs() async throws -> [LoreSessionDoc] { [] }
    public func search(_ query: String, filter: LoreFilter, limit: Int) async throws -> LoreSearchResult {
        throw CoreError.http(status: 501, code: "not_implemented", message: "This Core cannot search notes.")
    }
    public func list(filter: LoreFilter) async throws -> [LoreNote] {
        throw CoreError.http(status: 501, code: "not_implemented", message: "This Core cannot list notes.")
    }
    public func restore(_ id: String) async throws -> LoreNote {
        throw CoreError.http(status: 501, code: "not_implemented", message: "This Core cannot restore notes.")
    }
    public func export(project: String?) async throws -> Data {
        throw CoreError.http(status: 501, code: "not_implemented", message: "This Core cannot export notes.")
    }
}

/// The real one: signed requests through the paired connection, the way Leyline and the Brain reach their modules.
public struct LiveLoreService: LoreService {
    public typealias Send = @Sendable (_ method: String, _ target: String, _ body: Data) async throws -> Data
    static let base = "/modules/lore/v1"
    static let bodyMax = 16 << 20
    let send: Send
    let projects: @Sendable () async throws -> [String: String]

    public init(connection: CoreConnection) {
        // A zip import is the one body over 1 MiB (the Core allows 16 MiB on that route only).
        send = { try await connection.signedRequest(method: $0, target: $1, body: $2, limit: Self.bodyMax) }
        projects = {
            do {
                let list = try await connection.client.listProjects().ok.body.json
                return Dictionary(list.map { (String($0.id), $0.name) }, uniquingKeysWith: { a, _ in a })
            } catch { throw CoreFailure.of(error) ?? error }
        }
    }

    /// Tests: any transport.
    public init(send: @escaping Send, projects: @escaping @Sendable () async throws -> [String: String] = { [:] }) {
        self.send = send
        self.projects = projects
    }

    public func today(_ day: String) async throws -> LoreNote {
        try await call("GET", "/today?day=\(Self.query(day))", as: NoteWire.self).note
    }

    public func daily(_ day: String) async throws -> LoreNote? {
        // ponytail: the 500 most recently changed daily notes; an older day reads as empty and `today` finds it on the
        // first save (the save then merges). A `?day=` filter on `GET /notes` would make it exact.
        let list = try await call("GET", "/notes?kind=daily&state=active", as: [NoteWire].self)
        guard let hit = list.first(where: { $0.day == day }) else { return nil }
        return try await note(hit.id)
    }

    public func note(_ id: String) async throws -> LoreNote {
        try await call("GET", "/notes/\(Self.seg(id))", as: NoteWire.self).note
    }

    public func create(text: String, project: String?) async throws -> LoreNote {
        struct Body: Encodable {
            let text: String
            let project: String?
        }
        return try await call("POST", "/notes", Body(text: text, project: project), as: NoteWire.self).note
    }

    public func save(_ id: String, baseRev: Int, text: String) async throws -> LoreSaveResult {
        struct Body: Encodable {
            let baseRev: Int
            let text: String
            enum CodingKeys: String, CodingKey {
                case text
                case baseRev = "base_rev"
            }
        }
        let w = try await call(
            "PUT", "/notes/\(Self.seg(id))/text", Body(baseRev: baseRev, text: text), as: SaveWire.self)
        return LoreSaveResult(note: w.note.note, outcome: w.outcome, version: w.version)
    }

    public func projectNames() async throws -> [String: String] { try await projects() }

    public func search(_ query: String, filter: LoreFilter, limit: Int) async throws -> LoreSearchResult {
        let w = try await call(
            "GET", "/search?q=\(Self.query(query))&limit=\(limit)" + Self.filterQuery(filter), as: SearchWire.self)
        return LoreSearchResult(
            hits: w.results.map {
                LoreHit(
                    note: $0.note.note, via: $0.via, heading: $0.heading,
                    snippet: LoreSnippet(
                        text: $0.snippet.text,
                        matches: $0.snippet.matches.map { LoreSpan(start: $0.start, end: $0.end) }
                    ))
            }, semantic: w.semantic)
    }

    public func list(filter: LoreFilter) async throws -> [LoreNote] {
        // Core minor 95 filters the list by `tag`; an older Core ignores it and answers every note.
        try await call("GET", "/notes?" + String(Self.filterQuery(filter).dropFirst()), as: [NoteWire].self).map(
            \.note)
    }

    public func trash(_ id: String) async throws -> LoreNote {
        struct Body: Encodable { let trashed: Bool }
        return try await call("PATCH", "/notes/\(Self.seg(id))", Body(trashed: true), as: NoteWire.self).note
    }

    public func restore(_ id: String) async throws -> LoreNote {
        struct Body: Encodable { let trashed: Bool }
        return try await call("PATCH", "/notes/\(Self.seg(id))", Body(trashed: false), as: NoteWire.self).note
    }

    public func export(project: String?) async throws -> Data {
        // A zip, not JSON: the bytes as they come.
        let q = project.map { "?project=\(Self.query($0))" } ?? ""
        return try await send("GET", Self.base + "/export" + q, Data())
    }

    /// `&state=…&kind=…&project=…&tag=…`, each only when set.
    static func filterQuery(_ f: LoreFilter) -> String {
        var s = "&state=\(Self.query(f.state))"
        if let k = f.kind { s += "&kind=\(Self.query(k))" }
        if let p = f.project { s += "&project=\(Self.query(p))" }
        if let t = f.tag, !t.isEmpty { s += "&tag=\(Self.query(t))" }
        return s
    }

    public func backlinks(_ id: String) async throws -> [LoreBacklink] {
        try await call("GET", "/notes/\(Self.seg(id))/backlinks", as: [LoreBacklink].self)
    }

    public func versions(_ id: String) async throws -> [LoreVersion] {
        try await call("GET", "/notes/\(Self.seg(id))/versions", as: [LoreVersion].self)
    }

    public func versionText(_ id: String, version: String) async throws -> String {
        struct View: Decodable { let text: String }
        return try await call("GET", "/notes/\(Self.seg(id))/versions/\(Self.seg(version))", as: View.self).text
    }

    public func restore(_ id: String, version: String) async throws -> LoreSaveResult {
        struct Body: Encodable { let version: String }
        let w = try await call("POST", "/notes/\(Self.seg(id))/restore", Body(version: version), as: SaveWire.self)
        return LoreSaveResult(note: w.note.note, outcome: w.outcome, version: w.version)
    }

    public func move(_ id: String, project: String?) async throws -> LoreNote {
        struct Body: Encodable {
            let project: String?
            // `null` makes the note personal, so the key is always sent.
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(project, forKey: .project)
            }
            enum Keys: String, CodingKey { case project }
        }
        return try await call("PATCH", "/notes/\(Self.seg(id))", Body(project: project), as: NoteWire.self).note
    }

    public func tags() async throws -> [LoreTagCount] {
        try await call("GET", "/tags", as: [LoreTagCount].self)
    }

    public func sessionDocs() async throws -> [LoreSessionDoc] {
        try await call("GET", "/session-docs", as: [LoreSessionDoc].self)
    }

    func call<T: Decodable>(_ method: String, _ path: String, _ body: (any Encodable)? = nil, as: T.Type)
        async throws -> T
    {
        let data = try await send(method, Self.base + path, try body.map { try JSONEncoder().encode($0) } ?? Data())
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch {
            throw CoreError.protocolViolation("The Core answered something this app does not know.")
        }
    }

    /// One path segment, escaped so an id can never add a slash or a query.
    static func seg(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? s
    }

    static func query(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#")))
            ?? s
    }
}

private struct NoteWire: Decodable {
    let id: String
    let kind: String
    let day: String?
    let project: String?
    let title: String
    let rev: Int
    let text: String?
    let trashedAt: String?

    var note: LoreNote {
        LoreNote(
            id: id, kind: kind, day: day, project: project, title: title, rev: rev, text: text ?? "",
            trashed: trashedAt != nil)
    }
}

/// `SearchOut`: each hit is the note summary flattened, plus `via`, `heading` and the snippet.
private struct SearchWire: Decodable {
    struct Span: Decodable {
        let start: Int
        let end: Int
    }
    struct Snip: Decodable {
        let text: String
        let matches: [Span]
    }
    struct Hit: Decodable {
        let note: NoteWire
        let via: String
        let heading: String?
        let snippet: Snip
        enum Keys: String, CodingKey { case via, heading, snippet }
        init(from decoder: any Decoder) throws {
            note = try NoteWire(from: decoder)
            let c = try decoder.container(keyedBy: Keys.self)
            via = try c.decode(String.self, forKey: .via)
            heading = try c.decodeIfPresent(String.self, forKey: .heading)
            snippet = try c.decode(Snip.self, forKey: .snippet)
        }
    }
    let results: [Hit]
    let semantic: Bool
}

/// `SaveOut`: the note flattened, plus the outcome and the kept version.
private struct SaveWire: Decodable {
    let note: NoteWire
    let outcome: String
    let version: String?
    enum Keys: String, CodingKey { case outcome, version }
    init(from decoder: any Decoder) throws {
        note = try NoteWire(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        outcome = try c.decode(String.self, forKey: .outcome)
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }
}
