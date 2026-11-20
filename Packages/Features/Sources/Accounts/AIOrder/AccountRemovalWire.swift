import CoreKit
import Foundation

// HAND-WRITTEN WIRE for Core 0.10 (E7-7). The generated client does not know `undo_until` or `restore` yet; the
// coordinator runs `make clients` at integration. Every call is gated by API minor 95 through `aiOrderOn`.

/// `DELETE /api/v1/accounts/{id}` now answers `{"deleted": true, "undo_until": "..."}`.
struct AccountRemovedProbe: Decodable, Sendable {
    let undoUntil: Date?
    private enum Keys: String, CodingKey { case undoUntil = "undo_until" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        undoUntil = WireDate.parse(try c.decodeIfPresent(String.self, forKey: .undoUntil))
    }
}

/// An account that was just removed and can still come back: where it stood and until when.
struct RemovedAccount: Equatable, Sendable {
    let account: AccountItem
    let index: Int
    let until: Date

    /// True while the Core still keeps it.
    func canUndo(at now: Date) -> Bool { now < until }
}

extension AccountsService {
    func removeAccount(_ id: Int64) async throws -> Date? {
        try await deleteAccount(id)
        return nil
    }
    func restoreAccount(_ id: Int64) async throws {
        throw CoreError.invalidInput("Bringing an account back needs a newer Core.")
    }
}

extension LiveAccountsService {
    func removeAccount(_ id: Int64) async throws -> Date? {
        let data = try await connection.signedRequest(method: "DELETE", target: "/api/v1/accounts/\(id)")
        return (try? JSONDecoder().decode(AccountRemovedProbe.self, from: data))?.undoUntil
    }

    func restoreAccount(_ id: Int64) async throws {
        _ = try await connection.signedRequest(
            method: "POST", target: "/api/v1/accounts/\(id)/restore", body: Data("{}".utf8))
    }
}
