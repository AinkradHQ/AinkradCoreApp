import AinkradClient
import CryptoKit
import Foundation
import Testing

@testable import CoreKit

@Suite struct SignerTests {
    @Test func headersCarryTheSixFieldsAndVerify() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let headers = try await m.headers(
            method: "GET", target: "/api/v1/events?after=3&limit=10", body: Data(), sessionID: "s_abc")
        #expect(
            Set(headers.keys) == [
                "ainkrad-device", "ainkrad-session", "ainkrad-alg", "ainkrad-timestamp", "ainkrad-nonce",
                "ainkrad-signature",
            ])
        #expect(headers["ainkrad-alg"] == "ES256" && headers["ainkrad-device"] == h.identity.deviceID)
        #expect(headers["ainkrad-nonce"]?.count == 22 && headers["ainkrad-signature"]?.count == 86)
        #expect(headers["ainkrad-timestamp"] == String(Int64(h.clock.now().timeIntervalSince1970)))
        let canonical = Wire.canonicalRequest(
            coreFP: h.identity.coreFingerprint, deviceID: h.identity.deviceID, sessionID: "s_abc", method: "GET",
            path: "/api/v1/events", query: "after=3&limit=10", timestamp: UInt64(headers["ainkrad-timestamp"]!)!,
            nonce: headers["ainkrad-nonce"]!, body: Data())
        #expect(
            Wire.verify(spki: h.key.spki, message: canonical, signature: Wire.unb64(headers["ainkrad-signature"]!)!))
        // Session `-`: no header, `-` in the string.
        let none = try await m.headers(method: "POST", target: "/pair/status", body: Data(), sessionID: nil)
        #expect(none["ainkrad-session"] == nil)
        #expect(headers["ainkrad-nonce"] != none["ainkrad-nonce"], "a fresh nonce each time")
    }

    @Test func pathBytesAreSignedAsSent() async throws {
        let h = try Harness()
        let headers = try await h.sessions().headers(
            method: "GET", target: "/api/v1/a%2Fb%20c?x=%7E", body: Data(), sessionID: "s_1")
        let canonical = Wire.canonicalRequest(
            coreFP: h.identity.coreFingerprint, deviceID: h.identity.deviceID, sessionID: "s_1", method: "GET",
            path: "/api/v1/a%2Fb%20c", query: "x=%7E", timestamp: UInt64(headers["ainkrad-timestamp"]!)!,
            nonce: headers["ainkrad-nonce"]!, body: Data())
        #expect(
            Wire.verify(spki: h.key.spki, message: canonical, signature: Wire.unb64(headers["ainkrad-signature"]!)!))
    }
}

