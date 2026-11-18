import Foundation

/// What the Core says about one library asset (`GET /modules/design/v1/assets/{sha}`).
public struct CanvasAssetInfo: Sendable, Equatable {
    public enum Check: Sendable { case ok, pending, refused }
    /// Where bytes of one Core content type may go. Decided by the Core's `content_type` (sniffed from the file's magic bytes
    /// on upload) and nothing else: not the asset's kind or name, which a person sets (#304 review).
    public enum Route: Sendable, Equatable { case font, image, none }
    /// The Core's content type, e.g. `font/ttf` or `image/png`.
    public let contentType: String
    public let check: Check
    public init(contentType: String, check: Check) {
        self.contentType = contentType
        self.check = check
    }

    /// Exactly the types the Core's allow-list can sniff as a font or a raster image. Everything else (SVG, PDF, zip, an
    /// unknown or oddly cased type) is never handed to the engine.
    public var route: Route {
        switch contentType {
        case "font/ttf", "font/otf", "font/woff2": .font
        case "image/png", "image/jpeg", "image/gif", "image/webp": .image
        default: .none
        }
    }
}

/// Where the canvas gets asset bytes: the Design service in the app, files in the Debug scene, fakes in tests.
public struct CanvasAssetSource: Sendable {
    public let info: @Sendable (String) async -> CanvasAssetInfo?
    public let data: @Sendable (String) async throws -> Data
    public init(
        info: @escaping @Sendable (String) async -> CanvasAssetInfo?,
        data: @escaping @Sendable (String) async throws -> Data
    ) {
        self.info = info
        self.data = data
    }
}

/// Fetches what the renderer asked for (`de_missing_assets`). Bytes are fetched, and so handed to Skia, only when the Core
/// marked the asset `ok` and its content type is a font or an image type; fonts go to `de_font_add`, images to `de_asset_add`,
/// strictly by that type (fonts are checked by parsing on a runner, V4-01). `pending` is asked again later; `refused`,
/// unknown or failed hashes are never fetched again for this canvas.
@MainActor
final class AssetFetcher {
    let engine: Engine
    let source: CanvasAssetSource
    var onAdded: () -> Void = {}
    private var seen: Set<String> = []
    static let retryPending: Duration = .seconds(10)

    init(engine: Engine, source: CanvasAssetSource) {
        self.engine = engine
        self.source = source
    }

    func fetch(_ hashes: [String]) {
        for sha in hashes where !seen.contains(sha) {
            seen.insert(sha)
            Task { await load(sha) }
        }
    }

    private func load(_ sha: String) async {
        guard let info = await source.info(sha) else { return }
        switch info.check {
        case .refused: return
        case .pending:
            try? await Task.sleep(for: Self.retryPending)
            seen.remove(sha)
            return
        case .ok:
            let route = info.route
            guard route != .none, let bytes = try? await source.data(sha) else { return }  // never fetched, never fed
            let added = route == .font ? engine.addFont(sha, bytes) : engine.addAsset(sha, bytes)
            if added { onAdded() }
        }
    }
}
