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

    /// The seq of a raw event, readable even when the rest of it does not decode (so a cursor can pass it).
    static func rawSeq(_ data: Data) -> Int64? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["seq"] as? Int64
    }

    /// Whether the end of the stream is final. Not `.coreUnproven`: that one is retried.
    static func isTerminal(_ e: CoreError) -> Bool {
        switch e {
        case .revoked, .coreIdentityMismatch, .noSharedMinor, .authFailed, .forbiddenScope, .notPaired: true
        default: false
        }
    }
}

/// A WebSocket as the runner needs it, so tests can stand in for the network.
protocol EventSocket: Sendable {
    func start()
    func ping() async throws
    func receive() async throws -> Data
    /// Sends one text frame (the terminal socket; the event socket never sends).
    func send(_ data: Data) async throws
    func cancel()
    /// The close code the Core sent, 0 when none.
    var closeCode: Int { get }
    var closeReason: String { get }
    /// The status of a refused upgrade, when there was one.
    var responseStatus: Int? { get }
}

extension EventSocket {
    func send(_ data: Data) async throws { throw CoreError.protocolViolation("this socket cannot send") }
}

/// `URLSessionWebSocketTask`. It is documented thread-safe; its state is only read after the task ended.
final class URLSessionEventSocket: EventSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    init(_ task: URLSessionWebSocketTask) { self.task = task }
    func start() { task.resume() }
    func ping() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in c.resume(with: error.map { .failure($0) } ?? .success(())) }
        }
    }
    func receive() async throws -> Data {
        switch try await task.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: Data()
        }
    }
    func send(_ data: Data) async throws { try await task.send(.string(String(decoding: data, as: UTF8.self))) }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }
    var closeCode: Int { task.closeCode.rawValue }
    var closeReason: String { task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    var responseStatus: Int? { (task.response as? HTTPURLResponse)?.statusCode }
}

/// The consumer's buffer is full: the cursor stays before the event that did not fit, and the stream replays after a pause.
struct EventBackpressure: Error {}

/// How a socket ended without an error to throw.
enum FollowEnd { case closed, scopeChanged }

/// Replay then follow: HTTP `GET /api/v1/events?after=` to catch up, then `GET /api/v1/events/ws` (signed upgrade, session-bound,
/// `Last-Event-ID` = the last seq seen), forever, with backoff.
struct EventRunner: Sendable {
    let sessions: SessionManager
    let endpoint: CoreEndpoint
    let clock: any CoreClock
    let makeSocket: @Sendable (URLRequest) -> any EventSocket
    static let page = 1000

