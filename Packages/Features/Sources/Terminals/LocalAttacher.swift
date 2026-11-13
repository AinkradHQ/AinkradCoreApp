import CoreKit
import Foundation

/// Decides whether a terminal can be attached over its runner's own socket, and does it. Everything it needs from the outside is
/// a closure, so the decisions are tested without a Core.
struct LocalAttacher: Sendable {
    /// The API minor that has `grantLocalTerminal`.
    static let localMinor: Int32 = 58

    var localRunner: @Sendable () async -> LocalRunner?
    /// Whether the connected Core has the local-path routes.
    var supported: @Sendable () async -> Bool
    /// Grants, signatures and the release for terminal `id`.
    var source: @Sendable (String) -> LocalGrantSource

    /// A local attachment, or nil for "use the Core's WebSocket": no runner on this Mac, the terminal is on another runner, no
    /// socket (a host from an older build), a Core without the routes or that says the terminal or runner is not ready, a host
    /// that would not take the grant or did not answer. An answer that is the Core's decision about this person (no step-up, no
    /// scope, revoked, rate limit) is thrown, as for any attach.
    func attach(_ id: String, runner: String, after: UInt64) async throws -> LocalTerminalAttachment? {
        guard let local = await localRunner(), local.id == runner else { return nil }
        let path = local.terminals.appending(path: "\(id).local.sock").path
        guard FileManager.default.fileExists(atPath: path), await supported() else { return nil }
        let source = source(id)
        let first: LocalTerminalGrant
        do { first = try await source.grant() } catch {
            if Self.unavailable(error) { return nil }
            throw error
        }
        do {
            return try await LocalTerminalAttachment.open(socketPath: path, first: first, source: source, after: after)
        } catch {
            // The host would not serve it (or did not answer): hand the lease back and go through the Core.
            await source.release()
            return nil
        }
    }

    /// A status that means "not on this Core / not now", as against one the Core decided about this person.
    static func unavailable(_ error: any Error) -> Bool {
        guard case .http(let status, _, _)? = CoreError.unwrapping(error) else { return false }
        return [404, 405, 409, 501].contains(status)
    }
}
