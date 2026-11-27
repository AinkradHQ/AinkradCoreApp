import CoreKit
import Foundation

/// What the Design screens ask of the Core beyond the first read/rename/link set: comments, approvals, upload, tags, brand
/// kits, the design-system link, AI take-over, archived designs and the library's server search. `DesignService` inherits
/// it, so a service that brings none of this (the older tests) answers in words instead of failing to compile.

/// A note on a screen (a top-level frame) of a design, with an optional pin on a layer.
struct DesignComment: Identifiable, Equatable, Sendable {
    let id: String
    let screen: String
    let body: String
    let author: String
    let createdAt: Date?
    let node: String?
    let parent: String?
    let resolvedAt: Date?
    var x: Double?
    var y: Double?
    var resolved: Bool { resolvedAt != nil }
}

/// What a person is posting.
struct NewDesignComment: Equatable, Sendable {
    var screen: String
    var body: String
    var node: String?
    var parent: String?
    /// The Core takes 1 to 4000 characters.
    static let limit = 4000
    var valid: Bool { (1...Self.limit).contains(body.trimmingCharacters(in: .whitespacesAndNewlines).count) }
}

/// One screen's approval as the Core keeps it (`approved`, `changed` since, or `withdrawn`).
struct ScreenApproval: Equatable, Sendable {
    enum State: String, Sendable { case approved, changed, withdrawn, other }
    let screen: String
    let version: String
    let state: State
    let decidedBy: String
    let decidedAt: Date?
}

/// The Core's answer to an upload: the stored row, and whether the same bytes were already there.
struct UploadResult: Equatable, Sendable {
    let asset: DesignAsset
    let duplicate: Bool
}

protocol DesignLibraryService: Sendable {
    func archivedDocs() async throws -> [DesignDoc]
    /// Brings an archived design back (Core API 109).
    func unarchive(doc: String) async throws
    /// Assets whose name contains `q`, from the Core (it holds more than the 500 the lists show).
    func searchAssets(_ q: String) async throws -> [DesignAsset]
    func comments(doc: String) async throws -> [DesignComment]
    func postComment(doc: String, _ new: NewDesignComment) async throws -> DesignComment
    func resolveComment(doc: String, id: String, resolved: Bool) async throws
    func approvals(doc: String) async throws -> [ScreenApproval]
    func approve(doc: String, screen: String) async throws
    func withdrawApproval(doc: String, screen: String) async throws
    func upload(name: String, kind: String?, project: String?, data: Data) async throws -> UploadResult
    func setTags(sha: String, tags: [String]) async throws -> DesignAsset
    func createCollection(kind: BrandKit.Kind, name: String, colors: [String], fonts: [String], project: String?)
        async throws -> BrandKit
    /// `nil` leaves a field alone; colours and fonts replace the whole list.
    func patchKit(id: String, name: String?, colors: [String]?, fonts: [String]?) async throws -> BrandKit
    func putKitItem(id: String, sha: String, role: String?) async throws
    func removeKitItem(id: String, sha: String) async throws
    /// Links a design to a design system, or ends that (`nil`).
    func setSystem(doc: String, system: String?) async throws -> DesignDoc
    /// Pause AI (`PUT ai-paused`).
    func pauseAI(doc: String) async throws -> DesignDoc
    func takeOver(doc: String) async throws -> DesignDoc
    func resumeAI(doc: String) async throws -> DesignDoc
}

