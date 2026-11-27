import AppKit
import CoreKit
import Design
import DesignCanvas
import Foundation
import Pairing
import SwiftUI
import os

/// The editor chrome's way into the engine (V3-04): `Design` sees `DesignEditBackend`, the canvas view does the work.
@MainActor
final class CanvasEditing: DesignEditBackend {
    private weak var view: DesignCanvasNSView?
    init(_ view: DesignCanvasNSView) { self.view = view }
    func tree() -> Data? { view?.editorTree() }
    func node(_ id: String) -> String? { view?.editorNode(id) }
    func selection() -> [String] { view?.editorSelection() ?? [] }
    func select(_ ids: [String]) -> Bool { view?.editorSelect(ids) ?? false }
    func edit(_ json: String) -> Bool { view?.editorEdit(json) ?? false }
    func undo() { view?.editorUndo() }
    func redo() { view?.editorRedo() }
    func fitSelection() { view?.editorFitSelection() }
    func peers() -> Data? { view?.editorPeers() }
    func setPresence(_ json: String) { view?.editorSetPresence(json) }
    func tokens() -> Data? { view?.editorTokens() }
    var syncStuck: Bool { view?.editorSyncStuck ?? false }
    var loaded: Bool { view?.editorLoaded ?? false }
    var syncConnected: Bool { view?.editorSyncConnected ?? false }
    var lastEditTooLarge: Bool { view?.editorLastEditTooLarge ?? false }
    var tool: Int { view?.editorTool ?? 0 }
    func docTokens() -> Data? { view?.editorDocTokens() }
    func setTool(_ tool: Int) { view?.editorSetTool(tool) }
    func camera() -> CanvasCamera? {
        view?.editorCamera.map { CanvasCamera(zoom: $0.zoom, pan: CGPoint(x: $0.panX, y: $0.panY)) }
    }
    func fit(_ rect: CGRect) { view?.editorFit(rect) }
    func presenceList() -> Data? { view?.editorPresenceList() }
    func follow(_ peer: String) { view?.editorFollow(peer) }
    func setPage(_ index: Int) { view?.editorSetPage(index) }
    func zoom(by factor: Double) { view?.editorZoom(by: factor) }
    func zoom(to scale: Double) { view?.editorZoom(to: scale) }
    func fitAll() { view?.editorFitAll() }
    func copy() -> Data? { view?.editorCopy() }
    func paste(_ json: Data, parent: String?, atCenter: Bool) -> Bool {
        guard let view else { return false }
        return view.editorPaste(json, parent: parent, at: atCenter ? view.center : nil)
    }
    func duplicate() -> Bool { view?.editorDuplicate() ?? false }
    func group() -> Bool { view?.editorGroup() ?? false }
    func ungroup() -> Bool { view?.editorUngroup() ?? false }
    func createComponent() -> Bool { view?.editorComponentCreate() ?? false }
    func insertInstance(_ component: String, at: CGPoint?) -> Bool {
        guard let view else { return false }
        return view.editorInstanceInsert(component, at: at ?? view.center)
    }
    func detachInstance() -> Bool { view?.editorInstanceDetach() ?? false }
    func setKeyHandler(_ handler: (@MainActor (EditorKey) -> Bool)?) {
        guard let view else { return }
        guard let handler else {
            view.keyHandler = nil
            return
        }
        view.keyHandler = { @MainActor (e: NSEvent) -> Bool in handler(EditorKey(e)) }
    }
    func debugPresence(_ json: String) {
        #if DEBUG
        view?.editorDebugPresence(json)
        #endif
    }
    func present(_ tap: (@MainActor (String?) -> Void)?) {
        view?.editorPresent(tap.map { t in { id in MainActor.assumeIsolated { t(id) } } })
    }

    /// Hands the chrome the canvas and has the canvas tell it when the document or selection may have changed.
    static func connect(_ view: DesignCanvasNSView, to handle: DesignEditorHandle) {
        handle.attach(CanvasEditing(view))
        view.onChange = { handle.changed() }
    }
}

