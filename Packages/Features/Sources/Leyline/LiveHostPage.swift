import CoreKit
import Foundation

/// The live host-page calls: terminals, health, commands and runs, files (SFTP), sessions and recordings, Mac-direct and
/// Make Runner. An older Core answers 404 and the page shows "This Core cannot do that yet".
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

    // SFTP: a listing is `[RemoteFileWire]`; a download is read in chunks (`offset`, `limit`) answered as
    // `{data: base64, eof}`; an upload is sent in chunks `{offset, data: base64, done}` and written to the host on `done`.
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

    func sessions(host: String) async throws -> [HostSession] {
        try await call("GET", "/hosts/\(Self.seg(host))/sessions", as: [SessionWire].self).map(\.item)
    }

    func history(host: String) async throws -> [HostEvent] {
        try await call("GET", "/hosts/\(Self.seg(host))/sessions", as: [SessionWire].self).map(\.event)
    }

    /// The cast is an asciicast file (`application/x-asciicast`), not JSON; it needs a live step-up.
    func recording(_ id: String) async throws -> Recording {
        Recording.parse(try await raw("GET", "/sessions/\(Self.seg(id))/recording"))
    }

    func pauseRecording(session: String) async throws {
        _ = try await call("POST", "/sessions/\(Self.seg(session))/recording/pause", as: Ack.self)
    }

    func makeRunner(host: String, rows: Int, cols: Int) async throws -> RunnerInstall {
        struct Body: Encodable {
            let rows: Int
            let cols: Int
        }
        return try await call(
            "POST", "/hosts/\(Self.seg(host))/runner", Body(rows: rows, cols: cols), as: RunnerInstallWire.self
        ).item
    }

    // `POST /hosts/{h}/direct` answers the ready command; `/direct/revoke` drops the lease.
    func startDirect(host: String) async throws -> DirectLease {
        try await call("POST", "/hosts/\(Self.seg(host))/direct", as: DirectWire.self).item
    }

    func stopDirect(host: String) async throws {
        _ = try await call("POST", "/hosts/\(Self.seg(host))/direct/revoke", as: Ack.self)
    }
}
