import Foundation
import SwiftUI

/// What the canvas (V3-02, package `DesignCanvas`) needs for one open design. Design does not link the engine: the app
/// sets `DesignModel.canvas` and builds the canvas from this, so `Features` builds and tests without the 150 MB library.
public struct DesignCanvasInput: Sendable {
    /// What the Core says about an asset the renderer asked for.
    public struct AssetInfo: Sendable {
        public let isFont: Bool
        /// `ok`, `pending` or `refused`.
        public let check: String
    }
    public let doc: String
    public let system: String?
    /// Nil when the Core does not know the hash (or is not reachable).
    public let info: @Sendable (String) async -> AssetInfo?
    /// The bytes of an `ok` asset.
    public let data: @Sendable (String) async throws -> Data
}

extension DesignModel {
    /// The canvas for a design doc, or nil when the app has none (tests) or the doc cannot sync yet.
    func canvasView(_ d: DesignDoc) -> AnyView? {
        guard d.kind == .design, let canvas, let service else { return nil }
        let input = DesignCanvasInput(
            doc: d.id, system: d.system,
            info: { sha in
                guard let a = try? await service.asset(sha) else { return nil }
                return .init(isFont: a.kind == .font, check: a.check.rawValue)
            },
            data: { try await service.data($0) })
        return canvas(input)
    }
}