extension DesignLibraryService {
    private static var no: DesignFailure {
        DesignFailure(sentence: "This Core cannot do that yet.", code: "not_found", status: 404)
    }
    func archivedDocs() async throws -> [DesignDoc] { throw Self.no }
    func unarchive(doc: String) async throws {
        throw DesignFailure(sentence: "Restoring needs a Core update.", code: "not_found", status: 404)
    }
    func searchAssets(_ q: String) async throws -> [DesignAsset] { [] }
    func comments(doc: String) async throws -> [DesignComment] { throw Self.no }
    func postComment(doc: String, _ new: NewDesignComment) async throws -> DesignComment { throw Self.no }
    func resolveComment(doc: String, id: String, resolved: Bool) async throws { throw Self.no }
    func approvals(doc: String) async throws -> [ScreenApproval] { throw Self.no }
    func approve(doc: String, screen: String) async throws { throw Self.no }
    func withdrawApproval(doc: String, screen: String) async throws { throw Self.no }
    func upload(name: String, kind: String?, project: String?, data: Data) async throws -> UploadResult {
        throw Self.no
    }
    func setTags(sha: String, tags: [String]) async throws -> DesignAsset { throw Self.no }
    func createCollection(kind: BrandKit.Kind, name: String, colors: [String], fonts: [String], project: String?)
        async throws -> BrandKit
    { throw Self.no }
    func patchKit(id: String, name: String?, colors: [String]?, fonts: [String]?) async throws -> BrandKit {
        throw Self.no
    }
    func putKitItem(id: String, sha: String, role: String?) async throws { throw Self.no }
    func removeKitItem(id: String, sha: String) async throws { throw Self.no }
    func setSystem(doc: String, system: String?) async throws -> DesignDoc { throw Self.no }
    func pauseAI(doc: String) async throws -> DesignDoc { throw Self.no }
    func takeOver(doc: String) async throws -> DesignDoc { throw Self.no }
    func resumeAI(doc: String) async throws -> DesignDoc { throw Self.no }
}

// MARK: wire

struct CommentWire: Decodable {
    let id: String
    let screen: String
    let body: String
    let author: String
    let createdAt: String
    let node: String?
    let parent: String?
    let resolvedAt: String?
    let x: Double?
    let y: Double?

    var comment: DesignComment {
        DesignComment(
            id: id, screen: screen, body: body, author: author, createdAt: Ago.iso(createdAt), node: node,
            parent: parent, resolvedAt: Ago.iso(resolvedAt), x: x, y: y)
    }
}

struct ApprovalWire: Decodable {
    let screen: String
    let version: String
    let state: String
    let decidedBy: String
    let decidedAt: String

    var approval: ScreenApproval {
        ScreenApproval(
            screen: screen, version: version, state: ScreenApproval.State(rawValue: state) ?? .other,
            decidedBy: decidedBy, decidedAt: Ago.iso(decidedAt))
    }
}

/// Only the `duplicate` flag an upload answer adds to an asset row.
private struct UploadFlag: Decodable { let duplicate: Bool? }

// MARK: live

extension LiveDesignService {
    /// The biggest file the Core takes (its route's own cap).
    static let uploadLimit = 25 * 1024 * 1024

