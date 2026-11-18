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
}

/// The real one: signed requests through the paired connection, the way Leyline and the Brain reach their modules.
public struct LiveLoreService: LoreService {
    public typealias Send = @Sendable (_ method: String, _ target: String, _ body: Data) async throws -> Data
    static let base = "/modules/lore/v1"
    let send: Send
    let projects: @Sendable () async throws -> [String: String]

    public init(connection: CoreConnection) {
        send = { try await connection.signedRequest(method: $0, target: $1, body: $2) }
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

    private func call<T: Decodable>(_ method: String, _ path: String, _ body: (any Encodable)? = nil, as: T.Type)
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