@Suite struct SessionTests {
    @Test func opensASessionAfterProvingTheCore() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let s = try await m.currentSession()
        #expect(s.id.hasPrefix("s_") && s.scopes == ["read", "admin"])
        #expect(s.expiresAt - s.createdAt == 900)
        #expect(await m.negotiatedMinor == 33)
        // The proof came first: the first request to the Core is the unsigned handshake.
        #expect(h.core.log.first?.target == "/handshake" && h.core.log.first?.headers["ainkrad-signature"] == nil)
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await m.currentSession().id } }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(ids.count == 1 && h.core.sessionsIssued == 1)
    }

    @Test func refreshesAtEightyPercentWithoutBeingAsked() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let first = try await m.currentSession()
        #expect(await m.needsRefresh(first, at: first.createdAt + 719) == false)
        #expect(await m.needsRefresh(first, at: first.createdAt + 720) == true)
        await m.startAutoRefresh()
        for _ in 0..<200 where h.core.sessionsIssued < 3 { try await Task.sleep(for: .milliseconds(10)) }
        await m.stopAutoRefresh()
        #expect(h.core.sessionsIssued >= 3, "refreshed on its own")
        #expect(h.clock.sleeps.first == .seconds(720), "80 % of 900 s")
        // Every refresh came before the old session ran out: the Core never saw an expired one.
        #expect(h.core.requests(to: "/handshake/session").count == h.core.sessionsIssued)
        let latest = try #require(await m.session)
        #expect(latest.id != first.id)
    }

    @Test func needsRefreshOnlyWhenOldEnough() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let s = CoreSession(id: "s_x", createdAt: 0, expiresAt: 900, scopes: [], elevatedUntil: nil)
        #expect(await m.needsRefresh(s, at: 100) == false)
        #expect(await m.needsRefresh(s, at: 900) == true)
    }

    @Test func aFailedEarlyRefreshKeepsTheLiveSession() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let first = try await m.currentSession()
        h.clock.advance(800)  // past 80 %, before expiry
        h.core.fail("/handshake", .init(status: 429, code: "rate_limited", headers: ["retry-after": "30"]))
        let again = try await m.currentSession()
        #expect(again.id == first.id)
    }

    @Test func coreRestartIsRecoveredFromSilently() async throws {
        let h = try Harness()
        let conn = try h.connection()
        _ = try await conn.client.getMe()
        let before = h.core.sessionsIssued
        h.core.restart()
        let me = try await conn.client.getMe()
        #expect(try me.ok.body.json.device.name == "Test Mac")
        #expect(h.core.sessionsIssued == before + 1)
    }

    @Test func clockSkewLearnsTheOffsetAndRetriesOnce() async throws {
        let h = try Harness()
        h.core.serverOffset = 3600
        let conn = try h.connection()
        _ = try await conn.client.getMe()
        let offset = await conn.sessions.clockOffset
        #expect(abs(offset - 3600) <= 1)
        // One retry only: a Core that keeps refusing is an error, not a loop.
        h.core.serverOffset = 7200
        h.core.fail("/api/v1/me", .init(status: 401, code: "clock_skew", extra: ["server_time": 1]))
        await #expect(throws: (any Error).self) { _ = try await conn.client.getMe() }
    }

    @Test func unreasonableSkewIsNotFollowed() async throws {
        let h = try Harness()
        let m = try h.sessions()
        let retry = await m.retry(after: .clockSkew(serverTime: 5), sessionID: nil, retried: [])
        #expect(retry == nil)
    }

    @Test func aCoreThatIsNotThePinnedOneIsRefusedBeforeAnythingIsSigned() async throws {
        let h = try Harness(pinned: Wire.fingerprint(spki: SoftwareKey(key: .init()).spki))
        let m = try h.sessions()
        await #expect(throws: CoreError.self) { _ = try await m.currentSession() }
        #expect(h.core.signedRequests() == 0)
        #expect(h.core.requests(to: "/handshake/challenge").isEmpty)
    }

    @Test func handshakeFailsClosed() async throws {
        // A 404 (an older Core or an impostor): no fallback to GET /handshake.
        var h = try Harness()
        h.core.handshakeStatus = 404
        var thrown: CoreError?
        do { _ = try await h.sessions().currentSession() } catch { thrown = error as? CoreError }
        guard case .coreIdentityMismatch? = thrown else {
            Issue.record("\(String(describing: thrown))")
            return
        }
        #expect(h.core.log.count == 1)
        // A core_sig made for another host does not verify.
        h = try Harness()
        let wrongHost = FakeCore(clock: h.clock, host: "other.example")
        wrongHost.coreKey = h.core.coreKey
        let sessions = SessionManager(
            endpoint: try CoreEndpoint(h.identity.endpoint), identity: h.identity, key: h.key, http: wrongHost,
            clock: h.clock)
        await #expect(throws: CoreError.self) { _ = try await sessions.currentSession() }
        #expect(wrongHost.signedRequests() == 0)
    }

    @Test func noSharedMinorStops() async throws {
        let h = try Harness()
        h.core.supportedMinors = [40, 41]
        await #expect(throws: CoreError.noSharedMinor(builtFor: 33, serverSupported: [40, 41])) {
            _ = try await h.sessions().currentSession()
        }
        h.core.supportedMinors = nil
        await #expect(throws: CoreError.self) { _ = try await h.sessions().currentSession() }
    }

    @Test func olderServersNegotiateDown() async throws {
        let h = try Harness()
        h.core.supportedMinors = Array(0...12)
        let conn = try h.connection()
        try await conn.connect()
        #expect(await conn.negotiatedMinor == 12)
        let has12 = await conn.serverSupports(minor: 12)
        let has13 = await conn.serverSupports(minor: 13)
        #expect(has12 && !has13)
        await conn.close()
    }
}

@Suite struct MiddlewareTests {
    @Test func signsEveryRequestWithTheSession() async throws {
        let h = try Harness()
        let conn = try h.connection()
        let me = try await conn.client.getMe()
        #expect(try me.ok.body.json.device.id == h.identity.deviceID)
        let sent = try #require(h.core.requests(to: "/api/v1/me").first)
        #expect(sent.headers["ainkrad-session"]?.hasPrefix("s_") == true)
        #expect(sent.headers["authorization"] == nil)
    }

    @Test func rateLimitIsThrownWithRetryAfter() async throws {
        let h = try Harness()
        let conn = try h.connection()
        h.core.fail("/api/v1/me", .init(status: 429, code: "rate_limited", headers: ["retry-after": "30"]))
        do {
            _ = try await conn.client.getMe()
            Issue.record("no error")
        } catch {
            #expect(CoreError.unwrapping(error) == .rateLimited(retryAfter: 30))
        }
    }

    @Test func refusalsMapToCoreErrors() async throws {
        let h = try Harness()
        let conn = try h.connection()
        for (status, code, expected) in [
            (403, "step_up_required", CoreError.stepUpRequired), (403, "forbidden_scope", .forbiddenScope),
            (401, "auth_failed", .authFailed),
        ] {
            h.core.fail("/api/v1/me", .init(status: status, code: code))
            do {
                _ = try await conn.client.getMe()
                Issue.record("no error")
            } catch {
                #expect(CoreError.unwrapping(error) == expected)
            }
        }
    }

    @Test func oversizedBodiesAreRefusedLocally() async throws {
        let h = try Harness()
        let mw = SigningMiddleware(sessions: try h.sessions())
        var req = HTTPRequestShim.make()
        req.path = "/api/v1/x"
        await #expect(throws: CoreError.bodyTooLarge) {
            _ = try await mw.intercept(
                req, body: .init(Data(count: (1 << 20) + 1)), baseURL: URL(string: "http://127.0.0.1:7700")!,
                operationID: "x"
            ) { _, _, _ in throw CoreError.protocolViolation("not reached") }
        }
        #expect(h.core.log.isEmpty, "nothing was sent")
    }
}
