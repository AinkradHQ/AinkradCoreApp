import CoreKit
import Foundation

/// What the Design screens ask of the Core. The real one calls the module's routes under `/modules/design/v1` through the
/// paired connection (`CoreConnection.signedRequest`), the way Leyline and the Brain do; the Debug demo and the tests bring
/// their own. Reads need `read`; links are `admin` writes without a step-up.
protocol DesignService: DesignLibraryService {
    func docs() async throws -> [DesignDoc]
    func assets() async throws -> [DesignAsset]
    func kits() async throws -> [BrandKit]
    /// One asset, library or not (the canvas asks for what a design draws with).
    func asset(_ sha: String) async throws -> DesignAsset
    /// The bytes of a checked (`ok`) asset. Fonts are fetched only for the canvas engine, never shown or loaded by the app.
    func data(_ sha: String) async throws -> Data
    /// Relates an item to a project (`on`) or ends that.
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws
    /// The design's versions, newest first (V3-04).
    func versions(doc: String) async throws -> [DesignVersion]
    /// Keeps the design's current state under a name.
    func saveVersion(doc: String, name: String) async throws -> DesignVersion
    /// Rewrites the live design to a version (one Core transaction, so it is an ordinary edit for everyone and Undo works).
    func restoreVersion(doc: String, id: String) async throws
    /// Makes an empty design (`POST /docs`), related to `project` when there is one.
    func create(kind: DesignDoc.Kind, name: String, project: String?) async throws -> DesignDoc
    /// The same, linked to a design system (`NewDoc.system`; designs only).
    func create(kind: DesignDoc.Kind, name: String, project: String?, system: String?) async throws -> DesignDoc
    /// Starts an AI session drawing three directions on the design (E11-4, API minor 95).
    /// `count` 1 or 3; `size` the screen to draw (points). A Core from before these ignores them: three phone screens
    /// (the composer then keeps the best).
    func compose(doc: String, prompt: String, count: Int, size: CGSize) async throws -> ComposeState
    /// Where that drawing is; the first read after the AI is done writes the three frames.
    func composeState(doc: String, id: String) async throws -> ComposeState
    /// Stops the AI session behind a drawing.
    func cancelCompose(session: String) async throws
    /// AI writes a whole design system (tokens) into a system doc: `mode: "system"`, optional brand kit. Needs API 108.
    func composeSystem(doc: String, prompt: String, brandName: String?, colors: [String]) async throws -> ComposeState
    /// A new name for a design, a library file or a brand kit (`PATCH`).
    func rename(_ item: DesignItem, to name: String) async throws
    /// Takes it out of the library: a design is archived (every row kept), a file or a kit deleted. A step-up route.
    func remove(_ item: DesignItem) async throws
}

/// One "draw 3 directions" run, as the Core reports it.
struct ComposeState: Equatable, Sendable {
    enum Phase: String, Sendable { case drawing, applying, done, failed }
    struct Direction: Equatable, Sendable, Identifiable {
        let name: String
        let summary: String
        /// The node id of its frame on the canvas.
        let frame: String?
        var id: String { frame ?? name }
    }
    let id: String
    let phase: Phase
    let reason: String
    let session: String?
    let directions: [Direction]
}

/// A failure the screens can word. `code` is for hover help only.
struct DesignFailure: Error, Equatable, Sendable {
    let sentence: String
    let code: String
    var status = 0
}

extension DesignService {
    // The Core serves no versions route yet (V1-04), so a service that does not bring its own says so in words.
    func versions(doc: String) async throws -> [DesignVersion] { throw Self.noVersions }
    func saveVersion(doc: String, name: String) async throws -> DesignVersion { throw Self.noVersions }
    func restoreVersion(doc: String, id: String) async throws { throw Self.noVersions }
    func create(kind: DesignDoc.Kind, name: String, project: String?) async throws -> DesignDoc {
        throw DesignFailure(sentence: "This Core cannot make designs.", code: "not_found", status: 404)
    }
    func create(kind: DesignDoc.Kind, name: String, project: String?, system: String?) async throws -> DesignDoc {
        try await create(kind: kind, name: name, project: project)
    }
    func compose(doc: String, prompt: String, count: Int, size: CGSize) async throws -> ComposeState {
        throw Self.noCompose
    }
    func composeState(doc: String, id: String) async throws -> ComposeState { throw Self.noCompose }
    func cancelCompose(session: String) async throws {}
    func composeSystem(doc: String, prompt: String, brandName: String?, colors: [String]) async throws -> ComposeState {
        throw Self.noCompose
    }
    func rename(_ item: DesignItem, to name: String) async throws {
        throw DesignFailure(sentence: "This Core cannot rename designs.", code: "not_found", status: 404)
    }
    func remove(_ item: DesignItem) async throws {
        throw DesignFailure(sentence: "This Core cannot delete designs.", code: "not_found", status: 404)
    }
    static var noCompose: DesignFailure {
        DesignFailure(sentence: "This Core cannot draw with AI yet.", code: "not_found", status: 404)
    }
    static var noVersions: DesignFailure {
        DesignFailure(sentence: "This Core does not keep versions yet.", code: "not_found", status: 404)
    }

