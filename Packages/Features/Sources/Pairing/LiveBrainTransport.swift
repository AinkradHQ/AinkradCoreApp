import Brain
import BrainImport
import CoreKit
import Foundation

/// The Brain's routes over the paired connection: `CoreConnection.signedRequest`, so the signing, the session and the
/// retries are the ones every other call uses. A Core answer that is an error status becomes `BrainHTTPError`; auth, rate
/// limit and step-up refusals pass through as `CoreError` for the host (Touch ID, banners) to handle.
struct LiveBrainTransport: BrainTransport {
    let connection: CoreConnection

    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        do {
            return try await connection.signedRequest(method: method, target: path, body: body ?? Data())
        } catch CoreError.http(let status, let code, let message) {
            throw BrainHTTPError(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw BrainHTTPError(status: 400, code: "bad_request", message: message)
        }
    }
}

/// The Core did not answer, or answered 5xx: an import waits and tries again. Anything else (auth, 4xx) stops it.
extension CoreError: TransientFailure {
    public var isTransient: Bool {
        switch self {
        case .offline, .coreUnproven: true
        case .http(let status, _, _): status >= 500
        default: false
        }
    }
}
