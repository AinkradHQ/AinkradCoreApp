import AppKit
import DesignEngine
import Metal
import QuartzCore
import SwiftUI

// Security model (T4, Sec): the engine is reached only through `Engine`'s handle; every buffer handed to it is a Swift
// array or `Data` whose pointer and length come from the same value, and every out-buffer call goes through
// `Engine.read`, which never trusts the engine's size beyond one regrowth. The Metal device, queue and drawable textures
// outlive every draw: the loop is stopped (and the engine detached) before the view lets them go. No engine call runs
// AppKit code, and only the render thread draws. Asset bytes reach the engine only when the Core marked them `ok`.

/// The canvas (V3-02): a layer-backed `NSView` whose `CAMetalLayer` the engine draws into from `FrameLoop`'s render
/// thread. Native input goes straight into the engine's interaction calls on the main thread: trackpad scroll (with the
/// system's momentum) pans and rubber-bands, pinch and ⌘-scroll zoom (pinch keeps a short glide), the pointer selects,
/// moves and resizes, keys delete, nudge, duplicate, undo and fit. Reduce Motion drops every glide: no scroll momentum,
/// no pinch glide, and the rubber band snaps back at once.
public final class DesignCanvasNSView: NSView {
    public let engine: Engine
    let device: any MTLDevice
    let loop: FrameLoop
    var sync: DesignSync?
    var system: DesignSync?
    var fetcher: AssetFetcher?
    /// Called on the main thread when the document or the selection may have changed (a remote update, a pointer press or
    /// release, a key, an undo, an edit from the chrome): the layers panel and inspector read the engine again.
    public var onChange: (() -> Void)?
    /// Presenting (a mockup or a prototype): clicks report the node under them instead of editing, scroll and pinch are
    /// off. Nil while editing.
    public var presentTap: ((String?) -> Void)?
    /// The editor chrome's first look at a key (editor commands: copy, group, zoom…). True: it took the key. Never asked
    /// while a text is being edited.
    public var keyHandler: (@MainActor (NSEvent) -> Bool)?
    /// The tool to give back when Space is let go (Space held = the hand, whatever the tool).
    var spaceRestore: Int32?
    private var fitted = false
    var lastEditTooLarge = false
    var reduceMotion = false {
        didSet {
            let on = reduceMotion
            loop.state.withLock { $0.reduceMotion = on }
        }
    }
    var night = false {
        didSet {
            if night != oldValue {
                de_set_theme(engine.h, night ? 1 : 0)
                loop.wake()
            }
        }
    }

