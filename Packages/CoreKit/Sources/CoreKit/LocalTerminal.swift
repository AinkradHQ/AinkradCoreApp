import Darwin
import Foundation

/// What the Core answers to "let me attach to this terminal directly": a signed grant for the runner host's Unix socket.
public struct LocalTerminalGrant: Sendable, Equatable {
    public var terminal: String
    public var runner: String
    public var grant: String
    public var leaseSecs: Int
    /// The file name of the host's socket in the runner's terminal directory.
    public var socket: String
    public init(terminal: String, runner: String, grant: String, leaseSecs: Int, socket: String) {
        self.terminal = terminal
        self.runner = runner
        self.grant = grant
        self.leaseSecs = leaseSecs
        self.socket = socket
    }
}

/// Why the local path could not be used. The caller falls back to the Core's WebSocket on every one of these.
public enum LocalPathError: Error, Equatable, Sendable {
    /// No socket, an unsafe directory or socket, or another user's peer.
    case unavailable(String)
    /// The host answered, but did not accept the grant.
    case refused(String)
    /// The host did not speak the local protocol in time.
    case timedOut
}

/// A blocking line socket on a Unix domain socket: one JSON message per line (the host's protocol).
final class UnixLineSocket: @unchecked Sendable {
    private var fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var buffer = Data()

    private init(fd: Int32) { self.fd = fd }

