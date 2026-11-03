import Foundation

/// What an attached terminal tells its consumer, in order.
public enum TerminalUpdate: Sendable, Equatable {
    case output(Data)
    /// The screen as it is now (the bytes in between were not kept): clear and draw.
    case snapshot(Data)
    /// The child ended. The socket stays open until the Core closes it.
    case exited(code: Int32?, signal: String?)
    /// The runner refused or lost the stream (`code` is the protocol's machine code).
    case failed(code: String, message: String)
    /// Always last. The terminal itself keeps running unless it exited.
    case closed(TerminalClose)
}

public enum TerminalClose: Sendable, Equatable {
    /// The connection went quiet or the Core restarted: attach again after `cursor`.
    case dropped
    /// Close 4003 `step-up expired`: attach again after Touch ID.
    case stepUpExpired
    /// Close 4003 `scope changed`.
    case scopeChanged
    /// Close 4001: this device was revoked.
    case revoked
    /// This side detached.
    case detached
}

/// One attach to one terminal over `terminals/{id}/ws` (spec §2): a socket, the frames in and out, credit and the byte cursor
/// to reattach from. A dropped socket ends it with `.closed(.dropped)`; the owner attaches again with `after: cursor`.
public final class TerminalAttachment: @unchecked Sendable {
    public let opened: TerminalOpened
    public let updates: AsyncStream<TerminalUpdate>

    private let socket: any EventSocket
    private let clock: any CoreClock
    private let wake: AsyncStream<Void>.Continuation
    private let wakes: AsyncStream<Void>
    private let feed: AsyncStream<TerminalUpdate>.Continuation
    private let lock = NSLock()
    private var flow = TerminalFlow()
    private var cursorState: TerminalCursor
    private var sendSeq: UInt64 = 0
    private var finished = false
    private var gate: CheckedContinuation<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var outbox: [Data] = []

    /// The next byte to ask for on a reattach.
    public var cursor: UInt64 { lock.withLock { cursorState.offset } }
    /// A snapshot arrived on this socket (the screen was repainted, not replayed).
    public var repainted: Bool { lock.withLock { cursorState.repainted } }
    /// Received and not yet drawn, for tests and the stats line.
    public var pending: Int { lock.withLock { flow.pending } }

    init(socket: any EventSocket, clock: any CoreClock, opened: TerminalOpened, after: UInt64) {
        self.socket = socket
        self.clock = clock
        self.opened = opened
        self.cursorState = TerminalCursor(after: after)
        var f: AsyncStream<TerminalUpdate>.Continuation!
        self.updates = AsyncStream(bufferingPolicy: .unbounded) { f = $0 }
        self.feed = f
        var w: AsyncStream<Void>.Continuation!
        self.wakes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { w = $0 }
        self.wake = w
    }

    func start() {
        let reader = Task { await self.read() }
        let writer = Task { await self.write() }
        lock.withLock { tasks = [reader, writer] }
    }

    // MARK: sending

