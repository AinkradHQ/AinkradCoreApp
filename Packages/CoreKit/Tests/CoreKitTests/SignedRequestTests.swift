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
}
