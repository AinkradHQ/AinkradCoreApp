import CoreKit
import Foundation

/// What the Design screens ask of the Core. The real one calls the module's routes under `/modules/design/v1` through the
/// paired connection (`CoreConnection.signedRequest`), the way Leyline and the Brain do; the Debug demo and the tests bring
/// their own. Reads need `read`; links are `admin` writes without a step-up.
protocol DesignService: Sendable {
    func docs() async throws -> [DesignDoc]
    func assets() async throws -> [DesignAsset]
    func kits() async throws -> [BrandKit]
    /// The bytes of a checked (`ok`) asset. Never called for a font.
    func data(_ sha: String) async throws -> Data
    /// Relates an item to a project (`on`) or ends that.
    func link(_ item: DesignItem, project: String, _ on: Bool) async throws
}

/// A failure the screens can word. `code` is for hover help only.
struct DesignFailure: Error, Equatable, Sendable {
    let sentence: String
    let code: String
    var status = 0
}

struct LiveDesignService: DesignService {
    let connection: CoreConnection
    static let base = "/modules/design/v1"

    func docs() async throws -> [DesignDoc] { try await call("GET", "/docs", as: [DocWire].self).map(\.doc) }
    func assets() async throws -> [DesignAsset] {
        try await call("GET", "/assets", as: [AssetWire].self).filter(\.library).map(\.asset)
    }
    func kits() async throws -> [BrandKit] {
        try await call("GET", "/collections", as: [CollectionWire].self).filter { $0.kind == "brand_kit" }.map(\.kit)
    }
    func data(_ sha: String) async throws -> Data {
        try await raw("GET", "/assets/\(Self.seg(sha))/data")
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

    private func raw(_ method: String, _ path: String) async throws -> Data {
        do {
            return try await connection.signedRequest(method: method, target: Self.base + path)
        } catch CoreError.http(let status, let code, let message) {
            throw Self.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw Self.failure(status: 400, code: "bad_request", message: message)
        }
    }

    private func call<T: Decodable>(_ method: String, _ path: String, as: T.Type) async throws -> T {
        let data = try await raw(method, path)
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

    var doc: DesignDoc {
        DesignDoc(
            id: id, kind: DesignDoc.Kind(rawValue: kind) ?? .design, name: name, system: system, projects: projects,
            aiPaused: aiPaused, createdBy: createdBy, updatedAt: Ago.iso(updatedAt))
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
            updatedAt: Ago.iso(updatedAt))
    }
}
