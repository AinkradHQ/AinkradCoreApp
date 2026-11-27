import Foundation
import Testing

@testable import CoreKit

@Suite struct SignedRequestTests {
    @Test func aModuleRouteIsSignedLikeAnyOtherCall() async throws {
        let h = try Harness()
        let conn = try h.connection()
        let target = "/modules/brain/v1/imports/r1/proposals/p1/items?after=3&limit=50"
        do { _ = try await conn.signedRequest(method: "GET", target: target) } catch {
            // The fake Core has no such route; a refusal is fine, the request on the wire is what counts.
        }
        let sent = h.core.requests(to: "/modules/brain/v1/imports").first
        #expect(sent?.target == target && sent?.method == "GET")
        #expect(sent?.headers["ainkrad-signature"]?.count == 86 && sent?.headers["ainkrad-session"] != nil)
    }

    @Test func preAuthRoutesAndBigBodiesAreRefusedBeforeSending() async throws {
        let h = try Harness()
        let conn = try h.connection()
        await #expect(throws: CoreError.self) { _ = try await conn.signedRequest(method: "POST", target: "/handshake") }
        await #expect(throws: CoreError.bodyTooLarge) {
            _ = try await conn.signedRequest(
                method: "POST", target: "/modules/brain/v1/imports", body: Data(count: (1 << 20) + 1))
        }
        #expect(h.core.requests(to: "/modules").isEmpty)
    }

    @Test func theCoresOwnRefusalsAreToldApartFromAnAppsAnswers() {
        func res(_ status: Int, _ body: String) -> RawResponse {
            RawResponse(status: status, headers: [:], body: Data(body.utf8))
        }
        #expect(SessionManager.isCoreRefusal(res(401, #"{"code":"session_expired","message":"x"}"#)))
        #expect(SessionManager.isCoreRefusal(res(403, #"{"code":"step_up_required","message":"x"}"#)))
        #expect(SessionManager.isCoreRefusal(res(429, "")))
        // An app behind the preview that says 401, 403 or 404 on its own is an answer to show, not a failure.
        #expect(!SessionManager.isCoreRefusal(res(401, "<html>log in</html>")))
        #expect(!SessionManager.isCoreRefusal(res(403, #"{"code":"nope"}"#)))
        #expect(!SessionManager.isCoreRefusal(res(404, "")))
        #expect(!SessionManager.isCoreRefusal(res(409, #"{"code":"not_running"}"#)))
    }
}
