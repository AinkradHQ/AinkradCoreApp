import CoreKit
import Foundation
import SwiftUI

/// What the canvas (V3-02, package `DesignCanvas`) needs for one open design. Design does not link the engine: the app sets
/// `DesignModel.canvas` and builds the canvas from this, so `Features` builds and tests without the 150 MB library.
public struct DesignCanvasInput: Sendable {
    /// What the Core says about an asset the renderer asked for.
    public struct AssetInfo: Sendable {
        /// The Core's sniffed content type (`font/ttf`, `image/png`, …). The canvas routes bytes by this alone.
        public let contentType: String
        /// `ok`, `pending` or `refused`.
        public let check: String
    }
    public let doc: String
    public let system: String?
    /// Nil when the Core does not know the hash (or is not reachable).
    public let info: @Sendable (String) async -> AssetInfo?
    /// The bytes of an `ok` asset.
    public let data: @Sendable (String) async throws -> Data
    /// The editor chrome (V3-04). When the canvas is up the app gives it the canvas: `editor.attach(backend)`, and calls
    /// `editor.changed()` when the document or selection may have changed.
    public let editor: DesignEditorHandle
    /// Opens the signed sync socket of a design (or a design system), resuming after `lastSeq`: `GET
    /// /modules/design/v1/docs/{d}/sync` with `Last-Update-Seq`. Nil without a connection.
    public let openSocket: (@Sendable (_ doc: String, _ lastSeq: UInt64?) async throws -> CoreSocket)?
}

/// The app's way to reach the editor chrome of one design without seeing its internals.
@MainActor
public struct DesignEditorHandle: Sendable {
    let editor: DesignEditor
    public func attach(_ backend: (any DesignEditBackend)?) { editor.attach(backend) }
    public func changed() { editor.changed() }
}

extension DesignModel {
    /// The canvas for a design doc, or nil when the app has none (tests) or the doc cannot sync yet.
    func canvasView(_ d: DesignDoc, editor viewer: DesignEditor? = nil) -> AnyView? {
        // A design draws on it; a design system opens on it too (the style guide reads and writes its tokens).
        guard d.kind == .design || d.kind == .system, let canvas, let service else { return nil }
        let socketOpener: (@Sendable (String, UInt64?) async throws -> CoreSocket)? = connection.map { connection in
            { @Sendable (doc: String, lastSeq: UInt64?) async throws -> CoreSocket in
                let headers: [String: String] = lastSeq.map { ["Last-Update-Seq": String($0)] } ?? [:]
                let target = LiveDesignService.base + "/docs/" + LiveDesignService.seg(doc) + "/sync"
                return try await connection.openSocket(target: target, headers: headers)
            }
        }
        let input = DesignCanvasInput(
            doc: d.id, system: d.system,
            info: { sha in
                guard let a = try? await service.asset(sha) else { return nil }
                return .init(contentType: a.contentType, check: a.check.rawValue)
            },
            data: { try await service.data($0) },
            editor: DesignEditorHandle(editor: viewer ?? editor(for: d.id)),
            openSocket: socketOpener)
        return canvas(input)
    }

    /// The one editor of an open design; made when its canvas is first built, dropped when the item closes.
    func editor(for doc: String) -> DesignEditor {
        if let e = editors[doc] { return e }
        let e = DesignEditor(doc: doc, service: service)
        // Ask… draws on this canvas: three directions from the words, through the composer.
        e.ask = { [weak self] req in
            guard let self else { return false }
            guard composeSupported else {
                host.shell.showToast("This Core cannot draw with AI yet.", kind: .warn)
                return false
            }
            await drawWithAI(prompt: req.text)
            return true
        }
        editors[doc] = e
        return e
    }
}