    /// `a=1&b=2`, every value escaped so a name can never add a parameter.
    static func query(_ pairs: [(String, String?)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.compactMap { k, v in
            v.map { "\(k)=\($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
        }
        .joined(separator: "&")
    }

    private static func json(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    private func doc(_ method: String, _ path: String, body: Data = Data()) async throws -> DesignDoc {
        try await call(method, path, body: body, as: DocWire.self).doc
    }

    func archivedDocs() async throws -> [DesignDoc] {
        try await call("GET", "/docs?state=archived", as: [DocWire].self).map(\.doc)
    }
    func unarchive(doc id: String) async throws { _ = try await raw("POST", "/docs/\(Self.seg(id))/unarchive") }
    func searchAssets(_ q: String) async throws -> [DesignAsset] {
        try await call("GET", "/assets?" + Self.query([("q", q)]), as: [AssetWire].self).filter(\.library).map(\.asset)
    }

    func comments(doc id: String) async throws -> [DesignComment] {
        try await call("GET", "/docs/\(Self.seg(id))/comments?state=all", as: [CommentWire].self).map(\.comment)
    }
    func postComment(doc id: String, _ new: NewDesignComment) async throws -> DesignComment {
        var f: [String: Any] = ["screen": new.screen, "body": new.body]
        if let n = new.node { f["node"] = n }
        if let p = new.parent { f["parent"] = p }
        return try await call(
            "POST", "/docs/\(Self.seg(id))/comments", body: try Self.json(f), as: CommentWire.self
        ).comment
    }
    func resolveComment(doc id: String, id comment: String, resolved: Bool) async throws {
        _ = try await raw(
            "PUT", "/docs/\(Self.seg(id))/comments/\(Self.seg(comment))/resolved",
            body: try Self.json(["resolved": resolved]))
    }

    func approvals(doc id: String) async throws -> [ScreenApproval] {
        try await call("GET", "/docs/\(Self.seg(id))/approvals", as: [ApprovalWire].self).map(\.approval)
    }
    func approve(doc id: String, screen: String) async throws {
        _ = try await raw("PUT", "/docs/\(Self.seg(id))/screens/\(Self.seg(screen))/approval")
    }
    func withdrawApproval(doc id: String, screen: String) async throws {
        _ = try await raw("DELETE", "/docs/\(Self.seg(id))/screens/\(Self.seg(screen))/approval")
    }

    func upload(name: String, kind: String?, project: String?, data: Data) async throws -> UploadResult {
        let q = Self.query([("name", name), ("kind", kind), ("project", project)])
        let bytes = try await raw("POST", "/assets?" + q, body: data, limit: Self.uploadLimit)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let wire = try? decoder.decode(AssetWire.self, from: bytes) else {
            throw DesignFailure(sentence: "The Core answered something this app does not know.", code: "bad_answer")
        }
        let flag = try? decoder.decode(UploadFlag.self, from: bytes)
        return UploadResult(asset: wire.asset, duplicate: flag?.duplicate ?? false)
    }
    func setTags(sha: String, tags: [String]) async throws -> DesignAsset {
        try await call(
            "PATCH", "/assets/\(Self.seg(sha))", body: try Self.json(["tags": tags]), as: AssetWire.self
        ).asset
    }

    func createCollection(kind: BrandKit.Kind, name: String, colors: [String], fonts: [String], project: String?)
        async throws -> BrandKit
    {
        var f: [String: Any] = ["kind": kind.rawValue, "name": name]
        // A folder takes no colours or fonts.
        if kind == .brandKit {
            f["colors"] = colors
            f["fonts"] = fonts
        }
        if let project { f["project"] = project }
        return try await call("POST", "/collections", body: try Self.json(f), as: CollectionWire.self).kit
    }
    func patchKit(id: String, name: String?, colors: [String]?, fonts: [String]?) async throws -> BrandKit {
        var f: [String: Any] = [:]
        if let name { f["name"] = name }
        if let colors { f["colors"] = colors }
        if let fonts { f["fonts"] = fonts }
        return try await call(
            "PATCH", "/collections/\(Self.seg(id))", body: try Self.json(f), as: CollectionWire.self
        ).kit
    }
    func putKitItem(id: String, sha: String, role: String?) async throws {
        _ = try await raw(
            "PUT", "/collections/\(Self.seg(id))/items/\(Self.seg(sha))",
            body: try Self.json(["role": role.map { $0 as Any } ?? NSNull()]))
    }
    func removeKitItem(id: String, sha: String) async throws {
        _ = try await raw("DELETE", "/collections/\(Self.seg(id))/items/\(Self.seg(sha))")
    }

    func setSystem(doc id: String, system: String?) async throws -> DesignDoc {
        // `system: null` clears the link, so it is written as an explicit null.
        try await doc(
            "PATCH", "/docs/\(Self.seg(id))", body: try Self.json(["system": system.map { $0 as Any } ?? NSNull()]))
    }
    func pauseAI(doc id: String) async throws -> DesignDoc {
        try await doc("PUT", "/docs/\(Self.seg(id))/ai-paused", body: try Self.json(["paused": true]))
    }
    func takeOver(doc id: String) async throws -> DesignDoc { try await doc("POST", "/docs/\(Self.seg(id))/take-over") }
    func resumeAI(doc id: String) async throws -> DesignDoc { try await doc("POST", "/docs/\(Self.seg(id))/resume") }
}
