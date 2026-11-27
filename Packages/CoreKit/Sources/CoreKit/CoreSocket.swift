import Foundation

/// One WebSocket message: a module socket (Design's sync) speaks binary frames and JSON text frames.
public enum CoreSocketFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// A signed, session-bound WebSocket to a module route (see `CoreConnection.openSocket`).
public final class CoreSocket: Sendable {
    private let socket: any EventSocket
    init(_ socket: any EventSocket) { self.socket = socket }

    public func receive() async throws -> CoreSocketFrame { try await socket.receiveFrame() }
    public func send(_ frame: CoreSocketFrame) async throws { try await socket.sendFrame(frame) }
    public func cancel() { socket.cancel() }
    /// The close code the Core sent, 0 when none (valid after `receive` threw).
    public var closeCode: Int { socket.closeCode }
}

extension CoreConnection {
    /// Opens a signed upgrade of `target` (a path with its raw query, e.g. `/modules/design/v1/docs/dd_…/sync`), the way
    /// the events and terminal sockets are opened. `headers` are extra request headers (Design's `Last-Update-Seq`).
    /// Returns once the upgrade is proven by a pong. A refused upgrade throws the `CoreError` for its status.
    public func openSocket(target: String, headers extra: [String: String] = [:]) async throws -> CoreSocket {
        // Module sockets, and a project run's log tail (`/api/v1/projects/{id}/run/logs/ws`, signed like any request).
        let runLogs = target.hasPrefix("/api/v1/projects/") && target.contains("/run/logs/ws")
        guard target.hasPrefix("/modules/") || runLogs else {
            throw CoreError.invalidInput("\(target) is not a module socket")
        }
        let session = try await sessions.currentSession()
        var headers = try await sessions.headers(method: "GET", target: target, body: Data(), sessionID: session.id)
        for (k, v) in extra { headers[k.lowercased()] = v }
        var comps = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        comps?.scheme = endpoint.url.scheme == "https" ? "wss" : "ws"
        guard let base = comps?.string, let url = URL(string: base + target) else {
            throw CoreError.invalidInput("no WebSocket URL")
        }
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let socket = makeSocket(request)
        socket.start()
        // Opened once the Core answers the upgrade. Not by a ping: a module socket (Design's sync) sends its first frame at
        // once, and URLSession holds the pong behind that unread frame, so a ping before the first read never returns.
        // Never waits for ever: 10 s without an answer is "offline".
        var status = socket.responseStatus
        for _ in 0..<200 where status == nil {
            try? await Task.sleep(for: .milliseconds(50))
            status = socket.responseStatus
        }
        if status != 101 {
            socket.cancel()
            switch status {
            case 401:
                await sessions.invalidate(session.id)
                throw CoreError.sessionExpired
            case 403?: throw CoreError.forbiddenScope
            case let status?:
                throw CoreError.http(status: status, code: "refused", message: "The Core refused the connection.")
            case nil: throw CoreError.offline("the connection did not open in 10 s")
            }
        }
        return CoreSocket(socket)
    }
}
