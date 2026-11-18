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
    var lastEditTooLarge: Bool { view?.editorLastEditTooLarge ?? false }

    /// Hands the chrome the canvas and has the canvas tell it when the document or selection may have changed.
    static func connect(_ view: DesignCanvasNSView, to handle: DesignEditorHandle) {
        handle.attach(CanvasEditing(view))
        view.onChange = { handle.changed() }
    }
}

/// Gives Design its canvas (V3-02). The app links the engine; `Features` does not. A design gets a canvas once its doc can
/// sync with the Core. TODO(V1-03): the Core serves no `docs/{d}/sync` route yet, so there is no live `DesignSyncChannel`
/// and real designs keep their preview. Then: `DesignCanvas(doc:system:channel:assets:)` with the live channel and a
/// `CanvasAssetSource` over `input.info` / `input.data` (its `CanvasAssetInfo(contentType:check:)` from `info`), and
/// `onReady: { CanvasEditing.connect($0, to: input.editor) }` so the layers panel and inspector work. Debug: `CORE_DESIGN_SCENE=<dir>` (doc.bin, system.bin, <sha>.png from AinkradCore's
/// synth scene) opens every design on that scene through a local channel, for screenshots and the T5 measurement.
@MainActor
enum DesignCanvasHookup {
    static func install(_ app: AppModel) {
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["CORE_DESIGN_SCENE"], !dir.isEmpty {
            let scene = URL(fileURLWithPath: dir)
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
        app.design.canvas = { _ in nil }
    }
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
