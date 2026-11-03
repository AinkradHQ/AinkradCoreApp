import AinkradClient
import Foundation
import Testing

@testable import CoreKit

// Against a real local Core, only when `CORE_IT=1`. `scripts/core-it.sh` starts the Core, bootstraps the first device with
// ainkradctl, makes a pairing code, approves the SAS this test writes to CORE_IT_SAS_FILE, and triggers an event once this test
// writes CORE_IT_LIVE_FILE. Never run it by hand without the script: it needs those files and a code that lives 5 minutes.

private let env = ProcessInfo.processInfo.environment

private final class Seen: @unchecked Sendable {
    var replayed: [Int64] = []
    var live = false
    var fresh: Int64?
}

private func need(_ name: String) throws -> String { try #require(env[name], "\(name) is not set") }

private func within<T: Sendable>(_ seconds: Int, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CoreError.offline("timed out after \(seconds) s")
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

@Suite(.serialized) struct LiveIntegrationTests {
    @Test(.enabled(if: env["CORE_IT"] == "1"))
    func pairsOpensASessionReadsAndFollowsEvents() async throws {
        let url = try #require(URL(string: try need("CORE_IT_URL")))
        let store = makeMemoryKeyStore()

        // Pair as a new device with the typed code over plain loopback; compute the SAS ourselves.
        let pairing = DevicePairing(keyStore: store)
        let claim = try await pairing.claim(try .parse(try need("CORE_IT_CODE")), endpoint: url)
        print("IT claimed device=\(claim.deviceID) sas=\(claim.sas) core_fp=\(claim.coreFingerprint)")
        try claim.sas.write(toFile: try need("CORE_IT_SAS_FILE"), atomically: true, encoding: .utf8)
        // The approver compares the SAS (ainkradctl is handed this one); matching, the user confirms it here.
        try await pairing.confirmSAS()
        try await within(60) { try await pairing.awaitApproval(timeout: .seconds(55)) }
        print("IT approved")

        // Session, GET /api/v1/me through the signed generated client.
        let conn = try CoreConnection.open(keyStore: store)
        let session = try await conn.connect()
        let me = try await conn.client.getMe().ok.body.json
        print(
            "IT me.device=\(me.device.id) session=\(session.id) minor=\(String(describing: await conn.negotiatedMinor))"
        )
        #expect(me.device.id == claim.deviceID)
        #expect(await conn.negotiatedMinor != nil)

        // Replay (from 0) then the WebSocket, then one event produced after it is live.
        let seen = Seen()
        let stream = conn.events(after: 0)
        let liveFile = try need("CORE_IT_LIVE_FILE")
        try await within(60) {
            for await update in stream {
                switch update {
                case .reconnecting(let why): print("IT stream reconnecting: \(String(describing: why))")
                case .gap(let f): print("IT stream gap floor=\(f)")
                case .event(let e):
                    if seen.live {
                        seen.fresh = e.seq
                        return
                    }
                    seen.replayed.append(e.seq)
                case .live:
                    seen.live = true
                    try "live".write(toFile: liveFile, atomically: true, encoding: .utf8)
                case .ended(let e): throw e
                }
            }
        }
        let (replayed, fresh) = (seen.replayed, seen.fresh)
        print(
            "IT replayed \(replayed.count) events (seqs \(replayed.first ?? 0)...\(replayed.last ?? 0)), live event seq=\(fresh ?? -1)"
        )
        #expect(!replayed.isEmpty && replayed == replayed.sorted())
        #expect(fresh != nil && fresh! > (replayed.last ?? 0))

        // Refresh: a new session opens with no user interaction, and the API still answers under it.
        let renewed = try await conn.sessions.openSession()
        #expect(renewed.id != session.id)
        let again = try await conn.client.getMe().ok.body.json
        #expect(again.device.id == claim.deviceID)
        print("IT refreshed session \(session.id) -> \(renewed.id)")

        // The Core refuses a client whose pin is another Core's, with nothing signed sent.
        let wrongPin = PairedIdentity(
            deviceID: claim.deviceID, coreFingerprint: Wire.fingerprint(spki: Data(repeating: 1, count: 91)),
            endpoint: url)
        let http = URLSessionHTTP(endpoint: try CoreEndpoint(url), session: makeCoreSession())
        await #expect(throws: CoreError.self) {
            _ = try await CoreHandshake.prove(
                http: http, host: try CoreEndpoint(url).host, pinned: wrongPin.coreFingerprint)
        }
        await conn.close()
    }
}
