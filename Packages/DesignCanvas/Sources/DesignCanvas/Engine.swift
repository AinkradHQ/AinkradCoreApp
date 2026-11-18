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
        /// No thread could start for the update (`DE_ERR_BUSY`): nothing changed, ask the Core for it again later.
        case busy
        /// The update is over what the engine takes (`DE_ERR_TOO_LARGE`): it is dropped, and the sync asks for a fresh state.
        case tooLarge
    }

    /// What `outbox()` found.
    public enum Outbox: Sendable, Equatable {
        /// Nothing waits to be sent.
        case empty
        case update(Data)
        /// The oldest unsent edit is over what the Core takes (`DE_ERR_TOO_LARGE`): it can never be sent and the engine
        /// refuses new edits. The design must be reopened; unsent edits are lost.
        case stuck
    }

    /// What `edit` did.
    public enum EditResult: Sendable, Equatable {
        case applied
        /// The change was refused and nothing changed.
        case refused
        /// The change (or the queue behind a stuck update) is over what one update takes (`DE_ERR_TOO_LARGE`).
        case tooLarge
        /// No thread could start (`DE_ERR_BUSY`): nothing changed, try again.
        case busy
    }

    @discardableResult public func apply(_ update: Data, to target: Target = .doc) -> Applied {
        let rc = update.withUnsafeBytes {
            de_sync_apply(h, target.rawValue, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        switch rc {
        case DE_OK: return .applied
        case DE_ERR_RESET: return .reset
        case DE_ERR_HALTED: return .halted
        case DE_ERR_BUSY: return .busy
        case DE_ERR_TOO_LARGE: return .tooLarge
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
    /// Local edits not sent yet, drained; `.stuck` when one can never go out.
    public func outbox() -> Outbox {
        let (rc, d) = fetch { de_sync_outbox(h, $0, $1, $2) }
        if rc == DE_ERR_TOO_LARGE { return .stuck }
        guard rc == DE_OK, let d, !d.isEmpty else { return .empty }
        return .update(d)
    }
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
    /// This device's presence JSON (cursor, selection, label), at most 4 KiB.
    @discardableResult func presenceSet(_ json: String) -> Bool {
        let b = Array(json.utf8)
        return de_presence_set(h, b, b.count) == DE_OK
    }
    /// Other peers' presence as JSON `{"<client>": {...}}`.
    func presencePeers() -> Data? { read { de_presence_peers(h, $0, $1, $2) } }

    // The editor chrome's reads and its select: the layers panel, the token pickers and click-to-select in the layers panel.
    /// The nodes as `[{id,type,parent,order,name,hidden}]` (`de_tree`).
    func tree() -> Data? { read { de_tree(h, $0, $1, $2) } }
    /// The linked design system's tokens as `[{name,kind}]` (`de_tokens`).
    func tokens() -> Data? { read { de_tokens(h, $0, $1, $2) } }
    /// Replaces the selection with `ids`; false when the engine refused (an id the document lacks, or too many ids).
    func select(_ ids: [String]) -> Bool {
        guard let json = try? JSONEncoder().encode(ids) else { return false }
        return json.withUnsafeBytes { de_select(h, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) } == DE_OK
    }

    /// Applies a JSON array of edit ops (one undo step).
    @discardableResult public func edit(_ json: String) -> Bool { editResult(json) == .applied }

    public func editResult(_ json: String) -> EditResult {
        let b = Array(json.utf8)
        switch de_edit(h, b, b.count) {
        case DE_OK: return .applied
        case DE_ERR_TOO_LARGE: return .tooLarge
        case DE_ERR_BUSY: return .busy
        default: return .refused
        }
    }

    /// Calls an out-buffer function, growing the buffer once to the size it asks for.
    private func read(_ f: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>?) -> Int32) -> Data? {
        let (rc, d) = fetch(f)
        return rc == DE_OK ? d : nil
    }

    /// The same, with the engine's code kept (the sync reads `DE_ERR_TOO_LARGE`).
    private func fetch(_ f: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>?) -> Int32) -> (Int32, Data?)
    {
        var cap = 16 * 1024
        var rc: Int32 = DE_ERR_SMALL_BUFFER
        for _ in 0..<2 {
            var buf = [UInt8](repeating: 0, count: cap)
            var n = 0
            rc = buf.withUnsafeMutableBufferPointer { f($0.baseAddress, cap, &n) }
            if rc == DE_OK { return (rc, Data(buf[0..<n])) }
            guard rc == DE_ERR_SMALL_BUFFER, n > cap else { return (rc, nil) }
            cap = n
        }
        return (rc, nil)
    }
}
