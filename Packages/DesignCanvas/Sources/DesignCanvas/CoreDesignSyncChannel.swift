import Foundation

/// One WebSocket message as the Core's sync socket sends it: binary frames carry updates, text frames are presence JSON.
public enum DesignSocketFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// The open socket of one design. The app wraps CoreKit's signed `CoreSocket` in it; tests bring a fake.
public protocol DesignSocket: Sendable {
    func receive() async throws -> DesignSocketFrame
    func send(_ frame: DesignSocketFrame) async throws
    func cancel()
    /// The close code the Core sent, 0 when none (read after `receive` threw).
    var closeCode: Int { get }
}

/// The Core's binary frames on `GET /modules/design/v1/docs/{d}/sync` (AinkradCore `modules/design/module/src/ws.rs`).
///   client to Core  `01` + update
///   Core to client  `01` + seq (u64 BE) + update, `02` + seq + whole state, `03` + seq (the client's update is stored)
public enum DesignSyncWire {
    public enum Incoming: Equatable, Sendable {
        case update(seq: UInt64, Data)
        case snapshot(seq: UInt64, Data)
        case ack(seq: UInt64)
    }

    public static func encode(update: Data) -> Data { Data([0x01]) + update }

    /// Nil for a frame this protocol does not have (unknown tag, short header).
    public static func decode(_ frame: Data) -> Incoming? {
        let b = [UInt8](frame)
        guard b.count >= 9 else { return nil }
        let seq = b[1..<9].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let body = Data(b[9...])
        switch b[0] {
        case 0x01: return .update(seq: seq, body)
        case 0x02: return .snapshot(seq: seq, body)
        case 0x03 where b.count == 9: return .ack(seq: seq)
        default: return nil
        }
    }
}

/// `DesignSyncChannel` over the Core's sync socket. It keeps, per design, the highest seq it applied (the next connect
/// resumes from it with `Last-Update-Seq`) and the updates the Core has not acknowledged (resent on the next connect:
/// applying a repeat is harmless). The Core has no state-vector exchange, so the first one `DesignSync` sends on a
/// connection is dropped; a later one means "send everything again": the socket is closed and the next connect carries no
/// cursor, so the Core answers with a snapshot. Presence rides the text frames: a peer's message is labelled and handed on as `.awareness`, and this device's goes out as one.
public actor CoreDesignSyncChannel: DesignSyncChannel {
    /// Opens the socket for a design, resuming after `lastSeq` when there is one.
    public typealias Opener = @Sendable (_ doc: String, _ lastSeq: UInt64?) async throws -> any DesignSocket

    /// Close code 4412: the update depends on state the Core lacks; reconnect without a cursor.
    static let resyncCode = 4412

    private let opener: Opener
    private var cursor: [String: UInt64] = [:]
    private var unacked: [String: [Data]] = [:]
    private var sockets: [String: any DesignSocket] = [:]
    private var vectorSeen: Set<String> = []
    private var generation: [String: Int] = [:]

    public init(opener: @escaping Opener) { self.opener = opener }

    /// The seq the next connect resumes from.
    public func lastSeq(_ doc: String) -> UInt64? { cursor[doc] }

    public func open(doc: String) async throws -> AsyncThrowingStream<DesignSyncMessage, any Error> {
        let socket = try await opener(doc, cursor[doc])
        let mine = (generation[doc] ?? 0) + 1
        generation[doc] = mine
        sockets[doc] = socket
        vectorSeen.remove(doc)
        for u in unacked[doc] ?? [] { try? await socket.send(.binary(DesignSyncWire.encode(update: u))) }
        let (stream, out) = AsyncThrowingStream<DesignSyncMessage, any Error>.makeStream()
        let pump = Task { [weak self] in
            do {
                while true {
                    let frame = try await socket.receive()
                    if case .text(let t) = frame {
                        if let m = Self.relay(t) { out.yield(.awareness(m)) }
                        continue
                    }
                    guard case .binary(let data) = frame else { continue }
                    switch DesignSyncWire.decode(data) {
                    case .update(let seq, let body), .snapshot(let seq, let body):
                        await self?.applied(doc, seq)
                        out.yield(.update(body))
                    case .ack: await self?.acked(doc)
                    case nil: throw DesignSyncFailure.badFrame
                    }
                }
            } catch {
                await self?.ended(doc, mine, socket.closeCode)
                out.finish(throwing: error)
            }
        }
        out.onTermination = { _ in
            pump.cancel()
            socket.cancel()
        }
        return stream
    }

    public func send(_ message: DesignSyncMessage, doc: String) async throws {
        switch message {
        case .update(let u):
            unacked[doc, default: []].append(u)
            try await sockets[doc]?.send(.binary(DesignSyncWire.encode(update: u)))
        case .stateVector:
            guard vectorSeen.insert(doc).inserted else {
                cursor[doc] = nil
                sockets[doc]?.cancel()
                return
            }
        case .awareness(let a):
            try await sockets[doc]?.send(.text(String(decoding: a, as: UTF8.self)))
        }
    }

    /// A peer's presence text with the label the engine shows: the Core says who (`person:d_…`, `session:as_…`), not their
    /// name. Hostile text: anything that is not a small JSON object is dropped.
    static func relay(_ text: String) -> Data? {
        guard text.utf8.count <= 4096, var o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        else { return nil }
        if o["gone"] == nil, let peer = o["peer"] as? String {
            o["label"] = peer.hasPrefix("session:") ? "An AI session" : "Another device"
        }
        return try? JSONSerialization.data(withJSONObject: o)
    }

    private func applied(_ doc: String, _ seq: UInt64) { cursor[doc] = max(cursor[doc] ?? 0, seq) }
    private func acked(_ doc: String) { if !(unacked[doc]?.isEmpty ?? true) { unacked[doc]?.removeFirst() } }
    /// A socket that was already replaced by a newer connect leaves that one alone.
    private func ended(_ doc: String, _ gen: Int, _ code: Int) {
        if code == Self.resyncCode { cursor[doc] = nil }
        if gen == generation[doc] { sockets[doc] = nil }
    }
}

public enum DesignSyncFailure: Error, Equatable { case badFrame }
