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

    // MARK: clipboard, group, components: the engine does the work, each one is a single undo step

    /// The clipboard JSON (`{"format": "ainkrad-design/1", …}`) of `ids`, or of the selection when nil; nil when the engine
    /// refuses (nothing selected, a page, too large).
    public func editorCopy(_ ids: [String]? = nil) -> Data? {
        let json = ids.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        return json.withUnsafeBytes { p in
            engine.read { de_copy(engine.h, p.bindMemory(to: UInt8.self).baseAddress, json.count, $0, $1, $2) }
        }
    }

    /// Pastes clipboard JSON into `parent` (nil: the page) with new ids and selects it. With `at` the pasted bounds' top-left
    /// goes to that view point; without it the layers keep their place.
    @discardableResult public func editorPaste(_ json: Data, parent: String? = nil, at: CGPoint? = nil) -> Bool {
        let p = Array((parent ?? "").utf8)
        let rc = json.withUnsafeBytes {
            de_paste(
                engine.h, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, p, p.count, Float(at?.x ?? 0),
                Float(at?.y ?? 0), at == nil ? 0 : 1)
        }
        return done(rc)
    }

    @discardableResult public func editorGroup() -> Bool { done(de_group(engine.h)) }
    @discardableResult public func editorUngroup() -> Bool { done(de_ungroup(engine.h)) }
    /// ⌘D: copies of the selection beside it, selected.
    @discardableResult public func editorDuplicate() -> Bool { done(de_key(engine.h, UInt32(DE_KEY_DUPLICATE), 0)) }
    @discardableResult public func editorComponentCreate() -> Bool { done(de_component_create(engine.h)) }
    @discardableResult public func editorInstanceDetach() -> Bool { done(de_instance_detach(engine.h)) }

    /// An instance of `component` (`"<doc>/<node>"`, or a bare id of this design) with its top-left at view point `at`.
    @discardableResult public func editorInstanceInsert(_ component: String, at: CGPoint) -> Bool {
        let c = Array(component.utf8)
        return done(de_instance_insert(engine.h, c, c.count, Float(at.x), Float(at.y)))
    }

    private func done(_ rc: Int32) -> Bool {
        if rc == DE_OK { changed() }
        return rc == DE_OK
    }

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