extension NSView {
    /// The middle of the view, where the canvas is looking.
    fileprivate var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
}

/// Gives Design its canvas (V3-02). The app links the engine; `Features` does not. A design gets its canvas over the
/// Core's sync socket (`CoreDesignSyncChannel`, resuming from the last seq it applied); a design system rides the same
/// channel. Assets come from the Design service. Debug: `CORE_DESIGN_SCENE=<dir>` (doc.bin, system.bin, <sha>.png from
/// AinkradCore's synth scene) opens every design on that scene through a local channel, for screenshots and the T5
/// measurement.
@MainActor
enum DesignCanvasHookup {
    static func install(_ app: AppModel) {
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["CORE_DESIGN_SCENE"], !dir.isEmpty {
            let scene = URL(fileURLWithPath: dir)
            app.design.debugCanvasProbe = { log in await ToolProbe.run(log) }
            app.design.canvas = { input in
                AnyView(
                    DesignCanvas(
                        doc: input.doc, system: SceneChannel.system, channel: SceneChannel(dir: scene),
                        assets: SceneChannel.assets(scene),
                        onReady: {
                            DesignMeasure.ready($0)
                            CanvasEditing.connect($0, to: input.editor)
                        }))
            }
            return
        }
        #endif
        app.design.canvas = { input in
            guard let openSocket = input.openSocket else { return nil }
            let channel = CoreDesignSyncChannel { doc, seq in CoreSocketAdapter(try await openSocket(doc, seq)) }
            let assets = CanvasAssetSource(
                info: { sha in
                    guard let i = await input.info(sha) else { return nil }
                    return CanvasAssetInfo(
                        contentType: i.contentType,
                        check: i.check == "ok" ? .ok : i.check == "refused" ? .refused : .pending)
                },
                data: input.data)
            return AnyView(
                DesignCanvas(
                    doc: input.doc, system: input.system, channel: channel, assets: assets,
                    onReady: { CanvasEditing.connect($0, to: input.editor) }))
        }
    }
}

/// CoreKit's signed socket as the channel's socket.
struct CoreSocketAdapter: DesignSocket {
    let socket: CoreSocket
    init(_ socket: CoreSocket) { self.socket = socket }
    func receive() async throws -> DesignSocketFrame {
        switch try await socket.receive() {
        case .text(let t): .text(t)
        case .binary(let d): .binary(d)
        }
    }
    func send(_ frame: DesignSocketFrame) async throws {
        switch frame {
        case .text(let t): try await socket.send(.text(t))
        case .binary(let d): try await socket.send(.binary(d))
        }
    }
    func cancel() { socket.cancel() }
    var closeCode: Int { socket.closeCode }
}

#if DEBUG
/// Debug only: a stand-in for the sync socket that serves one scene's full states and keeps the link open.
struct SceneChannel: DesignSyncChannel {
    static let system = "dd_sys"
    let dir: URL

    func open(doc: String) async throws -> AsyncThrowingStream<DesignSyncMessage, any Error> {
        let file = dir.appendingPathComponent(doc == Self.system ? "system.bin" : "doc.bin")
        let bytes = try Data(contentsOf: file)
        let (stream, cont) = AsyncThrowingStream<DesignSyncMessage, any Error>.makeStream()
        cont.yield(.update(bytes))
        Self.held.withLock { $0.append(cont) }  // never finished: the "socket" stays up
        return stream
    }

    func send(_ message: DesignSyncMessage, doc: String) async throws {}

    private static let held = OSAllocatedUnfairLock(
        initialState: [AsyncThrowingStream<DesignSyncMessage, any Error>.Continuation]())

    /// The scene's images, every one `ok`; no fonts (the scene draws with `system`).
    static func assets(_ dir: URL) -> CanvasAssetSource {
        CanvasAssetSource(
            info: { sha in
                FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(sha).png").path)
                    ? CanvasAssetInfo(contentType: "image/png", check: .ok) : nil
            },
            data: { sha in try Data(contentsOf: dir.appendingPathComponent("\(sha).png")) })
    }
}

#endif
