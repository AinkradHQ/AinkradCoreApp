import Foundation
import Testing

@testable import Brain

/// The room Overview: the Core's JSON, the writing flow, and approving or editing the instructions.
@MainActor
struct RoomOverviewTests {
    func make(_ state: OverviewState, approved: Bool = false) async -> BrainModel {
        var s = SampleBrainService.Scenario()
        s.m3 = true
        s.overview = state
        s.overviewApproved = approved
        let host = FakeHost()
        let model = BrainModel(host: host)
        model.use(SampleBrainService(s, pace: .milliseconds(1)))
        await model.reload()
        model.roomOverview.pollEvery = .milliseconds(2)
        return model
    }

    @Test func decodesTheCoreAnswer() throws {
        let json = """
            {"state":"written","written_at":"2026-11-16T08:00:00Z","model":"the local model",
             "overview":{"summary":"One.\\n\\nTwo.","facts":{"stack":"Go","last_activity":"today"},
             "rules":{"workflow":[{"text":"Merge, never squash.","sources":["a","b"]}]},"instructions":"Be brief."},
             "instructions_approved_at":null}
            """
        let o = try JSONDecoder().decode(RoomOverview.self, from: Data(json.utf8))
        #expect(o.writer == "the local model" && o.detail.isEmpty && o.instructionsText == "Be brief.")
        #expect(o.state == .written && !o.instructionsApproved)
        #expect(o.overview?.paragraphs == ["One.", "Two."])
        #expect(o.overview?.facts.rows.map(\.label) == ["Stack", "Last activity"])
        #expect(o.overview?.rules.groups.map(\.title) == ["Workflow"])
        #expect(o.overview?.rules.workflow[0].sources == ["a", "b"])
        let w = try JSONDecoder().decode(
            RoomOverview.self, from: Data(#"{"state":"writing","progress":{"done":2,"total":9}}"#.utf8))
        #expect(w.progress == OverviewProgress(done: 2, total: 9) && w.overview == nil)
        #expect(try JSONDecoder().decode(OverviewState.self, from: Data(#""needs_account""#.utf8)) == .needsAccount)
    }

    @Test func aRoomOpensOnItsOverviewWhereTheServiceWritesOne() async {
        let model = await make(.written)
        #expect(model.candidates.paneMode == .overview)
        #expect(model.service?.overviewService != nil)
        let plain = BrainModel(host: FakeHost())
        plain.use(SampleBrainService())
        #expect(plain.service?.overviewService == nil && !plain.servesOverview)
        #expect(model.servesOverview)
    }

    @Test func everyStateLoads() async {
        for state in [OverviewState.notWritten, .writing, .written, .failed, .needsAccount, .cloudOff] {
            let model = await make(state)
            let o = model.roomOverview!
            await o.load("acme-shop")
            #expect(o.current?.state == state && o.phase == .ready)
        }
    }

    @Test func writingShowsAtOnceThenWatchesUntilWritten() async {
        let model = await make(.notWritten)
        let o = model.roomOverview!
        await o.load("acme-shop")
        await o.write("acme-shop")
        #expect(o.current?.state == .writing)
        await o.watch("acme-shop")
        #expect(o.current?.state == .written)
        #expect(o.current?.overview?.rules.never.isEmpty == false)
    }

    @Test func approveThenEditKeepsTheTextAndApproves() async {
        let model = await make(.written)
        let o = model.roomOverview!
        await o.load("acme-shop")
        #expect(o.current?.instructionsApproved == false)
        await o.approve("acme-shop")
        #expect(o.current?.instructionsApproved == true)
        o.startEdit()
        #expect(o.editing && o.draft == o.current?.instructionsText)
        o.draft = "  "
        #expect(!o.canSave)
        o.draft = "Use tabs."
        await o.save("acme-shop")
        #expect(!o.editing && o.current?.instructionsText == "Use tabs.")
        #expect(o.current?.instructionsApproved == true)
    }

    @Test func cancelLeavesTheInstructionsAlone() async {
        let model = await make(.written)
        let o = model.roomOverview!
        await o.load("acme-shop")
        let before = o.current?.instructionsText
        o.startEdit()
        o.draft = "Something else"
        o.cancelEdit()
        #expect(!o.editing && o.current?.instructionsText == before)
    }

    @Test func everyCitedItemHasATitle() async throws {
        let model = await make(.written)
        let o = model.roomOverview!
        await o.load("acme-shop")
        let rule = try #require(o.current?.overview?.rules.workflow.first)
        #expect(rule.sources.count == 14)
        let titles = try #require(o.current?.sourceTitles)
        #expect(rule.sources.allSatisfy { titles[$0] != nil })
        #expect(titles["s0"] == "Release checklist" && titles["s3"] == "Sprint 14 retro")
    }

    @Test func leavingARoomClearsItsOverview() async {
        let model = await make(.written)
        let o = model.roomOverview!
        await o.load("acme-shop")
        model.view("app")
        #expect(o.current == nil && o.roomID == nil)
    }

    // MARK: the Core's routes

    private let base = "/modules/brain/v1/rooms/acme/overview"
    nonisolated static func view() -> [String: Any] {
        [
            "room": "acme", "state": "written", "detail": "", "written_at": "2026-11-16T08:00:00Z",
            "model": "claude:work", "instructions": "Edited.", "instructions_approved_at": NSNull(),
            "progress": ["total": 1, "done": 1, "failed": 0, "room": NSNull()],
            "overview": ["summary": "One."], "source_titles": ["a": "Deploy runbook"],
        ]
    }

    @Test func theCoreViewReadsAndTheWriterIsNamed() async throws {
        let t = FakeBrainTransport()
        t.routes["GET \(base)"] = { _ in Self.view() }
        let o = try await CoreBrainService(transport: t).overviewService!.roomOverview(room: "acme")
        #expect(
            o.sourceTitles == ["a": "Deploy runbook"] && o.writer == "Claude, work"
                && o.progress == OverviewProgress(done: 1, total: 1))
        #expect(o.instructionsText == "Edited." && !o.instructionsApproved)
    }

    @Test func writingAnOpenOverviewIsNotAnError() async throws {
        let t = FakeBrainTransport()
        t.routes["POST \(base)/write"] = { _ in throw BrainHTTPError(status: 409, code: "overview_open") }
        try await CoreBrainService(transport: t).overviewService!.writeOverview(room: "acme")
        t.routes["POST \(base)/write"] = { _ in throw BrainHTTPError(status: 500, code: "internal") }
        await #expect(throws: BrainFailure.self) {
            try await CoreBrainService(transport: t).overviewService!.writeOverview(room: "acme")
        }
    }

    @Test func instructionsGoAsTextAndApprovalAndTooLongIsWorded() async throws {
        let t = FakeBrainTransport()
        let sent = Box()
        t.routes["PATCH \(base)/instructions"] = { body in
            sent.body = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return Self.view()
        }
        let s = CoreBrainService(transport: t).overviewService!
        try await s.setInstructions(room: "acme", text: "Edited.", approved: true)
        #expect(sent.body?["text"] as? String == "Edited." && sent.body?["approved"] as? Bool == true)
        try await s.setInstructions(room: "acme", text: nil, approved: false)
        #expect(sent.body?["text"] == nil && sent.body?["approved"] as? Bool == false)
        t.routes["PATCH \(base)/instructions"] = { _ in throw BrainHTTPError(status: 400, code: "instructions_too_long")
        }
        do { try await s.setInstructions(room: "acme", text: "x", approved: true) } catch let f as BrainFailure {
            #expect(f.sentence.contains("too long"))
        }
    }
}

private final class Box: @unchecked Sendable { var body: [String: Any]? }
