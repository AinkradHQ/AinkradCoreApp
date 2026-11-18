import Design
import DesignCanvas
import Foundation
import Pairing
import SwiftUI
import os

/// Gives Design its canvas (V3-02). The app links the engine; `Features` does not. A design gets a canvas once its doc can
/// sync with the Core. TODO(V1-03): the Core serves no `docs/{d}/sync` route yet, so there is no live `DesignSyncChannel`
/// and real designs keep their preview. Then: `DesignCanvas(doc:system:channel:assets:)` with the live channel and a
/// `CanvasAssetSource` over `input.info` / `input.data`. Debug: `CORE_DESIGN_SCENE=<dir>` (doc.bin, system.bin, <sha>.png from AinkradCore's
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
                        assets: SceneChannel.assets(scene), onReady: { DesignMeasure.ready($0) }))
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
                    ? CanvasAssetInfo(isFont: false, check: .ok) : nil
            },
            data: { sha in try Data(contentsOf: dir.appendingPathComponent("\(sha).png")) })
    }
}

#endif
