import BrainImport
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// One box per room: ticking is local, Import sends the ticked rooms in one call (API minor 73), an older Core gets the
/// ticked rooms accepted first, the selection survives a restart, and an answer that never came is never "Nothing was
/// changed".
@MainActor
struct ReviewBoxesTests {
    static let base = "/modules/brain/v1/imports/r1"

    func wizard(_ t: FakeBrainTransport, resume: ResumeStore? = nil) -> ImportModel {
        t.routes["POST /modules/brain/v1/imports"] = { _ in ["run": "r1"] }
        t.routes["POST \(Self.base)/items"] = { _ in ["results": []] }
        t.routes["POST \(Self.base)/collected"] = { _ in runView("discovering", stored: 2) }
        t.routes["GET \(Self.base)"] = { _ in runView("review", stored: 2) }
        t.routes["GET \(Self.base)/proposals"] = { _ in [card("alpha"), card("beta"), card("gamma"), card("unsorted")] }
        return ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: t), sources: [FakeSource()], poll: .milliseconds(1),
            resume: resume, pause: { _ in })
    }

    func reviewing(_ m: ImportModel) async {
        m.start()
        for _ in 0..<500 where m.step != .review { try? await Task.sleep(for: .milliseconds(5)) }
    }

    nonisolated static func committed(_ keep: [String]) -> [String: Any] {
        [
            "rooms": keep.map {
                ["proposal": $0, "room": $0, "name": $0, "kind": "product", "sources": 2, "created": true]
                    as [String: Any]
            },
            "held": [String](), "rules_enabled": 0, "state": "committed",
        ]
    }

    @Test func importSendsTheTickedRoomsAndUnsortedInOneCall() async throws {
        let t = FakeBrainTransport()
        let m = wizard(t)
        nonisolated(unsafe) var sent: [String: Any] = [:]
        t.routes["POST \(Self.base)/commit"] = { b in
            sent = (try JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            return Self.committed(["alpha", "gamma"])
        }
        await reviewing(m)
        m.review.keepsInCommit = true
        m.review.setChecked("beta", false)
        m.review.setChecked("unsorted", false)
        #expect(ReviewWords.importTitle(m.review.kept.count) == "Import 2 rooms")
        #expect(
            ReviewWords.willDelete(
                rooms: m.review.dropped.filter { !$0.isUnsorted }.count, unsorted: !m.review.keepUnsorted)
                == "1 room not checked and the Unsorted items will be deleted.")
        await m.commit()
        #expect(m.step == .done)
        #expect(sent["keep"] as? [String] == ["alpha", "gamma"] && sent["keep_unsorted"] as? Bool == false)
        #expect(!t.log.contains { $0.hasPrefix("PATCH") || $0.hasSuffix("/refuse") }, "one call, nothing before it")
    }

    @Test func anOlderCoreGetsTheTickedRoomsAcceptedThenThePlainCommit() async {
        let t = FakeBrainTransport()
        let m = wizard(t)
        nonisolated(unsafe) var body: Data? = Data("x".utf8)
        for id in ["alpha", "beta", "gamma"] {
            t.routes["PATCH \(Self.base)/proposals/\(id)"] = { b in
                let o = (try JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
                return card(id, state: o["state"] as? String ?? "proposed")
            }
        }
        t.routes["POST \(Self.base)/commit"] = { b in
            body = b
            return Self.committed(["alpha", "gamma"])
        }
        await reviewing(m)
        m.review.setChecked("beta", false)
        await m.commit()
        #expect(m.step == .done && body == nil, "the plain commit has no body")
        #expect(
            t.count("PATCH \(Self.base)/proposals/alpha") == 1 && t.count("PATCH \(Self.base)/proposals/gamma") == 1)
        #expect(t.count("PATCH \(Self.base)/proposals/beta") == 0, "an unticked room is left out, not refused")
    }

    @Test func theSelectionSurvivesARestart() async {
        let store = ResumeStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("brain-state-\(UUID().uuidString).json"))
        let m = wizard(FakeBrainTransport(), resume: store)
        await reviewing(m)
        m.review.setChecked("beta", false)
        #expect(store.load().unchecked == ["beta"])
        let again = wizard(FakeBrainTransport(), resume: store)
        await reviewing(again)
        #expect(again.run == "r1")
        #expect(again.review.unchecked == ["beta"])
        #expect(store.load().run == "r1")
        #expect(again.review.kept.map(\.id) == ["alpha", "gamma"])
    }

    @Test func aTimeoutReadsTheRoomsAgainAndNeverSaysNothingChanged() async {
        struct Timeout: LocalizedError {
            var errorDescription: String? { "The Core cannot be reached: The request timed out" }
        }
        let t = FakeBrainTransport()
        let m = wizard(t)
        t.routes["POST \(Self.base)/commit"] = { _ in throw Timeout() }
        await reviewing(m)
        m.review.keepsInCommit = true
        t.routes["GET \(Self.base)/proposals"] = { _ in [card("alpha", state: "committed"), card("unsorted")] }
        await m.commit()
        let n = m.review.notice ?? ""
        #expect(m.step == .review && !n.contains("Nothing was changed"))
        #expect(
            n == "The Core cannot be reached: The request timed out. It may have done it anyway: "
                + "the list shows what it has now.")
        #expect(m.review.cards.first?.state == "committed", "the list was read again")
        #expect(BrainWords.unsure(Timeout()) && !BrainWords.unsure(BrainHTTPError(status: 409, code: "conflict")))
        #expect(!BrainWords.unsure(AdminDeclined()))
    }

    @Test func theCoresDecideAndCommitCodesAreSaidPlainly() {
        func say(_ s: Int, _ c: String, _ m: String = "") -> String {
            BrainWords.failure(BrainHTTPError(status: s, code: c, message: m))
        }
        #expect(say(409, "mixed_employers") == "Two employers are in one room. Split it first.")
        #expect(
            say(400, "bad_request", "Unsorted is not a room: move its items to one")
                == "Unsorted is not a room. Move its items to one.")
        #expect(say(400, "unsorted_not_a_room") == "Unsorted is not a room. Move its items to one.")
        #expect(
            say(409, "conflict", "the run is not in review")
                == "This import is not in review any more. The list shows where it is now.")
        #expect(
            say(409, "conflict", "that room is already imported or merged")
                == "That room was joined into another one. The list is up to date now.")
        #expect(say(429, "rate_limited") == "The Core is busy. Try again in a moment.")
        #expect(
            say(400, "bad_request", "keep names a room that is not in this run")
                == "The Core could not take this: keep names a room that is not in this run.")
        for s in [
            say(409, "mixed_employers"), say(409, "conflict", "x"), say(404, "not_found"), say(400, "bad_request", "x"),
        ] {
            #expect(!s.contains("Something went wrong"))
        }
    }

    @Test func aStaleRoomAnswered409ReadsTheRoomsAgain() async {
        let t = FakeBrainTransport()
        let m = wizard(t)
        await reviewing(m)
        t.routes["POST \(Self.base)/proposals/beta/merge"] = { _ in
            throw BrainHTTPError(status: 409, code: "conflict", message: "that room is already imported or merged")
        }
        let before = t.count("GET \(Self.base)/proposals")
        await m.review.merge("beta", into: "alpha")
        #expect(t.count("GET \(Self.base)/proposals") == before + 1)
        #expect(m.review.notice == "That room was joined into another one. The list is up to date now.")
    }
}
