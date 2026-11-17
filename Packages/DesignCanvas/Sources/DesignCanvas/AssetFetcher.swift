import Foundation

/// What the Core says about one library asset (`GET /modules/design/v1/assets/{sha}`).
public struct CanvasAssetInfo: Sendable, Equatable {
    public enum Check: Sendable { case ok, pending, refused }
    public let isFont: Bool
    public let check: Check
    public init(isFont: Bool, check: Check) {
        self.isFont = isFont
        self.check = check
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
/// marked the asset `ok` (fonts are checked by parsing on a runner, V4-01). `pending` is asked again later; `refused`,
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
            guard let bytes = try? await source.data(sha) else { return }
            let added = info.isFont ? engine.addFont(sha, bytes) : engine.addAsset(sha, bytes)
            if added { onAdded() }
        }
    }
}
