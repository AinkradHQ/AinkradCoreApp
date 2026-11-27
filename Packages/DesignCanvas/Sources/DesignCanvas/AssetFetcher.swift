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
    /// Called when the set of images that gave up changes.
    var onFailed: () -> Void = {}
    private var seen: Set<String> = []
    private var tries: [String: Int] = [:]
    /// Hashes that failed every retry (or the Core refused): the chrome says "image could not load" and offers Retry.
    private(set) var failed: Set<String> = [] {
        didSet { if failed != oldValue { onFailed() } }
    }
    static let retryPending: Duration = .seconds(10)
    /// Waits before each retry of a fetch that failed: 2, 5, 15, 30 s, then it gives up.
    static let retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)]

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
        guard let info = await source.info(sha) else { return await retry(sha) }
        switch info.check {
        case .refused: failed.insert(sha)
        case .pending:
            try? await Task.sleep(for: Self.retryPending)
            seen.remove(sha)
            return
        case .ok:
            let route = info.route
            guard route != .none else { return }  // never fetched, never fed
            guard let bytes = try? await source.data(sha) else { return await retry(sha) }
            let added = route == .font ? engine.addFont(sha, bytes) : engine.addAsset(sha, bytes)
            if added { onAdded() } else { failed.insert(sha) }
        }
    }

    /// A failed fetch is tried again after a growing wait (the next render asks for it again); after the last, it is failed.
    private func retry(_ sha: String) async {
        let n = tries[sha, default: 0]
        guard n < Self.retryDelays.count else { return _ = failed.insert(sha) }
        tries[sha] = n + 1
        try? await Task.sleep(for: Self.retryDelays[n])
        seen.remove(sha)
    }

    /// "Retry" in the chrome: everything that gave up is asked for again from the start.
    func retryFailed() {
        let list = failed
        failed = []
        for sha in list {
            tries[sha] = 0
            seen.remove(sha)
        }
        onAdded()  // wakes the loop, which asks for what is missing
    }
}