    /// Connects to `path` only when it is safe to: the directory is ours, real and private; the socket is ours; the peer is us.
    static func connect(_ path: String) throws -> UnixLineSocket {
        let url = URL(fileURLWithPath: path)
        var st = stat()
        guard lstat(url.deletingLastPathComponent().path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR,
            st.st_uid == getuid(), st.st_mode & 0o077 == 0
        else { throw LocalPathError.unavailable("the terminal folder is not private to this user") }
        guard lstat(path, &st) == 0 else { throw LocalPathError.unavailable("no local socket") }
        guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == getuid() else {
            throw LocalPathError.unavailable("the local socket is not ours")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalPathError.unavailable("no socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw LocalPathError.unavailable("the socket path is too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            Darwin.close(fd)
            throw LocalPathError.unavailable("the local socket does not answer")
        }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
            Darwin.close(fd)
            throw LocalPathError.unavailable("the local socket is served by another user")
        }
        return UnixLineSocket(fd: fd)
    }

    /// The next line without its newline; nil at EOF, on error, after `close()`, or when `timeout` (seconds, nil: forever) passes.
    /// Lines past 4 MiB end the connection (the host's own limit).
    func readLine(timeout: Double? = nil) -> Data? {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            if let i = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<i]
                buffer.removeSubrange(buffer.startIndex...i)
                return Data(line)
            }
            if buffer.count > 4 << 20 { return nil }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let wait = deadline.map { max(0, Int32($0.timeIntervalSinceNow * 1000)) } ?? -1
            let r = poll(&p, 1, wait)
            if r < 0 { if errno == EINTR { continue } else { return nil } }
            if r == 0 { return nil }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    /// Writes all of `line` plus a newline.
    @discardableResult
    func write(_ line: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        var data = line
        data.append(0x0A)
        var sent = 0
        return data.withUnsafeBytes { raw in
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Wakes a blocked reader and ends the connection.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

/// Where a local attach gets its grants and signatures: the Core (grants, release) and this device's routine key.
public struct LocalGrantSource: Sendable {
    /// A fresh grant (this is also the lease renewal, so it goes to the Core each time).
    public var grant: @Sendable () async throws -> LocalTerminalGrant
    /// ES256 over `message` with the device key the grants name.
    public var sign: @Sendable (Data) async throws -> Data
    /// Tells the Core this device detached.
    public var release: @Sendable () async -> Void
    public init(
        grant: @escaping @Sendable () async throws -> LocalTerminalGrant,
        sign: @escaping @Sendable (Data) async throws -> Data,
        release: @escaping @Sendable () async -> Void
    ) {
        self.grant = grant
        self.sign = sign
        self.release = release
    }
}

/// One attach to one terminal over the runner host's own Unix socket: the same updates, input, resize and cursor as
/// `TerminalAttachment`, with no Core on the byte path. The Core's signed grant opens it and renews it every third of a
/// lease; when it stops granting (revoked, no step-up) the host closes the socket within a lease.
public final class LocalTerminalAttachment: @unchecked Sendable {
    public let opened: TerminalOpened
    public let updates: AsyncStream<TerminalUpdate>

    private let socket: UnixLineSocket
    private let source: LocalGrantSource
    private let feed: AsyncStream<TerminalUpdate>.Continuation
    private let writes = DispatchQueue(label: "ainkrad.local-terminal.write")
    private let cond = NSCondition()
    private var flow = TerminalFlow()
    private var offset: UInt64
    private var repaint = false
    private var challenge: String
    private var finished = false
    private var renewal: Task<Void, Never>?

    public var cursor: UInt64 { cond.withLock { offset } }
    public var repainted: Bool { cond.withLock { repaint } }

    private init(
        socket: UnixLineSocket, source: LocalGrantSource, opened: TerminalOpened, after: UInt64, challenge: String
    ) {
        self.socket = socket
        self.source = source
        self.opened = opened
        self.offset = after
        self.challenge = challenge
        var f: AsyncStream<TerminalUpdate>.Continuation!
        updates = AsyncStream(bufferingPolicy: .unbounded) { f = $0 }
        feed = f
    }

    /// Connects to `socketPath`, proves the grant, and attaches after byte `after`. Throws `LocalPathError` (or the
    /// grant/sign error) when the path cannot be used: the caller then attaches through the Core.
    public static func open(
        socketPath: String, first: LocalTerminalGrant, source: LocalGrantSource, after: UInt64
    ) async throws -> LocalTerminalAttachment {
        let sock = try await offloadThrowing { try UnixLineSocket.connect(socketPath) }
        do {
            guard let challengeLine = await offload({ sock.readLine(timeout: 5) }),
                let c = Self.object(challengeLine), c["type"] as? String == "challenge",
                let nonce = c["nonce"] as? String
            else { throw LocalPathError.timedOut }
            try await Self.authenticate(sock, grant: first.grant, challenge: nonce, sign: source.sign)
            var opened: TerminalOpened?
            var next = nonce
            var lease = first.leaseSecs
            while opened == nil {
                guard let line = await offload({ sock.readLine(timeout: 5) }), let m = Self.object(line) else {
                    throw LocalPathError.timedOut
                }
                switch m["type"] as? String {
                case "error": throw LocalPathError.refused(m["message"] as? String ?? "refused")
                case "authed":
                    next = m["challenge"] as? String ?? next
                    lease = Int((m["lease_ms"] as? Int ?? lease * 1000) / 1000)
                case "hello": opened = Self.opened(m["info"] as? [String: Any] ?? [:])
                default: break
                }
            }
            let a = LocalTerminalAttachment(
                socket: sock, source: source, opened: opened!, after: after, challenge: next)
            a.start(lease: lease)
            return a
        } catch {
            sock.close()
            throw error
        }
    }

    private static func authenticate(
        _ sock: UnixLineSocket, grant: String, challenge: String, sign: @Sendable (Data) async throws -> Data
    ) async throws {
        let sig = try await sign(Self.attachMessage(challenge: challenge, grant: grant))
        sock.write(Self.line(["type": "auth", "grant": grant, "sig": Wire.b64(sig)]))
    }

    /// What the device key signs: the host's challenge and the grant, so a proof is good for one of each.
    static func attachMessage(challenge: String, grant: String) -> Data {
        Data("AINKRAD-LOCAL-ATTACH-V1\n".utf8) + Data(challenge.utf8) + Data("\n".utf8) + Data(grant.utf8)
    }

    private static func opened(_ info: [String: Any]) -> TerminalOpened {
        let size = info["size"] as? [String: Any]
        let exit = info["exit"] as? [String: Any]
        return TerminalOpened(
            state: info["state"] as? String ?? "running", rows: size?["rows"] as? Int ?? 0,
            cols: size?["cols"] as? Int ?? 0,
            seq: (info["seq"] as? NSNumber)?.uint64Value ?? 0, exitCode: (exit?["code"] as? Int).map(Int32.init),
            exitSignal: exit?["signal"] as? String)
    }

    private static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    private static func line(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private static func offloadThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            DispatchQueue.global().async { c.resume(with: Result { try work() }) }
        }
    }

    private static func offload<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { c in DispatchQueue.global().async { c.resume(returning: work()) } }
    }

    // MARK: running

    private func start(lease: Int) {
        let t = Thread { [self] in readLoop() }
        t.name = "ainkrad.local-terminal.read"
        t.start()
        send(["type": "attach", "seq": cursor])
        renewal = Task { [weak self] in await self?.renewLoop(lease: lease) }
    }

    private func send(_ obj: [String: Any]) {
        let line = Self.line(obj)
        writes.async { [self] in
            if !socket.write(line) { finish(.dropped) }
        }
    }

    public func input(_ bytes: Data) {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let j = bytes.index(i, offsetBy: 32 * 1024, limitedBy: bytes.endIndex) ?? bytes.endIndex
            send(["type": "input", "data": Data(bytes[i..<j]).base64EncodedString()])
            i = j
        }
    }

