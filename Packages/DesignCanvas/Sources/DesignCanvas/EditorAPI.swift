import DesignEngine
import Foundation

/// What the editor chrome (V3-04, SwiftUI in `Features/Design`) asks of the canvas: reads as JSON text (the chrome decodes
/// them, so this package stays free of `Features`) and writes as edit ops (T12 op list, one undo step per call). Every
/// write wakes the render loop, relays the local update to the Core and tells `onChange`.
extension DesignCanvasNSView {
    /// The document's nodes as a JSON array of `{id, type, parent, order, name, hidden}`; nil while the engine cannot list them.
    public func editorTree() -> Data? { engine.tree() }
    /// One node as JSON (`{id, type, parent, order, name, props, text}`), or nil.
    public func editorNode(_ id: String) -> String? { engine.node(id) }
    public func editorSelection() -> [String] { engine.selection() }
    /// Makes `ids` the selection (false: this engine cannot select by id yet).
    @discardableResult public func editorSelect(_ ids: [String]) -> Bool {
        let ok = engine.select(ids)
        if ok { changed() }
        return ok
    }
    /// A JSON array of ops, applied all or nothing as one undo step; false when the engine refused it.
    @discardableResult public func editorEdit(_ json: String) -> Bool {
        let r = engine.editResult(json)
        lastEditTooLarge = r == .tooLarge
        if r == .applied {
            changed()
        } else if r == .tooLarge {
            sync?.probe()
            onChange?()
        }
        return r == .applied
    }
    /// The last `editorEdit` was refused as too large for one update (or because an unsent update is stuck).
    public var editorLastEditTooLarge: Bool { lastEditTooLarge }
    /// An unsent edit can never go out: "This design stopped syncing — reopen it (unsent edits are lost)".
    public var editorSyncStuck: Bool { sync?.stuck ?? false }
    public func editorUndo() { undo(redo: false) }
    public func editorRedo() { undo(redo: true) }
    public func editorFitSelection() {
        de_fit_selection(engine.h)
        loop.wake()
    }
    /// Other peers' presence as JSON `{"<client>": {...}}`.
    public func editorPeers() -> Data? { engine.presencePeers() }
    /// This device's presence (a JSON object, at most 4 KiB), sent to the Core's relay with the next update.
    public func editorSetPresence(_ json: String) {
        guard engine.presenceSet(json) else { return }
        sync?.flushPresence()
    }
    /// 1 while a text node is being edited on the canvas.
    public var editorTextActive: Bool { engine.textActive }
    /// The design system's tokens as a JSON array of `{name, kind}`; nil while the engine cannot list them.
    public func editorTokens() -> Data? { engine.tokens() }

    private func changed() {
        loop.wake(input: true)
        sync?.flush()
        onChange?()
    }
}
