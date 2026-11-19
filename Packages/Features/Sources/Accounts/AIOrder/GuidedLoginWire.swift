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
}

extension AccountsService {
    func loginScreen(_ id: String) async throws -> LoginScreen { throw CoreError.invalidInput("Sign-in needs a newer Core.") }
    func sendLoginInput(_ id: String, line: String) async throws {
        throw CoreError.invalidInput("Sign-in needs a newer Core.")
    }
    func boundRunners() async -> [Int64: String] { [:] }
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
}
