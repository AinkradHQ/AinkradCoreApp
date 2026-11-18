import CoreKit
import Foundation

/// The live host-page calls. Routes that exist in the Core today: terminals (Y3-01), commands and runs (Y4-02). The rest
/// (health, files, history, Mac-direct) are the routes the plan's stories add (Y5-01, Y2-03, Y3-02, Y6-01); their paths and
/// shapes are written down here so the epic build has one place to align, and until the Core has them they answer 404 and
/// the page shows "This Core cannot do that yet".
extension LiveLeylineService {
    /// Most a transfer may hold in memory, and the chunk each signed request carries (a body is JSON, at most 1 MiB).
    static let transferCap = 64 << 20
    static let chunk = 512 << 10

    private static func q(_ s: String) -> String {
        s.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#?")))
            ?? s
    }

    func openTerminal(host: String, rows: Int, cols: Int) async throws -> String {
        struct Body: Encodable {
            let rows: Int
            let cols: Int
        }
        return try await call(
            "POST", "/hosts/\(Self.seg(host))/terminals", Body(rows: rows, cols: cols), as: HostTerminalOpened.self
        ).terminal
    }

    // TODO(Y5-01): `GET /hosts/{h}/health` (the samples the prober stores) is not routed yet.
    func health(host: String) async throws -> HostHealth {
        try await call("GET", "/hosts/\(Self.seg(host))/health", as: HealthWire.self).item
    }

    func commands() async throws -> [PresetCommand] {
        try await call("GET", "/commands", as: [CommandWire].self).map(\.item)
    }

    func runCommand(_ command: String, host: String, confirmed: Bool) async throws -> String {
        struct Body: Encodable {
            let host: String
            let confirm: Bool
        }
        do {
            return try await call(
                "POST", "/commands/\(Self.seg(command))/run", Body(host: host, confirm: confirmed), as: RunStarted.self
            ).run
        } catch let e as LeylineFailure where e.status == 409 {
            // 409 here is "not for this host" or "needs confirming", not a taken name.
            throw LeylineFailure(
                sentence: "This command is not for this host, or it needs confirming first.", code: e.code, status: 409)
        }
    }

    func run(_ id: String, host: String, name: String) async throws -> CommandRun {
        try await call("GET", "/runs/\(Self.seg(id))", as: RunWire.self).item(host: host, name: name)
    }

    // TODO(Y2-03): the Core routes for SFTP. Shapes assumed: a listing is `[RemoteFileWire]`; a download is read in chunks
    // (`offset`, `limit`) answered as `{data: base64, eof}`; an upload is written in chunks `{offset, data: base64, done}`.
    func files(host: String, path: String) async throws -> [RemoteFile] {
        try await call("GET", "/hosts/\(Self.seg(host))/files?path=\(Self.q(path))", as: [RemoteFileWire].self).map(
            \.item)
    }

    func download(host: String, path: String) async throws -> Data {
        struct Part: Decodable {
            let data: String
            let eof: Bool
        }
        var out = Data()
        while true {
            let p = try await call(
                "GET",
                "/hosts/\(Self.seg(host))/files/content?path=\(Self.q(path))&offset=\(out.count)&limit=\(Self.chunk)",
                as: Part.self)
            guard let d = Data(base64Encoded: p.data) else {
                throw LeylineFailure(
                    sentence: "The Core answered something this app does not know.", code: "bad_answer")
            }
            out.append(d)
            if p.eof || d.isEmpty { return out }
            if out.count > Self.transferCap { throw Self.tooBig }
        }
    }

    func upload(host: String, path: String, data: Data) async throws {
        struct Part: Encodable {
            let offset: Int
            let data: String
            let done: Bool
        }
        guard data.count <= Self.transferCap else { throw Self.tooBig }
        var at = 0
        repeat {
            let end = min(at + Self.chunk, data.count)
            _ = try await call(
                "PUT", "/hosts/\(Self.seg(host))/files/content?path=\(Self.q(path))",
                Part(offset: at, data: data[at..<end].base64EncodedString(), done: end == data.count),
                as: Ack.self)
            at = end
        } while at < data.count
    }

    private static let tooBig = LeylineFailure(
        sentence: "This app moves files up to 64 MB. Use Mac-direct (scp) for bigger ones.", code: "too_big",
        status: 413)

    /// Answers whose body this app ignores.
    private struct Ack: Decodable {}

    // TODO(Y3-02): `GET /hosts/{h}/sessions` (what happened here) and `GET /sessions/{s}/recording` (the cast).
    func history(host: String) async throws -> [HostEvent] {
        try await call("GET", "/hosts/\(Self.seg(host))/history", as: [HostEventWire].self).map(\.item)
    }

    func recording(_ id: String) async throws -> Recording {
        struct Cast: Decodable { let cast: String }
        return Recording.parse(Data(try await call("GET", "/recordings/\(Self.seg(id))", as: Cast.self).cast.utf8))
    }

    // TODO(Y6-01): `POST /hosts/{h}/direct` answers the ready command; `/direct/revoke` drops the lease.
    func startDirect(host: String) async throws -> DirectLease {
        try await call("POST", "/hosts/\(Self.seg(host))/direct", as: DirectWire.self).item
    }

    func stopDirect(host: String) async throws {
        _ = try await call("POST", "/hosts/\(Self.seg(host))/direct/revoke", as: Ack.self)
    }
}