    func run(after: Int64?, into out: AsyncStream<EventUpdate>.Continuation) async {
        defer { out.finish() }
        var last: Int64
        do {
            if let after { last = after } else { last = try await latest().seq }
        } catch {
            if let e = error as? CoreError { out.yield(.ended(e)) }
            return
        }
        var backoff = 0.25
        var needsResync = false
        while !Task.isCancelled {
            do {
                if needsResync {
                    // Cursors count in the device's scope view, which changed: the old one means nothing now. Tell the
                    // consumer to re-sync and carry on from the head of the new view; a failure here retries before any replay.
                    let head = try await latest()
                    // A gap the consumer never received is not reported: needsResync stays set and it is yielded again.
                    if case .dropped = out.yield(.gap(floor: head.seq)) { throw EventBackpressure() }
                    last = head.seq
                    needsResync = false
                }
                try await replay(&last, out)
                let end = try await follow(&last, out)
                if end == .scopeChanged { needsResync = true }
                backoff = 0.25
                out.yield(.reconnecting(nil))
            } catch is CancellationError {
                return
            } catch is EventBackpressure {
                // Nothing to tell a consumer whose buffer is full: wait for it to catch up, then replay from `last`.
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

    private func latest() async throws -> (seq: Int64, floor: Int64?) {
        let res = try await sessions.perform(method: "GET", target: "/api/v1/events/latest")
        let obj = (try? JSONSerialization.jsonObject(with: res.body) as? [String: Any])
        guard let seq = obj?["seq"] as? Int64 else { throw CoreError.protocolViolation("events/latest without a seq") }
        return (seq, obj?["floor"] as? Int64)
    }

    /// Pages from `last` until the Core has no more. Past the retention floor: `gap`, then on from the floor.
    private func replay(_ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) async throws {
        while true {
            let res: RawResponse
            do {
                res = try await sessions.perform(
                    method: "GET", target: "/api/v1/events?after=\(last)&limit=\(Self.page)")
            } catch CoreError.pastRetention(let floor) {
                if case .dropped = out.yield(.gap(floor: floor)) { throw EventBackpressure() }  // cursor stays
                last = max(last, floor)
                continue
            }
            guard let page = try? JSONSerialization.jsonObject(with: res.body) as? [String: Any],
                let items = page["items"] as? [Any]
            else { throw CoreError.protocolViolation("an events page that is not the contract's") }
            let before = last
            for item in items {
                guard let data = try? JSONSerialization.data(withJSONObject: item) else { continue }
                try deliver(data, &last, out)
            }
            // The cursor moves past an event that does not decode too, so a bad one cannot hold the replay in a loop.
            if let next = page["next_after"] as? Int64, next > last { last = next }
            if page["next_after"] as? Int64 == nil || last == before { return }
        }
    }

    /// Delivers one event: each seq once and in order. A resume may repeat what was delivered; an undecodable event is skipped
    /// but still passed by the cursor.
    private func deliver(_ data: Data, _ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) throws {
        guard let seq = EventWire.rawSeq(data), seq > last else { return }
        if let event = EventWire.decode(data), case .dropped = out.yield(.event(event)) {
            throw EventBackpressure()  // the cursor stays before this event
        }
        last = seq
    }

    /// One WebSocket, from `last`, until it closes. Throws what ends or interrupts it.
    private func follow(_ last: inout Int64, _ out: AsyncStream<EventUpdate>.Continuation) async throws -> FollowEnd {
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
        let socket = makeSocket(request)
        socket.start()
        // Cancelling the consumer closes the socket at once, not when the next message happens to arrive.
        return try await withTaskCancellationHandler {
            do {
                // A pong proves the upgrade went through: a quiet stream sends nothing else.
                try await socket.ping()
                out.yield(.live)
                while true {
                    let data = try await socket.receive()
                    try deliver(data, &last, out)
                }
            } catch {
                socket.cancel()
                if error is EventBackpressure { throw error }
                if Task.isCancelled { throw CancellationError() }
                return try await classify(socket, session: session)
            }
        } onCancel: {
            socket.cancel()
        }
    }

    /// What a dead socket means: a close code the Core chose, or an upgrade that was refused, or the network.
    private func classify(_ socket: any EventSocket, session: CoreSession) async throws -> FollowEnd {
        switch socket.closeCode {
        case 4001: throw CoreError.revoked
        case 4410:
            guard let floor = EventWire.floor(fromCloseReason: socket.closeReason) else {
                throw CoreError.protocolViolation("4410 without a floor")
            }
            throw CoreError.pastRetention(floor: floor)
        case 4003: return .scopeChanged
        case 0:
            // Never opened (the cause is in the upgrade answer) or the connection was lost.
            switch socket.responseStatus {
            case 401:
                // The body is not readable on a refused upgrade: drop the session, and the replay that comes next reopens it
                // with the usual retry rules. A `clock_skew` is then reported by that replay, never adopted.
                await sessions.invalidate(session.id)
                throw CoreError.sessionExpired
            case 403?: throw CoreError.forbiddenScope
            case 429?: throw CoreError.rateLimited(retryAfter: nil)
            default: throw CoreError.offline("the event stream dropped")
            }
        default:
            // 1012 restarting, 1013 too slow, 1001: reconnect from the last seq.
            return .closed
        }
    }
}