    public func resize(rows: Int, cols: Int) {
        send(["type": "resize", "size": ["rows": rows, "cols": cols]])
    }

    /// The renderer drew `bytes`: the reader may go on (it stops while a window's worth waits to be drawn).
    public func drawn(_ bytes: Int) {
        cond.lock()
        _ = flow.drawn(bytes)
        cond.broadcast()
        cond.unlock()
    }

    public func detach() {
        guard finish(.detached) else { return }
        Task { await source.release() }
    }

    private func readLoop() {
        while true {
            cond.lock()
            while !flow.wantsMore && !finished { cond.wait() }
            let done = finished
            cond.unlock()
            if done { return }
            guard let line = socket.readLine(), let m = Self.object(line) else {
                finish(.dropped)
                return
            }
            handle(m)
        }
    }

    private func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "out":
            guard let text = m["data"] as? String, let bytes = Data(base64Encoded: text) else { return }
            let seq = (m["seq"] as? NSNumber)?.uint64Value ?? 0
            let data: Data? = cond.withLock {
                let end = seq + UInt64(bytes.count)
                guard end > offset else { return nil }
                let skip = Int(min(UInt64(bytes.count), offset > seq ? offset - seq : 0))
                offset = end
                flow.received(bytes.count - skip)
                return skip == 0 ? bytes : bytes.dropFirst(skip)
            }
            if let data, !data.isEmpty { feed.yield(.output(Data(data))) }
        case "snapshot":
            guard let text = m["data"] as? String, let bytes = Data(base64Encoded: text) else { return }
            cond.withLock {
                offset = (m["seq"] as? NSNumber)?.uint64Value ?? offset
                repaint = true
                flow.received(bytes.count)
            }
            feed.yield(.snapshot(bytes))
        case "exit":
            let e = m["exit"] as? [String: Any]
            feed.yield(.exited(code: (e?["code"] as? Int).map(Int32.init), signal: e?["signal"] as? String))
        case "authed":
            if let c = m["challenge"] as? String { cond.withLock { challenge = c } }
        case "error":
            feed.yield(.failed(code: "local", message: m["message"] as? String ?? "the terminal host refused"))
        default: break
        }
    }

    /// Asks the Core for a fresh grant every third of a lease and presents it on the open connection. A Core that says
    /// no ends the attachment the way the WebSocket's close codes do; a Core that cannot be reached is tried again, and if
    /// it stays away the host closes the socket at the end of the lease and the owner reattaches.
    private func renewLoop(lease: Int) async {
        let every = Double(max(3, lease)) / 3
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(every))
            if Task.isCancelled || cond.withLock({ finished }) { return }
            do {
                let g = try await source.grant()
                let c = cond.withLock { challenge }
                let sig = try await source.sign(Self.attachMessage(challenge: c, grant: g.grant))
                send(["type": "auth", "grant": g.grant, "sig": Wire.b64(sig)])
            } catch let e as CoreError {
                switch CoreError.unwrapping(e) ?? e {
                case .stepUpRequired: finish(.stepUpExpired)
                case .revoked: finish(.revoked)
                case .forbiddenScope: finish(.scopeChanged)
                case .http(let status, let code, _) where status == 403 && code.contains("step"): finish(.stepUpExpired)
                case .http(let status, _, _) where status == 401 || status == 403: finish(.revoked)
                default: break  // offline, rate limited: the lease still has time
                }
            } catch {}
        }
    }

    /// Ends this attachment once; false when it already ended.
    @discardableResult
    func finish(_ why: TerminalClose) -> Bool {
        let first = cond.withLock { () -> Bool in
            defer {
                finished = true
                cond.broadcast()
            }
            return !finished
        }
        guard first else { return false }
        renewal?.cancel()
        socket.close()
        feed.yield(.closed(why))
        feed.finish()
        return true
    }
}
