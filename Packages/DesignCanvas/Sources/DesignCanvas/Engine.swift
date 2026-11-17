import DesignEngine
import Foundation

/// One engine (`de_*` handle) for one design document. The engine is a handle, never a pointer: a stale handle is an error
/// code, and every call locks that engine's own mutex in Rust, so the main thread (input, sync) and the render thread
/// (frames) may both call it. Hence `Sendable` with only a `let`.
public final class Engine: Sendable {
    let h: UInt64

    /// Nil when the id is not a design id or the engine table is full.
    public init?(doc: String) {
        var out: UInt64 = 0
        let bytes = Array(doc.utf8)
        guard de_engine_new(bytes, bytes.count, &out) == DE_OK else { return nil }
        h = out
    }

    deinit { de_engine_free(h) }

    // MARK: sync (T3): the engine's local yrs doc; Swift only relays bytes

    public enum Target: UInt32, Sendable {
        case doc = 0
        case system = 1
    }

    public enum Applied: Sendable {
        case applied, refused
        /// The update failed inside yrs and the engine reset the doc (`DE_ERR_RESET`): resync from the Core.
        case reset
        /// Three resets in a minute (`DE_ERR_HALTED`): remote updates are no longer applied; open the design again.
        case halted
    }

    @discardableResult public func apply(_ update: Data, to target: Target = .doc) -> Applied {
        let rc = update.withUnsafeBytes {
            de_sync_apply(h, target.rawValue, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        switch rc {
        case DE_OK: return .applied
        case DE_ERR_RESET: return .reset
        case DE_ERR_HALTED: return .halted
        default: return .refused
        }
    }
    public func stateVector() -> Data? { read { de_sync_state_vector(h, $0, $1, $2) } }
    /// What a peer at state vector `sv` lacks (empty `sv`: the whole state).
    public func diff(_ sv: Data) -> Data? {
        sv.withUnsafeBytes { s in
            read { de_sync_diff(h, s.bindMemory(to: UInt8.self).baseAddress, s.count, $0, $1, $2) }
        }
    }
    /// Local edits not sent yet, drained (nil or empty: nothing to send).
    public func outbox() -> Data? { read { de_sync_outbox(h, $0, $1, $2) } }
    func presenceApply(_ b: Data) {
        _ = b.withUnsafeBytes { de_presence_apply(h, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
    }
    func presenceEncode() -> Data? { read { de_presence_encode(h, $0, $1, $2) } }

    // MARK: fonts + assets

    /// A library font by sha256; nil `sha` sets the face `system` draws with.
    @discardableResult func addFont(_ sha: String?, _ data: Data) -> Bool {
        let key = Array((sha ?? "").utf8)
        return data.withUnsafeBytes {
            de_font_add(h, key, key.count, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        } == DE_OK
    }
    @discardableResult func addAsset(_ sha: String, _ data: Data) -> Bool {
        let key = Array(sha.utf8)
        return data.withUnsafeBytes {
            de_asset_add(h, key, key.count, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        } == DE_OK
    }
    /// Hashes the renderer wanted and did not have.
    func missingAssets() -> [String] {
        guard let d = read({ de_missing_assets(h, $0, $1, $2) }) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: d)) ?? []
    }

    // MARK: queries

    public func selection() -> [String] {
        guard let d = read({ de_selection(h, $0, $1, $2) }) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: d)) ?? []
    }
    /// The node id under a view point, if any.
    public func hit(_ x: Float, _ y: Float) -> String? {
        struct Hit: Decodable { let id: String }
        guard let d = read({ de_hit(h, x, y, $0, $1, $2) }) else { return nil }
        return (try? JSONDecoder().decode(Hit.self, from: d))?.id
    }
    /// One node as JSON for the inspector, nil when the document has no such node.
    public func node(_ id: String) -> String? {
        let k = Array(id.utf8)
        guard let d = read({ de_node(h, k, k.count, $0, $1, $2) }), let s = String(data: d, encoding: .utf8),
            s != "null"
        else { return nil }
        return s
    }
    /// Applies a JSON array of edit ops (one undo step).
    @discardableResult public func edit(_ json: String) -> Bool {
        let b = Array(json.utf8)
        return de_edit(h, b, b.count) == DE_OK
    }

    /// Calls an out-buffer function, growing the buffer once to the size it asks for.
    private func read(_ f: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>?) -> Int32) -> Data? {
        var cap = 16 * 1024
        for _ in 0..<2 {
            var buf = [UInt8](repeating: 0, count: cap)
            var n = 0
            let rc = buf.withUnsafeMutableBufferPointer { f($0.baseAddress, cap, &n) }
            if rc == DE_OK { return Data(buf[0..<n]) }
            guard rc == DE_ERR_SMALL_BUFFER, n > cap else { return nil }
            cap = n
        }
        return nil
    }
}
