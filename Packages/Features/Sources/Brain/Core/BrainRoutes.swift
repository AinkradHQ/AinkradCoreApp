import BrainImport
import Foundation

/// A signed request to the Core. The app's `CoreConnection` is the real one; tests use a fake.
public protocol BrainTransport: Sendable {
    /// `path` and any query are exactly as sent, under `/modules/brain/v1`. Throws `BrainHTTPError` for a Core answer that
    /// is not 2xx and not the step-up kind; step-up and auth refusals pass through unchanged for the host to handle.
    func send(_ method: String, _ path: String, body: Data?) async throws -> Data
}

/// The Core answered with an error status.
public struct BrainHTTPError: Error, Sendable, Equatable {
    public let status: Int
    public let code: String
    public let message: String
    public init(status: Int, code: String, message: String = "") {
        self.status = status
        self.code = code
        self.message = message
    }
}

/// The Brain module's routes, one method each. No state: a wizard or a service owns the run it works on.
public struct BrainRoutes: Sendable {
    public static let base = "/modules/brain/v1"
    let transport: any BrainTransport
    public init(transport: any BrainTransport) { self.transport = transport }

    func call<T: Decodable>(
        _ method: String, _ path: String, _ body: (any Encodable)? = nil, as: T.Type = T.self
    ) async throws -> T {
        let data = try await raw(method, path, body)
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw BrainHTTPError(status: 200, code: "bad_answer", message: "The Core's answer was not the Brain's.")
        }
    }

    func raw(_ method: String, _ path: String, _ body: (any Encodable)? = nil) async throws -> Data {
        try await transport.send(method, Self.base + path, body: body.map { try JSONEncoder().encode($0) })
    }

    // MARK: status and rooms

    public func status() async throws -> BrainStatusWire { try await call("GET", "/status") }
    public func rooms() async throws -> [RoomViewWire] { try await call("GET", "/rooms") }
    /// Step-up route: the caller asks for Touch ID around it.
    public func openRoom(_ id: String) async throws -> OpenedWire {
        try await call("POST", "/rooms/\(Self.seg(id))/open")
    }

    // MARK: an import run

    public func startRun(kind: String = "full", sources: [String]) async throws -> String {
        try await call("POST", "/imports", StartRunBody(kind: kind, sources: sources), as: RunIdWire.self).run
    }
    public func collected(run: String, source: String) async throws -> RunView {
        try await call("POST", "/imports/\(Self.seg(run))/collected", CollectedBody(source: source))
    }
    public func run(_ run: String) async throws -> RunView { try await call("GET", "/imports/\(Self.seg(run))") }
    public func proposals(run: String) async throws -> [ProposalCard] {
        try await call("GET", "/imports/\(Self.seg(run))/proposals")
    }
    public func items(run: String, proposal: String, after: Int? = nil, limit: Int = 100) async throws -> ItemPage {
        var q = "?limit=\(limit)"
        if let after { q += "&after=\(after)" }
        return try await call("GET", "/imports/\(Self.seg(run))/proposals/\(Self.seg(proposal))/items" + q)
    }
    func patch(run: String, proposal: String, _ body: ProposalPatchBody) async throws -> ProposalCard {
        try await call("PATCH", "/imports/\(Self.seg(run))/proposals/\(Self.seg(proposal))", body)
    }
    /// Groups the run again; decisions on rooms that survive are kept.
    public func regroup(run: String) async throws -> Regrouped {
        try await call("POST", "/imports/\(Self.seg(run))/regroup")
    }
    public func semantic(run: String) async throws -> SemanticView {
        try await call("GET", "/imports/\(Self.seg(run))/semantic")
    }
    public func settings() async throws -> [BrainSettingWire] { try await call("GET", "/settings") }
    public func setSetting(_ name: String, _ value: Int) async throws -> BrainSettingWire {
        try await call("PUT", "/settings/\(Self.seg(name))", SettingBody(value: value))
    }
    public func merge(run: String, proposal: String, into: String) async throws -> ProposalCard {
        try await call(
            "POST", "/imports/\(Self.seg(run))/proposals/\(Self.seg(proposal))/merge", MergeBody(into: into))
    }
    public func split(run: String, proposal: String, itemIDs: [String], name: String?) async throws -> ProposalCard {
        try await call(
            "POST", "/imports/\(Self.seg(run))/proposals/\(Self.seg(proposal))/split",
            SplitBody(itemIds: itemIDs, name: name))
    }
    public func refuse(run: String, proposal: String) async throws -> ProposalCard {
        try await call("POST", "/imports/\(Self.seg(run))/proposals/\(Self.seg(proposal))/refuse")
    }
    /// `mark` is `needed`, `refused` or `clear`.
    public func markItems(run: String, ids: [String], mark: String) async throws {
        _ = try await raw("PATCH", "/imports/\(Self.seg(run))/items", ItemsPatchBody(ids: ids, mark: mark))
    }
    /// Moves items into another proposal of the run (PATCH items with `proposal`).
    public func moveItems(run: String, ids: [String], to proposal: String) async throws {
        _ = try await raw("PATCH", "/imports/\(Self.seg(run))/items", ItemsPatchBody(ids: ids, proposal: proposal))
    }
    /// Step-up route: the caller asks for Touch ID around it.
    public func commit(run: String) async throws -> CommitResult {
        try await call("POST", "/imports/\(Self.seg(run))/commit")
    }

    /// One path segment, escaped so an id can never add a slash or a query.
    static func seg(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? s
    }
}

/// The uploader's transport on the same signed route set: it posts under `/imports/{run}/...`.
public struct RoutesImportTransport: ImportTransport {
    let routes: BrainRoutes
    public init(routes: BrainRoutes) { self.routes = routes }
    public func post(path: String, body: Data) async throws -> Data {
        try await routes.transport.send("POST", BrainRoutes.base + path, body: body)
    }
}
