import AppKit
import DesignEngine
import Foundation

/// The canvas as the editor tools (clipboard, arrange, zoom, pages, presence) need it: small reads and camera moves, each
/// one engine call. Kept apart from `EditorAPI` so the two grow without touching each other.
extension DesignCanvasNSView {
    /// The people and AI sessions on the canvas: `[{"peer","label","kind":"person"|"ai","following"}]`, oldest first.
    public func editorPresenceList() -> Data? { engine.read { de_presence_list(engine.h, $0, $1, $2) } }

    /// Follows a peer (the camera shows what it sees until the viewer pans, zooms or fits); an empty id stops. False when
    /// the peer is gone.
    @discardableResult public func editorFollow(_ peer: String) -> Bool {
        let b = Array(peer.utf8)
        let ok = de_follow(engine.h, b, b.count) == DE_OK
        loop.wake()
        onChange?()
        return ok
    }

    /// Shows page `index` (its place among the design's pages) framed in the view.
    public func editorSetPage(_ index: Int) {
        de_set_page(engine.h, UInt32(max(0, index)))
        de_fit(engine.h)
        loop.wake()
        onChange?()
    }

    /// Zooms by `factor` about the middle of the view; the engine keeps it inside its limits.
    public func editorZoom(by factor: Double) {
        guard factor > 0, factor.isFinite else { return }
        zoom(by: CGFloat(factor), at: CGPoint(x: bounds.midX, y: bounds.midY))
        de_gesture_end(engine.h, reduceMotion ? 1 : 0)
        loop.wake()
    }

    /// Zooms to `scale` (1 = 100%) about the middle of the view.
    public func editorZoom(to scale: Double) {
        guard let z = editorCamera?.zoom, z > 0 else { return }
        editorZoom(by: scale / z)
    }

    /// Frames every artboard of the page.
    public func editorFitAll() { fit() }

    #if DEBUG
    /// Debug only: a presence message as the Core's socket relays it (`{"peer","conn","label","cursor"}`), for the
    /// snapshot walk: the engine draws the cursor and the list shows the person.
    @discardableResult public func editorDebugPresence(_ json: String) -> Bool {
        let b = Array(json.utf8)
        let ok = de_presence_remote(engine.h, b, b.count) == DE_OK
        loop.wake()
        onChange?()
        return ok
    }
    #endif
}
