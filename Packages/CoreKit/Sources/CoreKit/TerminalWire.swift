import Foundation

/// What one frame of the terminal WebSocket means (protocol v2 on stream 0, spec: terminal protocol §2). Output and snapshot
/// data arrive base64 and leave here as bytes.
public enum TerminalFrame: Sendable, Equatable {
    /// First frame: the terminal as the runner sees it. `seq` is the next byte offset.
    case opened(TerminalOpened)
    case output(Data)
    /// The screen now; output resumes at `seq`.
    case snapshot(seq: UInt64, data: Data)
    /// The child ended: `exit_code`, or the signal's name (`host_lost` when the host died with it).
    case exit(code: Int32?, signal: String?)
    case error(code: String, message: String)
    case credit(Int)
    case close(reason: String?)
    /// A kind or control type from a newer Core: skipped.
    case unknown

    /// Decodes one text frame. nil when it is not a frame at all.
    public static func decode(_ data: Data) -> TerminalFrame? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let kind = obj["kind"] as? String
        else { return nil }
        let p = obj["payload"] as? [String: Any] ?? [:]
        switch kind {
        case "output":
            guard let text = p["data"] as? String, let bytes = Data(base64Encoded: text) else { return .unknown }
            return .output(bytes)
        case "control":
            switch p["type"] as? String {
            case "opened":
                let size = p["size"] as? [String: Any]
                return .opened(
                    TerminalOpened(
                        state: p["state"] as? String ?? "running", rows: (size?["rows"] as? Int) ?? 0,
                        cols: (size?["cols"] as? Int) ?? 0, seq: (p["seq"] as? NSNumber)?.uint64Value ?? 0,
                        exitCode: ((p["exit"] as? [String: Any])?["exit_code"] as? Int).map(Int32.init),
                        exitSignal: (p["exit"] as? [String: Any])?["signal"] as? String))
            case "snapshot":
                guard let text = p["data"] as? String, let bytes = Data(base64Encoded: text) else { return .unknown }
                return .snapshot(seq: (p["seq"] as? NSNumber)?.uint64Value ?? 0, data: bytes)
            default: return .unknown
            }
        case "result":
            return .exit(code: (p["exit_code"] as? Int).map(Int32.init), signal: p["signal"] as? String)
        case "error":
            return .error(code: p["code"] as? String ?? "internal", message: p["message"] as? String ?? "")
        case "credit": return .credit((p["bytes"] as? Int) ?? 0)
        case "close": return .close(reason: p["reason"] as? String)
        default: return .unknown
        }
    }
}

public struct TerminalOpened: Sendable, Equatable {
    /// `created`, `running`, `exited`: the runner's word.
    public var state: String
    public var rows: Int
    public var cols: Int
    public var seq: UInt64
    public var exitCode: Int32?
    public var exitSignal: String?
    public init(
        state: String, rows: Int, cols: Int, seq: UInt64, exitCode: Int32? = nil, exitSignal: String? = nil
    ) {
        self.state = state
        self.rows = rows
        self.cols = cols
        self.seq = seq
        self.exitCode = exitCode
        self.exitSignal = exitSignal
    }
}

/// The frames this client sends. `seq` counts the frames of this socket, from 0.
enum TerminalOut {
    static func frame(_ kind: String, seq: UInt64, _ payload: [String: Any]) -> Data {
        let obj: [String: Any] = ["stream_id": 0, "kind": kind, "seq": seq, "payload": payload]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
    static func input(_ bytes: Data, seq: UInt64) -> Data {
        frame("output", seq: seq, ["data": bytes.base64EncodedString()])
    }
    static func resize(rows: Int, cols: Int, seq: UInt64) -> Data {
        frame("control", seq: seq, ["type": "resize", "rows": rows, "cols": cols])
    }
    static func signal(_ name: String, seq: UInt64) -> Data {
        frame("control", seq: seq, ["type": "signal", "signal": name])
    }
    static func credit(_ bytes: Int, seq: UInt64) -> Data { frame("credit", seq: seq, ["bytes": bytes]) }
}

/// Credit accounting for one terminal socket (spec §3). The Core sends output as fast as the socket takes it and drops a slow
/// reader to a snapshot, so the client keeps its own window: it counts the bytes it has received and not yet drawn, stops
/// reading from the socket past `highWater` (TCP then slows the Core's send), and hands credit back as it draws. A snapshot
/// counts like output and may overdraw the window (a screen larger than the window still arrives); only the next read waits.
public struct TerminalFlow: Sendable, Equatable {
    /// The window both sides start with (spec §3.1).
    public static let window = 64 * 1024
    /// Read no more while this many bytes wait to be drawn.
    public static let highWater = 4 * window
    /// Credit goes back in steps of this size, not one frame at a time.
    public static let grantStep = window / 2

    /// Received and not yet drawn.
    public private(set) var pending = 0
    private var owed = 0
    public init() {}

    public var wantsMore: Bool { pending < Self.highWater }

    public mutating func received(_ bytes: Int) { pending += max(0, bytes) }

    /// The renderer drew `bytes`. Returns the credit to send now: 0, or at least `grantStep`.
    public mutating func drawn(_ bytes: Int) -> Int {
        let n = min(max(0, bytes), pending)
        pending -= n
        owed += n
        guard owed >= Self.grantStep else { return 0 }
        defer { owed = 0 }
        return owed
    }
}

/// Where the next byte comes from: `after` for `?after=` on a reattach (spec §1: seq is a byte offset). A snapshot moves it to
/// the snapshot's seq; output moves it on.
public struct TerminalCursor: Sendable, Equatable {
    public private(set) var offset: UInt64
    /// Set once a snapshot arrived on this socket: the screen was repainted, not replayed.
    public private(set) var repainted = false
    public init(after: UInt64) { offset = after }

    public mutating func apply(_ frame: TerminalFrame) {
        switch frame {
        case .output(let d): offset += UInt64(d.count)
        case .snapshot(let seq, _):
            offset = seq
            repainted = true
        default: break
        }
    }
}
