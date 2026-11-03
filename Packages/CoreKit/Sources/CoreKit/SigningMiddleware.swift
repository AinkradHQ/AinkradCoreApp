import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Signs every request the generated client sends (§5) with the current session, and turns the Core's refusals into
/// `CoreError`. A `clock_skew` or `session_expired` answer is retried once with a fresh signature (the body is buffered, so
/// it can be sent again). 401, 403 and 429 answers are thrown as `CoreError` (use `CoreError.unwrapping` on what the generated
/// client throws); every other status passes through to the generated client's typed outputs.
struct SigningMiddleware: ClientMiddleware {
    /// A signed body is at most 1 MiB (§4).
    static let maxBody = 1 << 20
    let sessions: SessionManager

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let payload: Data
        if let body {
            do { payload = try await Data(collecting: body, upTo: Self.maxBody) } catch { throw CoreError.bodyTooLarge }
        } else {
            payload = Data()
        }
        guard let target = request.path, target.hasPrefix("/") else {
            throw CoreError.invalidInput("a request without a path")
        }
        // Pre-auth routes take no session (§4, §5.1): CoreKit makes those calls itself, never through the generated client.
        guard !target.hasPrefix("/handshake"), !target.hasPrefix("/pair") else {
            throw CoreError.invalidInput("\(target) is a pre-auth route; CoreKit calls it itself")
        }
        var retried: SessionManager.Retried = []
        while true {
            let session = try await sessions.currentSession()
            let signed = try await sessions.headers(
                method: request.method.rawValue, target: target, body: payload, sessionID: session.id)
            var req = request
            req.headerFields[.authorization] = nil
            for (name, value) in signed {
                guard let field = HTTPField.Name(name) else { continue }
                req.headerFields[field] = value
            }
            let (response, responseBody) = try await next(req, payload.isEmpty ? nil : HTTPBody(payload), baseURL)
            let status = response.status.code
            guard status == 401 || status == 403 || status == 429 else { return (response, responseBody) }
            var data = Data()
            if let responseBody { data = try await Data(collecting: responseBody, upTo: 64 * 1024) }
            var headers: [String: String] = [:]
            for f in response.headerFields { headers[f.name.rawName.lowercased()] = f.value }
            let error = CoreError.from(status: status, headers: headers, body: data)
            if let next = await sessions.retry(after: error, sessionID: session.id, retried: retried) {
                retried = next
                continue
            }
            throw error
        }
    }
}
