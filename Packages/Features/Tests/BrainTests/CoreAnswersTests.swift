import Foundation
import Testing

@testable import Brain

/// The Core's real answers for what the Inbox and a room's Items tab call, recorded from a local Core by
/// `scripts/brain-it.sh` (made-up rooms and sources, no records), trimmed to two rows. Each must decode with the app's types.
private enum Answer {
    static let rooms = #"""
        [{"id":"lantern-c5220b","name":"Lantern","kind":"general","state":"active","review_days":90,"sources":250,"open":true},{"id":"northwind-84e2cd","name":"Northwind","kind":"general","state":"active","review_days":90,"sources":1700,"open":true}]
        """#
    static let inbox = #"{"items":[],"waiting":0}"#
    static let distils = "[]"
    static let policy = #"""
        {"room":"lantern-c5220b","model":"cloud","allowed_providers":["approved_cloud"],"auto_accept":[],"min_sources":1,"accounts":[],"local_models":[],"lease_hours":24,"review_days":90}
        """#
    static let access = #"{"room":"lantern-c5220b","project":[],"runner":[],"session":[]}"#
    static let latest = #"""
        {"items":[{"item_id":"5G9PEWYKVTW0PZ5XQ4465P76E3","type":"source","source_kind":"claude_code","title":"Lantern session 167","started_at":"2026-10-28T23:47:00Z"},{"item_id":"FC4S491TT4TAEYTF6651QYSR11","type":"source","source_kind":"claude_code","title":"Lantern session 139","started_at":"2026-10-28T19:19:00Z"}],"records":0}
        """#
    static let search = #"""
        {"hits":[{"item_id":"02JTXG547XNZ3Y1ETFJ0RAZHBN","source_kind":"claude_code","title":"Lantern session 32","snippet":"…the build step, a «cache» key and a retry rule 224.","started_at":"2026-10-05T08:32:00Z"}]}
        """#
    static let sources = #"""
        [{"id":"core_transcript","device":"core","kind":"core_transcript","enabled":true,"roots":[],"cursor":{},"last_run":null,"items":0,"runner":null}]
        """#
}

/// Answers each path with its recorded JSON, or a 404 as the Core's router does for a route it has not got.
private final class Recorded: BrainTransport, @unchecked Sendable {
    /// The policy call ends as a cancelled request does when SwiftUI cancels the view's task.
    var cancelPolicy = false
    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let p = String(path.dropFirst(BrainRoutes.base.count).split(separator: "?")[0])
            .replacingOccurrences(of: "northwind-84e2cd", with: "lantern-c5220b")
        if cancelPolicy, p.hasSuffix("/policy") { throw CancellationError() }
        let room = "/rooms/lantern-c5220b"
        let json: String? =
            switch p {
            case "/rooms": Answer.rooms
            case room + "/inbox": Answer.inbox
            case room + "/distils": Answer.distils
            case room + "/policy": Answer.policy
            case room + "/access": Answer.access
            case room + "/latest": Answer.latest
            case room + "/search": Answer.search
            case "/sources": Answer.sources
            default: nil
            }
        guard let json else { throw BrainHTTPError(status: 404, code: "unknown", message: "HTTP 404") }
        return Data(json.utf8)
    }
}

struct CoreAnswersTests {
    let service = CoreBrainService(transport: Recorded())

    @Test func everyInboxAndItemsAnswerDecodes() async throws {
        let rooms = try await service.rooms()
        #expect(rooms.map(\.name) == ["Lantern", "Northwind"])
        #expect(rooms.first?.counts?.records == 250)
        let inbox = try await service.candidates()
        #expect(inbox.items.isEmpty && inbox.queued.isEmpty)
        let policy = try await service.policy(room: "lantern-c5220b")
        #expect(policy.model == .cloud && !policy.autoAccept)
        #expect(try await service.roomAccess(room: "lantern-c5220b") == RoomAccess())
        let hits = try await service.search(room: "lantern-c5220b", query: "cache")
        #expect(hits.first?.title == "Lantern session 32")
        #expect(try await service.sources().map(\.id) == ["core_transcript"])
    }

    /// A room with sources and no records lists its sources, and says nothing is distilled.
    @Test func itemsListTheSourcesOfARoomWithNoRecords() async throws {
        let latest = try await service.latest(room: "lantern-c5220b")
        #expect(latest.records == 0)
        #expect(latest.items.map(\.title) == ["Lantern session 167", "Lantern session 139"])
        #expect(latest.items.allSatisfy { $0.type == "source" && $0.sourceKind == "claude_code" })
    }

    @Test func aDecodeErrorNamesTheFieldAndTheScreenSaysSo() async throws {
        struct Two: Decodable { var items: [LatestItem] }
        let bad = Data(#"{"items":[{"item_id":"a","type":"source","source_kind":"x","title":"t"}]}"#.utf8)
        let why = BrainRoutes.describe(
            try #require(throws: DecodingError.self) { try JSONDecoder().decode(Two.self, from: bad) })
        #expect(why == "items.0.started_at is missing")
        let sentence = BrainWords.failure(BrainHTTPError(status: 200, code: "bad_answer", message: why))
        #expect(sentence == "The Core's answer could not be read: items.0.started_at is missing.")
    }

    @Test func aConnectionFailureSaysItsReasonNotSomethingWentWrong() {
        struct TimedOut: LocalizedError { var errorDescription: String? { "The Core cannot be reached: timed out" } }
        #expect(BrainWords.failure(TimedOut()) == "The Core cannot be reached: timed out")
        struct Odd: Error {}
        #expect(BrainWords.failure(Odd()) == "The Core did not answer.")
    }

    /// The Inbox reads each room's policy in a view task. Leaving the tab cancels it mid-call; on 0.8.4 that left "Something
    /// went wrong. Nothing was changed." over an empty Inbox. A cancelled read is not a failure.
    @MainActor @Test func leavingTheInboxMidLoadLeavesNoFailure() async throws {
        let t = Recorded()
        t.cancelPolicy = true
        let model = BrainModel(host: FakeHost())
        model.use(CoreBrainService(transport: t))
        let c = try #require(model.candidates)
        await c.load()
        #expect(c.phase == .ready && c.items.isEmpty)
        await c.loadPolicy("lantern-c5220b")
        #expect(c.notice == nil)
    }
}
