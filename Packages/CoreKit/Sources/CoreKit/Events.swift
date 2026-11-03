import AinkradClient
import Foundation
import OpenAPIRuntime

/// What the event stream tells its consumer.
public enum EventUpdate: Sendable {
    /// One event, each seq once and in order. Events this build cannot decode are skipped (§14a).
    case event(Components.Schemas.Event)
    /// Replay is done and the WebSocket is open.
    case live
    /// The socket dropped; it resumes after the last seq seen.
    case reconnecting(CoreError?)
    /// Events up to `floor` were trimmed (410 / close 4410): re-sync state from the API; the stream goes on after `floor`.
    case gap(floor: Int64)
    /// The stream is over for good: revoked, or the Core is not the pinned one.
    case ended(CoreError)
}

enum EventWire {
    static func decode(_ data: Data) -> Components.Schemas.Event? {
        let transcoder = Configuration(dateTranscoder: .iso8601WithFractionalSeconds).dateTranscoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            return try transcoder.decode(text)
        }
        return try? decoder.decode(Components.Schemas.Event.self, from: data)
    }

    /// `past retention, floor <seq>; …` → the seq.
    static func floor(fromCloseReason reason: String) -> Int64? {
        guard let rest = reason.components(separatedBy: "floor ").dropFirst().first else { return nil }
        return Int64(rest.prefix { $0.isASCII && $0.isNumber })
    }

    /// Whether the end of the stream is final.
    static func isTerminal(_ e: CoreError) -> Bool {
        switch e {
        case .revoked, .coreIdentityMismatch, .noSharedMinor, .authFailed, .forbiddenScope, .notPaired: true
        default: false
        }
    }
}

/// Replay then follow: HTTP `GET /api/v1/events?after=` to catch up, then `GET /api/v1/events/ws` (signed upgrade, session-bound,
/// `Last-Event-ID` = the last seq seen), forever, with backoff.
struct EventRunner: Sendable {
    let sessions: SessionManager
    let urlSession: URLSession
    let endpoint: CoreEndpoint
    let clock: any CoreClock
    static let page = 1000

    func run(after: Int64?, into out: AsyncStream<EventUpdate>.Continuation) async {
        defer { out.finish() }
        var last: Int64
        do {
            if let after { last = after } else { last = try await latest() }
        } catch {
            if let e = error as? CoreError { out.yield(.ended(e)) }
            return
        }
        var backoff = 0.25
        while !Task.isCancelled {
            do {
                try await replay(&last, out)
                try await follow(&last, out)
                backoff = 0.25
                out.yield(.reconnecting(nil))
            } catch is CancellationError {
                return
            } catch let e as CoreError {
                if EventWire.isTerminal(e) {
                    out.yield(.ended(e))
                    return
                }
                out.yield(.reconnecting(e))
            } catch {
                out.yield(.reconnecting(.offline("the event stream broke")))
            }
            if Task.isCancelled { return }
            let jitter = Double.random(in: 0.8...1.2)
            do { try await clock.sleep(for: .seconds(backoff * jitter)) } catch { return }
            backoff = min(backoff * 2, 10)
        }
    }

    private func latest() async throws -> Int64 {
        let res = try await sessions.perform(method: "GET", target: "/api/v1/events/latest")
        guard let seq = (try? JSONSerialization.jsonObject(with: res.body) as? [String: Any])?["seq"] as? Int64
        else { throw CoreError.protocolViolation("events/latest without a seq") }
        return seq
    }

    /// Pages from `last` until the Core has no more. Past the retention floor: `gap`, then on from the floor.
    private func replay(_ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) async throws {
        while true {
            let res: RawResponse
            do {
                res = try await sessions.perform(
                    method: "GET", target: "/api/v1/events?after=\(last)&limit=\(Self.page)")
            } catch CoreError.pastRetention(let floor) {
                out.yield(.gap(floor: floor))
                last = max(last, floor)
                continue
            }
            guard let page = try? JSONSerialization.jsonObject(with: res.body) as? [String: Any],
                let items = page["items"] as? [Any]
            else { throw CoreError.protocolViolation("an events page that is not the contract's") }
            if items.isEmpty { return }
            for item in items {
                guard let data = try? JSONSerialization.data(withJSONObject: item) else { continue }
                emit(data, &last, out)
            }
            if page["next_after"] as? Int64 == nil { return }
        }
    }

    private func emit(_ data: Data, _ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) {
        // A resume may repeat what was already delivered; never deliver a seq twice. An undecodable event is skipped.
        guard let event = EventWire.decode(data), event.seq > last else { return }
        last = event.seq
        out.yield(.event(event))
    }

    /// One WebSocket, from `last`, until it closes. Throws what ends or interrupts it.
    private func follow(_ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) async throws {
        let path = "/api/v1/events/ws"
        let session = try await sessions.currentSession()
        var headers = try await sessions.headers(method: "GET", target: path, body: Data(), sessionID: session.id)
        headers["last-event-id"] = String(last)
        var comps = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        comps?.scheme = endpoint.url.scheme == "https" ? "wss" : "ws"
        guard let base = comps?.string, let url = URL(string: base + path) else {
            throw CoreError.invalidInput("no WebSocket URL")
        }
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let task = urlSession.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        do {
            // A pong proves the upgrade went through: a quiet stream sends nothing else.
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                task.sendPing { error in c.resume(with: error.map { .failure($0) } ?? .success(())) }
            }
            out.yield(.live)
            while true {
                let message = try await task.receive()
                switch message {
                case .string(let text): emit(Data(text.utf8), &last, out)
                case .data(let data): emit(data, &last, out)
                @unknown default: break
                }
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            try await classify(task, session: session, error: error)
        }
    }

    /// What a dead socket means: a close code the Core chose, or an upgrade that was refused, or the network.
    private func classify(_ task: URLSessionWebSocketTask, session: CoreSession, error: any Error) async throws {
        let code = task.closeCode.rawValue
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        switch code {
        case 4001: throw CoreError.revoked
        case 4410:
            guard let floor = EventWire.floor(fromCloseReason: reason) else {
                throw CoreError.protocolViolation("4410 without a floor")
            }
            throw CoreError.pastRetention(floor: floor)
        case 0:
            // Never opened (the cause is in the upgrade answer) or the connection was lost.
            switch (task.response as? HTTPURLResponse)?.statusCode {
            case 401:
                // The body is not readable on a refused upgrade: drop the session, and the replay that comes next learns
                // `clock_skew` or reopens the session with the usual retry rules.
                await sessions.invalidate(session.id)
                throw CoreError.sessionExpired
            case 403?: throw CoreError.forbiddenScope
            case 429?: throw CoreError.rateLimited(retryAfter: nil)
            default: throw CoreError.offline("the event stream dropped")
            }
        default:
            // 4003 scope_changed, 1012 restarting, 1013 too slow, 1001: reconnect from the last seq.
            return
        }
    }
}