    func asset(_ sha: String) async throws -> DesignAsset {
        guard let a = try await assets().first(where: { $0.sha == sha }) else {
            throw DesignFailure(sentence: "The Core does not have that file.", code: "not_found", status: 404)
        }
        return a
    }
}

struct LiveDesignService: DesignService {
    let connection: CoreConnection
    static let base = "/modules/design/v1"

    func docs() async throws -> [DesignDoc] { try await call("GET", "/docs", as: [DocWire].self).map(\.doc) }
    func assets() async throws -> [DesignAsset] {
        try await call("GET", "/assets", as: [AssetWire].self).filter(\.library).map(\.asset)
    }
    func kits() async throws -> [BrandKit] {
        try await call("GET", "/collections", as: [CollectionWire].self).map(\.kit)
    }
    func asset(_ sha: String) async throws -> DesignAsset {
        try await call("GET", "/assets/\(Self.seg(sha))", as: AssetWire.self).asset
    }
    func data(_ sha: String) async throws -> Data {
        try await raw("GET", "/assets/\(Self.seg(sha))/data")
    }
    static func path(_ item: DesignItem) -> String {
        switch item {
        case .doc(let d): "/docs/\(seg(d.id))"
        case .asset(let a): "/assets/\(seg(a.sha))"
        case .kit(let k): "/collections/\(seg(k.id))"
        }
    }
    func rename(_ item: DesignItem, to name: String) async throws {
        _ = try await raw("PATCH", Self.path(item), body: try JSONEncoder().encode(["name": name]))
    }
    func remove(_ item: DesignItem) async throws {
        if case .doc = item {
            _ = try await raw("POST", Self.path(item) + "/archive")
        } else {
            _ = try await raw("DELETE", Self.path(item))
        }
    }
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws {
        let path: String =
            switch item {
            case .doc(let d): "/docs/\(Self.seg(d.id))"
            case .asset(let a): "/assets/\(Self.seg(a.sha))"
            case .kit(let k): "/collections/\(Self.seg(k.id))"
            }
        _ = try await raw(on ? "PUT" : "DELETE", "\(path)/projects/\(Self.seg(project))")
    }

    // TODO(V1-04): the versions routes are the plan's T14 shape, not yet in the Core's contract: GET/POST
    // `/docs/{d}/versions` (`{id, kind, name, created_by, created_at}`, POST body `{"name"}`) and POST
    // `/docs/{d}/versions/{id}/restore`. Check them against `openapi.json` when V1-04 lands.
    func versions(doc: String) async throws -> [DesignVersion] {
        try await call("GET", "/docs/\(Self.seg(doc))/versions", as: [VersionWire].self).map(\.version)
    }
    func saveVersion(doc: String, name: String) async throws -> DesignVersion {
        let body = try JSONEncoder().encode(["name": name])
        return try await call("POST", "/docs/\(Self.seg(doc))/versions", body: body, as: VersionWire.self).version
    }
    func restoreVersion(doc: String, id: String) async throws {
        _ = try await raw("POST", "/docs/\(Self.seg(doc))/versions/\(Self.seg(id))/restore")
    }

    func create(kind: DesignDoc.Kind, name: String, project: String?) async throws -> DesignDoc {
        try await create(kind: kind, name: name, project: project, system: nil)
    }
    func create(kind: DesignDoc.Kind, name: String, project: String?, system: String?) async throws -> DesignDoc {
        struct NewDoc: Encodable {
            let kind: String
            let name: String
            let project: String?
            let system: String?
        }
        let body = try JSONEncoder().encode(
            NewDoc(kind: kind.rawValue, name: name, project: project, system: kind == .design ? system : nil))
        return try await call("POST", "/docs", body: body, as: DocWire.self).doc
    }

