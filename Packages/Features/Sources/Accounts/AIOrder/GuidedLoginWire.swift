import CoreKit
import Foundation

// HAND-WRITTEN WIRE for the guided sign-in routes (E7-5). The generated client does not know them yet; the coordinator
// runs `make clients` at integration and this file then shrinks. Every call is gated by API minor 95.

/// `POST /api/v1/accounts/logins/{id}/input`. The line is a secret: no `Debug`, never stored or logged by the app.
private struct LoginInputBody: Encodable { let text: String }

/// `GET /api/v1/accounts` read for the runner an account is pinned to, if the Core says (`runners`, or one `runner`).
private struct BoundProbe: Decodable {
    let id: Int64
    let runners: [String]?
    let runner: String?
    let wipeNote: String?
    let keyringNotCleared: Bool?
    let modelsEnforced: Bool?
    private enum Keys: String, CodingKey {
        case id, runners, runner
        case wipeNote = "wipe_note"
        case keyringNotCleared = "keyring_not_cleared"
        case modelsEnforced = "models_enforced"
    }
    // Lenient: a field of another shape is read as absent, never a failure of the whole list.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int64.self, forKey: .id)
        runners = try? c.decodeIfPresent([String].self, forKey: .runners)
        runner = try? c.decodeIfPresent(String.self, forKey: .runner)
        wipeNote = try? c.decodeIfPresent(String.self, forKey: .wipeNote)
        keyringNotCleared = try? c.decodeIfPresent(Bool.self, forKey: .keyringNotCleared)
        modelsEnforced = try? c.decodeIfPresent(Bool.self, forKey: .modelsEnforced)
    }
}

/// What the Core says about one account beyond its row: what stays behind on removal, and whether a disallowed model is
/// refused by the runner. Both are optional; an older Core says neither.
struct AccountNotes: Equatable, Sendable {
    var wipeNote: String?
    var modelsEnforced: Bool?

    static let keyringWords =
        "Your Antigravity login may stay in this runner's keyring. Sign out in Antigravity on that runner."
    static let unenforcedWords =
        "This account's sessions cannot restrict models, so Allow only affects what Core starts."

    /// The Undo toast: "<Name> removed", and what may stay behind when the Core says so.
    static func removedWords(_ name: String, note: String?) -> String {
        note.map { "\(name) removed. \($0)" } ?? "\(name) removed"
    }

    /// A note in the Core's words, else the plain one when it only raised the flag.
    static func wipe(note: String?, flag: Bool?) -> String? {
        if let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return flag == true ? keyringWords : nil
    }
}

extension AccountsService {
    func loginScreen(_ id: String) async throws -> LoginScreen {
        throw CoreError.invalidInput("Sign-in needs a newer Core.")
    }
    func sendLoginInput(_ id: String, line: String) async throws {
        throw CoreError.invalidInput("Sign-in needs a newer Core.")
    }
    func boundRunners() async -> [Int64: String] { [:] }
    func accountNotes() async -> [Int64: AccountNotes] { [:] }
}

extension LiveAccountsService {
    func loginScreen(_ id: String) async throws -> LoginScreen {
        guard await aiOrderSupported() else { throw CoreError.invalidInput("Sign-in needs a newer Core.") }
        return try JSONDecoder().decode(
            LoginScreen.self,
            from: try await connection.signedRequest(
                method: "GET", target: "/api/v1/accounts/logins/\(Self.segment(id))/screen"))
    }

    func sendLoginInput(_ id: String, line: String) async throws {
        guard await aiOrderSupported() else { throw CoreError.invalidInput("Sign-in needs a newer Core.") }
        let body = try JSONEncoder().encode(LoginInputBody(text: line))
        _ = try await connection.signedRequest(
            method: "POST", target: "/api/v1/accounts/logins/\(Self.segment(id))/input", body: body)
    }

    func boundRunners() async -> [Int64: String] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/accounts"),
            let rows = try? JSONDecoder().decode([BoundProbe].self, from: data)
        else { return [:] }
        return Dictionary(
            rows.compactMap { r in (r.runners?.first ?? r.runner).map { (r.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    func accountNotes() async -> [Int64: AccountNotes] {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/accounts"),
            let rows = try? JSONDecoder().decode([BoundProbe].self, from: data)
        else { return [:] }
        var out: [Int64: AccountNotes] = [:]
        for r in rows {
            let n = AccountNotes(
                wipeNote: AccountNotes.wipe(note: r.wipeNote, flag: r.keyringNotCleared),
                modelsEnforced: r.modelsEnforced)
            if n.wipeNote != nil || n.modelsEnforced != nil { out[r.id] = n }
        }
        return out
    }
}
