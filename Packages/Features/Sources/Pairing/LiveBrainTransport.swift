import Brain
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