    func compose(doc: String, prompt: String, count: Int, size: CGSize) async throws -> ComposeState {
        struct Size: Encodable {
            let w: Int
            let h: Int
        }
        struct Body: Encodable {
            let prompt: String
            let count: Int
            let size: Size
        }
        let s = Size(
            w: min(4000, max(200, Int(size.width.rounded()))), h: min(4000, max(200, Int(size.height.rounded()))))
        let body = try JSONEncoder().encode(Body(prompt: prompt, count: count, size: s))
        return try await call("POST", "/docs/\(Self.seg(doc))/compose", body: body, as: ComposeWire.self).result
    }
    func composeSystem(doc: String, prompt: String, brandName: String?, colors: [String]) async throws -> ComposeState {
        struct Brand: Encodable {
            let colors: [String]
            let name: String?
        }
        struct Body: Encodable {
            let prompt: String
            let mode: String
            let brand: Brand?
        }
        let brand = colors.isEmpty && brandName == nil ? nil : Brand(colors: Array(colors.prefix(12)), name: brandName)
        let body = try JSONEncoder().encode(Body(prompt: prompt, mode: "system", brand: brand))
        return try await call("POST", "/docs/\(Self.seg(doc))/compose", body: body, as: ComposeWire.self).result
    }
    func composeState(doc: String, id: String) async throws -> ComposeState {
        try await call("GET", "/docs/\(Self.seg(doc))/compose/\(Self.seg(id))", as: ComposeWire.self).result
    }
    func cancelCompose(session: String) async throws {
        _ = try await raw("POST", "/api/v1/agent-sessions/\(Self.seg(session))/cancel", absolute: true)
    }

    func raw(
        _ method: String, _ path: String, body: Data = Data(), absolute: Bool = false, limit: Int? = nil
    ) async throws -> Data {
        do {
            return try await connection.signedRequest(
                method: method, target: absolute ? path : Self.base + path, body: body, limit: limit)
        } catch CoreError.http(let status, let code, let message) {
            throw Self.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw Self.failure(status: 400, code: "bad_request", message: message)
        }
    }

    func call<T: Decodable>(_ method: String, _ path: String, body: Data = Data(), as: T.Type) async throws -> T
    {
        let data = try await raw(method, path, body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch {
            throw DesignFailure(sentence: "The Core answered something this app does not know.", code: "bad_answer")
        }
    }

    /// One path segment, escaped so an id can never add a slash or a query.
    static func seg(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? s
    }

    static func failure(status: Int, code: String, message: String) -> DesignFailure {
        switch status {
        case 404, 501: DesignFailure(sentence: "This Core does not have Design yet.", code: code, status: status)
        default:
            DesignFailure(sentence: message.isEmpty ? "The Core refused that." : message, code: code, status: status)
        }
    }
}

// MARK: wire

struct DocWire: Decodable {
    let id: String
    let kind: String
    let name: String
    let system: String?
    let projects: [String]
    let aiPaused: Bool
    let createdBy: String
    let updatedAt: String
    let state: String?

    var doc: DesignDoc {
        DesignDoc(
            id: id, kind: DesignDoc.Kind(rawValue: kind) ?? .design, name: name, system: system, projects: projects,
            aiPaused: aiPaused, createdBy: createdBy, updatedAt: Ago.iso(updatedAt), archived: state == "archived")
    }
}

struct ComposeWire: Decodable {
    struct DirectionWire: Decodable {
        let name: String
        let summary: String
        let frame: String?
    }
    let id: String
    let state: String
    let reason: String
    let session: String?
    let directions: [DirectionWire]

    var result: ComposeState {
        ComposeState(
            id: id, phase: .init(rawValue: state) ?? .failed, reason: reason, session: session,
            directions: directions.map { .init(name: $0.name, summary: $0.summary, frame: $0.frame) })
    }
}

struct VersionWire: Decodable {
    let id: String
    let kind: String
    let name: String
    let createdBy: String
    let createdAt: String
    var version: DesignVersion {
        DesignVersion(
            id: id, kind: DesignVersion.Kind(rawValue: kind) ?? .auto, name: name, createdBy: createdBy,
            createdAt: Ago.iso(createdAt))
    }
}

struct AssetWire: Decodable {
    let sha256: String
    let kind: String
    let name: String
    let contentType: String
    let size: Int64
    let checkState: String
    let library: Bool
    let tags: [String]
    let projects: [String]
    let createdAt: String

    var asset: DesignAsset {
        DesignAsset(
            sha: sha256, kind: DesignAsset.Kind(rawValue: kind) ?? .other, name: name, contentType: contentType,
            size: size, check: DesignAsset.Check(rawValue: checkState) ?? .pending, tags: tags, projects: projects,
            createdAt: Ago.iso(createdAt))
    }
}

struct CollectionWire: Decodable {
    struct ItemWire: Decodable {
        let sha256: String
        let role: String?
    }
    let id: String
    let kind: String
    let name: String
    let colors: [String]
    let fonts: [String]
    let items: [ItemWire]
    let projects: [String]
    let updatedAt: String

    var kit: BrandKit {
        BrandKit(
            id: id, name: name, colors: colors, fonts: fonts,
            items: items.map { BrandKit.Item(sha: $0.sha256, role: $0.role) }, projects: projects,
            updatedAt: Ago.iso(updatedAt), kind: BrandKit.Kind(rawValue: kind) ?? .brandKit)
    }
}