    public var frameLog: FrameLog { loop.log }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    public init?(engine: Engine) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.engine = engine
        self.device = device
        loop = FrameLoop(engine: engine, queue: queue)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let dev = Unmanaged.passUnretained(device).toOpaque()
        let q = Unmanaged.passUnretained(queue).toOpaque()
        guard de_attach_metal(engine.h, dev, q) == DE_OK else { return nil }
        if let sf = try? Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/SFNS.ttf")) {
            engine.addFont(nil, sf)  // `system` = SF Pro (plan Q2)
        }
        loop.start(layer: metalLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("unused") }

    /// Stops the render thread and drops the GPU context; the engine (document, camera) stays.
    func tearDown() {
        sync?.stop()
        system?.stop()
        loop.stop()
        de_detach(engine.h)
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = device
        l.pixelFormat = .bgra8Unorm
        l.framebufferOnly = false  // Skia samples the target (backdrop blur)
        l.maximumDrawableCount = 3
        return l
    }

    // MARK: size

    public override func layout() {
        super.layout()
        syncSize()
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSize()
    }

    private func syncSize() {
        let scale = window?.backingScaleFactor ?? 2
        guard bounds.width > 0, bounds.height > 0 else { return }
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        de_resize(engine.h, Float(bounds.width), Float(bounds.height), Float(scale))
        if !fitted, engine.diff(Data()).map({ $0.count > 2 }) == true { fit() }
        loop.wake()
    }

    /// Frames the page once, when the first content arrives.
    func contentArrived() {
        if !fitted, bounds.width > 0 { fit() }
        loop.wake()
        onChange?()
    }

    func fit() {
        fitted = true
        de_fit(engine.h)
        loop.wake()
    }

    // MARK: scroll + pinch

    public override func scrollWheel(with e: NSEvent) {
        if presentTap != nil { return }  // presenting: the screen stays put
        let p = point(e)
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) {
            let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 8
            zoom(by: exp(d * 0.01), at: p)
            if e.phase.contains(.ended) || e.phase.isEmpty { de_gesture_end(engine.h, reduceMotion ? 1 : 0) }
            return
        }
        let momentum = !e.momentumPhase.isEmpty
        if momentum && reduceMotion { return }  // no glide after lift
        let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10
        if e.scrollingDeltaX != 0 || e.scrollingDeltaY != 0 { pan(e.scrollingDeltaX * k, e.scrollingDeltaY * k) }
        // The pan settles inside the bounds when the fingers lift with no glide to follow, when the glide ends, or after
        // a mouse wheel notch (no phases). A glide that starts after `ended` cancels the settle (de_scroll does).
        let ended =
            e.phase.contains(.ended) || e.phase.contains(.cancelled) || e.momentumPhase.contains(.ended)
            || (e.phase.isEmpty && e.momentumPhase.isEmpty)
        if ended {
            de_gesture_end(engine.h, reduceMotion ? 1 : 0)
            loop.wake()
        }
    }

    private var pinchRate = 0.0
    private var pinchStamp = 0.0

    public override func magnify(with e: NSEvent) {
        if presentTap != nil { return }
        let p = point(e)
        if e.phase.contains(.began) {
            loop.state.withLock { $0.zoomRate = 0 }
            pinchRate = 0
            pinchStamp = e.timestamp
        }
        let f = 1 + e.magnification
        if f > 0 { zoom(by: f, at: p) }
        let dt = max(e.timestamp - pinchStamp, 1.0 / 240)
        pinchStamp = e.timestamp
        pinchRate = pinchRate * 0.5 + (log(max(f, 0.01)) / dt) * 0.5
        if e.phase.contains(.ended) || e.phase.contains(.cancelled) {
            if !reduceMotion, abs(pinchRate) > 0.3 {
                let r = max(-4, min(4, pinchRate))
                loop.state.withLock {
                    $0.zoomRate = r
                    $0.zoomAt = p
                }
            } else {
                de_gesture_end(engine.h, reduceMotion ? 1 : 0)
            }
            loop.wake()
        }
    }

    func pan(_ dx: CGFloat, _ dy: CGFloat) {
        de_scroll(engine.h, Float(dx), Float(dy))
        loop.wake(input: true)
    }

    func zoom(by f: CGFloat, at p: CGPoint) {
        de_magnify(engine.h, Float(f), Float(p.x), Float(p.y))
        loop.wake(input: true)
    }

    // MARK: pointer

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }

    public override func mouseDown(with e: NSEvent) {
        // Presenting: a click is a tap on the screen (prototype links), never an edit.
        if let tap = presentTap {
            let p = point(e)
            tap(engine.hit(Float(p.x), Float(p.y)))
            return
        }
        window?.makeFirstResponder(self)
        // A double-click on a text node edits it (with the select tool; the text tool opens a session itself).
        if e.clickCount == 2, engine.tool == DE_TOOL_SELECT, !engine.textActive {
            let p = point(e)
            if de_text_begin(engine.h, Float(p.x), Float(p.y)) == DE_OK {
                textChanged()
                return
            }
        }
        pointer(DE_POINTER_DOWN, e)
    }
    public override func mouseDragged(with e: NSEvent) { if presentTap == nil { pointer(DE_POINTER_MOVE, e) } }
    public override func mouseMoved(with e: NSEvent) { if presentTap == nil { pointer(DE_POINTER_MOVE, e) } }
    public override func mouseUp(with e: NSEvent) {
        if presentTap != nil { return }
        pointer(DE_POINTER_UP, e)
        sync?.flush()
    }
    public override func cursorUpdate(with e: NSEvent) { updateCursor(point(e)) }

    func pointer(_ phase: Int32, _ e: NSEvent) { pointer(phase, at: point(e), mods: Self.mods(e.modifierFlags)) }

    func pointer(_ phase: Int32, at p: CGPoint, mods: UInt32 = 0) {
        de_pointer(engine.h, UInt32(phase), Float(p.x), Float(p.y), mods)
        updateCursor(p)
        loop.wake(input: true)
        if phase != DE_POINTER_MOVE { onChange?() }
    }

    private func updateCursor(_ p: CGPoint) {
        let c = de_cursor(engine.h, Float(p.x), Float(p.y))
        Self.cursor(c).set()
    }

    static func cursor(_ c: Int32) -> NSCursor {
        switch c {
        case DE_CURSOR_RESIZE_NS: return .resizeUpDown
        case DE_CURSOR_RESIZE_EW: return .resizeLeftRight
        case DE_CURSOR_RESIZE_NWSE, DE_CURSOR_RESIZE_NESW:
            if #available(macOS 15, *) {
                return .frameResize(position: c == DE_CURSOR_RESIZE_NWSE ? .topLeft : .topRight, directions: .all)
            }
            return .crosshair
        case DE_CURSOR_CROSSHAIR: return .crosshair
        case DE_CURSOR_GRAB: return .openHand
        case DE_CURSOR_GRABBING: return .closedHand
        case DE_CURSOR_TEXT: return .iBeam
        default: return .arrow
        }
    }

    static func mods(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: Int32 = 0
        if f.contains(.shift) { m |= DE_MOD_SHIFT }
        if f.contains(.control) { m |= DE_MOD_CONTROL }
        if f.contains(.option) { m |= DE_MOD_OPTION }
        if f.contains(.command) { m |= DE_MOD_COMMAND }
        return UInt32(m)
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    // MARK: keys

    /// Delete, Escape and the arrows (nudge; Shift: 10 pt).
    public override func keyDown(with e: NSEvent) {
        // Editing text: every key goes through the input system (typing, the IME, the caret keys; Escape ends it).
        if engine.textActive {
            interpretKeyEvents([e])
            return
        }
        let f = e.modifierFlags.intersection([.command, .control, .option])
        if e.keyCode == 49, f.isEmpty {
            // Space held: the hand tool until it is let go, with any tool (a repeat changes nothing).
            if !e.isARepeat, spaceRestore == nil, presentTap == nil {
                spaceRestore = engine.tool
                editorSetTool(Int(DE_TOOL_HAND))
            }
            return
        }
        if keyHandler?(e) == true { return }
        if f.isEmpty, let c = e.charactersIgnoringModifiers?.lowercased(), let t = Self.toolKey(c) {
            editorSetTool(Int(t))
            return
        }
        let key: Int32? =
            switch e.keyCode {
            case 36, 76: DE_KEY_ENTER
            case 51, 117: DE_KEY_DELETE
            case 53: DE_KEY_ESCAPE
            case 123: DE_KEY_LEFT
            case 124: DE_KEY_RIGHT
            case 125: DE_KEY_DOWN
            case 126: DE_KEY_UP
            default: nil
            }
        guard let key else { return super.keyDown(with: e) }
        send(key: key, mods: Self.mods(e.modifierFlags))
    }

    public override func keyUp(with e: NSEvent) {
        if e.keyCode == 49 { endSpacePan() } else { super.keyUp(with: e) }
    }

    public override func resignFirstResponder() -> Bool {
        endSpacePan()
        return super.resignFirstResponder()
    }

    func endSpacePan() {
        guard let t = spaceRestore else { return }
        spaceRestore = nil
        editorSetTool(Int(t))
        onChange?()
    }

    /// ⌘D duplicate, ⌘Z / ⇧⌘Z undo and redo, ⌘0 fit the page, ⌘1 fit the selection: only while the canvas has focus. The
    /// editor chrome's `keyHandler` sees the key first (copy, paste, group, zoom, arrange…).
    public override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: e) }
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if engine.textActive, f == .command, e.charactersIgnoringModifiers?.lowercased() == "a" {
            de_text_command(engine.h, UInt32(DE_TEXT_SELECT_ALL), 0)
            textChanged()
            return true
        }
        if !engine.textActive, keyHandler?(e) == true { return true }
        switch (e.charactersIgnoringModifiers?.lowercased(), f) {
        case ("d", .command): send(key: DE_KEY_DUPLICATE, mods: 0)
        case ("z", .command): undo(redo: false)
        case ("z", [.command, .shift]): undo(redo: true)
        case ("0", .command): fit()
        case ("1", .command):
            de_fit_selection(engine.h)
            loop.wake()
        default: return super.performKeyEquivalent(with: e)
        }
        return true
    }

    func send(key: Int32, mods: UInt32) {
        de_key(engine.h, UInt32(key), mods)
        loop.wake(input: true)
        sync?.flush()
        onChange?()
    }

    func undo(redo: Bool) {
        let rc = redo ? de_redo(engine.h) : de_undo(engine.h)
        if rc == DE_ERR_TOO_LARGE { sync?.probe() }
        loop.wake(input: true)
        sync?.flush()
        onChange?()
    }
}