    /// Typed or pasted bytes. Dropped when the socket is gone.
    public func input(_ bytes: Data) {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let j = bytes.index(i, offsetBy: 32 * 1024, limitedBy: bytes.endIndex) ?? bytes.endIndex
            let chunk = bytes[i..<j]
            enqueue { TerminalOut.input(Data(chunk), seq: $0) }
            i = j
        }
    }

    public func resize(rows: Int, cols: Int) { enqueue { TerminalOut.resize(rows: rows, cols: cols, seq: $0) } }
    public func signal(_ name: String) { enqueue { TerminalOut.signal(name, seq: $0) } }

    /// The renderer drew `bytes`: reading goes on, and credit goes back in steps.
    public func drawn(_ bytes: Int) {
        let (grant, resume) = lock.withLock { () -> (Int, CheckedContinuation<Void, Never>?) in
            let g = flow.drawn(bytes)
            let r = flow.wantsMore ? gate : nil
            if r != nil { gate = nil }
            return (g, r)
        }
        if grant > 0 { enqueue { TerminalOut.credit(grant, seq: $0) } }
        resume?.resume()
    }

    /// Detach: the socket closes, the terminal keeps running (spec §2).
    public func detach() { finish(.detached) }

    private func enqueue(_ make: (UInt64) -> Data) {
        let ok = lock.withLock { () -> Bool in
            guard !finished else { return false }
            outbox.append(make(sendSeq))
            sendSeq += 1
            return true
        }
        if ok { wake.yield() }
    }

    // MARK: loops

    private func write() async {
        var windowStart = clock.now()
        var spent = 0
        for await _ in wakes {
            while let frame = lock.withLock({ () -> Data? in outbox.isEmpty ? nil : outbox.removeFirst() }) {
                // The Core drops input past 256 KiB a second: pace pastes under it instead of losing them.
                if clock.now().timeIntervalSince(windowStart) >= 1 {
                    windowStart = clock.now()
                    spent = 0
                }
                spent += frame.count
                if spent > 160 * 1024 {
                    try? await clock.sleep(for: .seconds(max(0.05, 1 - clock.now().timeIntervalSince(windowStart))))
                    windowStart = clock.now()
                    spent = frame.count
                }
                do { try await socket.send(frame) } catch {
                    finish(.dropped)
                    return
                }
            }
        }
    }

    private func read() async {
        while !lock.withLock({ finished }) {
            await waitForRoom()
            if lock.withLock({ finished }) { return }
            let data: Data
            do { data = try await socket.receive() } catch {
                finish(Self.close(for: socket.closeCode))
                return
            }
            guard let frame = TerminalFrame.decode(data) else { continue }
            let update: TerminalUpdate?
            lock.withLock {
                cursorState.apply(frame)
                switch frame {
                case .output(let d): flow.received(d.count)
                case .snapshot(_, let d): flow.received(d.count)
                default: break
                }
            }
            switch frame {
            case .output(let d): update = .output(d)
            case .snapshot(_, let d): update = .snapshot(d)
            case .exit(let c, let s): update = .exited(code: c, signal: s)
            case .error(let code, let message): update = .failed(code: code, message: message)
            case .close: update = .closed(.dropped)
            default: update = nil
            }
            if case .closed = update {
                finish(.dropped)
                return
            }
            if let update { feed.yield(update) }
        }
    }

    private func waitForRoom() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let wait = lock.withLock { () -> Bool in
                if flow.wantsMore || finished { return false }
                gate = c
                return true
            }
            if !wait { c.resume() }
        }
    }

    static func close(for code: Int) -> TerminalClose {
        switch code {
        case 4001: .revoked
        case 4003: .stepUpExpired
        default: .dropped
        }
    }

    /// Ends this attachment once: last update, socket closed, readers released.
    func finish(_ why: TerminalClose) {
        let (already, gate, tasks) = lock.withLock {
            () -> (Bool, CheckedContinuation<Void, Never>?, [Task<Void, Never>]) in
            defer {
                finished = true
                self.gate = nil
            }
            return (finished, self.gate, self.tasks)
        }
        guard !already else { return }
        gate?.resume()
        socket.cancel()
        feed.yield(.closed(why))
        feed.finish()
        wake.finish()
        for t in tasks { t.cancel() }
    }
}

extension CoreConnection {
    /// Attaches to a terminal: a signed, session-bound upgrade of `terminals/{id}/ws?after=` (the Core wants an elevated
    /// session, so a lapsed one throws `stepUpRequired`: elevate and call again). Returns once the runner's `opened` arrived.
    public func attachTerminal(_ id: String, after: UInt64 = 0) async throws -> TerminalAttachment {
        guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            throw CoreError.invalidInput("not a terminal id")
        }
        let path = "/api/v1/terminals/\(id)/ws"
        let target = after > 0 ? "\(path)?after=\(after)" : path
        let session = try await sessions.currentSession()
        let headers = try await sessions.headers(method: "GET", target: target, body: Data(), sessionID: session.id)
        var comps = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        comps?.scheme = endpoint.url.scheme == "https" ? "wss" : "ws"
        guard let base = comps?.string, let url = URL(string: base + target) else {
            throw CoreError.invalidInput("no WebSocket URL")
        }
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let socket = makeSocket(request)
        socket.start()
        do {
            try await socket.ping()
            let opened = try await Self.firstFrame(socket)
            let a = TerminalAttachment(socket: socket, clock: clock, opened: opened, after: after)
            a.start()
            return a
        } catch {
            socket.cancel()
            throw await refusal(socket, session: session, error: error)
        }
    }

    /// The `opened` frame, within 20 s.
    private static func firstFrame(_ socket: any EventSocket) async throws -> TerminalOpened {
        try await withThrowingTaskGroup(of: TerminalOpened.self) { group in
            group.addTask {
                while true {
                    let data = try await socket.receive()
                    switch TerminalFrame.decode(data) {
                    case .opened(let o): return o
                    case .error(let code, let message): throw CoreError.http(status: 409, code: code, message: message)
                    default: continue
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw CoreError.offline("the terminal did not answer")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// What a refused upgrade or an early close means (the body of a refused upgrade is not readable, so the status decides).
    private func refusal(_ socket: any EventSocket, session: CoreSession, error: any Error) async -> any Error {
        if let e = error as? CoreError { return e }
        if error is CancellationError { return error }
        switch socket.closeCode {
        case 4001: return CoreError.revoked
        case 4003: return CoreError.stepUpRequired
        default: break
        }
        switch socket.responseStatus {
        case 401:
            await sessions.invalidate(session.id)
            return CoreError.sessionExpired
        case 403?: return session.scopes.contains("terminal") ? CoreError.stepUpRequired : CoreError.forbiddenScope
        case 404?:
            return CoreError.http(status: 404, code: "not_found", message: "The Core does not know this terminal.")
        case 409?:
            return CoreError.http(status: 409, code: "conflict", message: "The runner cannot take this terminal now.")
        case 429?:
            return CoreError.http(
                status: 429, code: "too_many_attaches", message: "Too many clients are attached to this terminal.")
        default: return CoreError.offline("the terminal connection dropped")
        }
    }
}