/// Measurement hooks (the Debug T5 walk): the same paths the gestures take.
extension DesignCanvasNSView {
    public func measurePhase(_ name: String) { loop.state.withLock { $0.phase = name } }
    public func measurePan(_ dx: CGFloat, _ dy: CGFloat) { pan(dx, dy) }
    public func measureZoom(_ f: CGFloat, at p: CGPoint) { zoom(by: f, at: p) }
    public func measureGestureEnd() {
        de_gesture_end(engine.h, reduceMotion ? 1 : 0)
        loop.wake()
    }
    public func measurePointer(down: Bool? = nil, at p: CGPoint, shift: Bool) {
        pointer(
            down == true ? DE_POINTER_DOWN : down == false ? DE_POINTER_UP : DE_POINTER_MOVE, at: p,
            mods: shift ? UInt32(DE_MOD_SHIFT) : 0)
    }
    public func measurePointer(down: Bool? = nil, at p: CGPoint) {
        pointer(down == true ? DE_POINTER_DOWN : down == false ? DE_POINTER_UP : DE_POINTER_MOVE, at: p)
    }
    public func measureFit() { fit() }
    public func measureUndo() { undo(redo: false) }
}

/// SwiftUI host for the canvas: passes the theme (Day/Night) and Reduce Motion in, and starts the sync relays and the
/// asset fetcher for the document. All chrome around it is SwiftUI (D8).
public struct DesignCanvas: NSViewRepresentable {
    let doc: String
    let system: String?
    let channel: any DesignSyncChannel
    let assets: CanvasAssetSource
    /// Hands the view out (the Debug measurement drives it).
    var onReady: (@MainActor (DesignCanvasNSView) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(
        doc: String, system: String?, channel: any DesignSyncChannel, assets: CanvasAssetSource,
        onReady: (@MainActor (DesignCanvasNSView) -> Void)? = nil
    ) {
        self.doc = doc
        self.system = system
        self.channel = channel
        self.assets = assets
        self.onReady = onReady
    }

    public func makeNSView(context: Context) -> NSView {
        guard let engine = Engine(doc: doc), let v = DesignCanvasNSView(engine: engine) else {
            return NSView()  // no Metal or a bad id: an empty well; the Design screen words the state
        }
        v.setAccessibilityElement(true)
        v.setAccessibilityRole(.layoutArea)
        v.setAccessibilityLabel("Design canvas")
        let fetcher = AssetFetcher(engine: engine, source: assets)
        fetcher.onAdded = { [weak v] in v?.loop.wake() }
        v.fetcher = fetcher
        v.loop.onMissing = { [weak fetcher] hashes in Task { @MainActor in fetcher?.fetch(hashes) } }
        let s = DesignSync(engine: engine, doc: doc, channel: channel)
        s.onRemote = { [weak v] in v?.contentArrived() }
        s.onStuck = { [weak v] in v?.onChange?() }
        s.onConnection = { [weak v] in v?.onChange?() }
        v.sync = s
        if let system {
            let y = DesignSync(engine: engine, doc: system, target: .system, channel: channel)
            y.onRemote = { [weak v] in v?.loop.wake() }
            v.system = y
            y.start()
        }
        s.start()
        update(v)
        onReady?(v)
        return v
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? DesignCanvasNSView { update(v) }
    }

    private func update(_ v: DesignCanvasNSView) {
        v.night = scheme == .dark
        v.reduceMotion = reduce
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? DesignCanvasNSView)?.tearDown()
    }
}
