import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// Room settings (B10-02): auto-save per kind, the daily cap, retention with its count first, "Clean up memory…" and the
/// room card, on the Core's wire shapes (`policy.rs`, `retention.rs`, `redistil_routes.rs`) and on the sample.
@MainActor
struct RoomCareTests {
    private func real(_ t: FakeBrainTransport) -> CoreBrainService { CoreBrainService(transport: t) }

    private func make(_ s: SampleBrainService.Scenario = .init()) async -> (BrainModel, FakeHost) {
        let host = FakeHost()
        let m = BrainModel(host: host)
        var s = s
        s.m3 = true
        m.use(SampleBrainService(s, pace: .zero))
        await m.reload()
        m.care.pollEvery = .milliseconds(1)
        m.view("core")
        await m.candidates.loadPolicy("core")
        return (m, host)
    }

    // MARK: the wire

    nonisolated private static func policyJSON(_ auto: [String]) -> [String: Any] {
        [
            "room": "r1", "model": "cloud", "auto_accept": auto, "min_sources": 1, "daily_distils": 12,
            "retention_days": NSNull(),
        ]
    }

    @Test func thePolicyCarriesTheCapAndRetentionAndPatchesOnlyWhatChanged() async throws {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/rooms/r1/policy"] = { _ in Self.policyJSON(["fact", "preference"]) }
        t.routes["GET /modules/brain/v1/rooms/r1/distils"] = { _ in [Any]() }
        final class Box: @unchecked Sendable { var body: [String: Any] = [:] }
        let box = Box()
        t.routes["PATCH /modules/brain/v1/rooms/r1/policy"] = { data in
            box.body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
            var p = Self.policyJSON(["fact", "preference"])
            p["daily_distils"] = 25
            p["retention_days"] = 90
            return p
        }
        let svc = real(t)
        let now = try await svc.policy(room: "r1")
        #expect(now.dailyDistils == 12 && now.retentionDays == nil)
        #expect(now.savedTypes == ["fact", "preference"] && now.saves(.preference) && !now.saves(.rule))
        let after = try await svc.setPolicy(room: "r1", PolicyChange(dailyDistils: 25, retentionDays: 90))
        #expect(after.dailyDistils == 25 && after.retentionDays == 90)
        // Only the two fields changed: the saved kinds are not sent.
        #expect(box.body["daily_distils"] as? Int == 25 && box.body["retention_days"] as? Int == 90)
        #expect(box.body["auto_accept"] == nil && box.body["min_sources"] == nil)
    }

    @Test func autoSaveSendsTheWholeListSoAnUnlistedTypeIsKept() async throws {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/rooms/r1/policy"] = { _ in Self.policyJSON(["fact", "summary"]) }
        t.routes["GET /modules/brain/v1/rooms/r1/distils"] = { _ in [Any]() }
        final class Box: @unchecked Sendable { var body: [String: Any] = [:] }
        let box = Box()
        t.routes["PATCH /modules/brain/v1/rooms/r1/policy"] = { data in
            box.body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
            return Self.policyJSON(["fact", "summary"])
        }
        _ = try await real(t).setPolicy(room: "r1", PolicyChange(types: ["fact", "rule"]))
        #expect(box.body["auto_accept"] as? [String] == ["fact", "rule"])
        _ = try await real(t).setPolicy(room: "r1", PolicyChange(types: []))
        #expect(box.body["auto_accept"] as? [String] == [])
    }

    @Test func aRunReadsTheCoresCountsAndSaysWhatApplyWouldDo() async throws {
        let t = FakeBrainTransport()
        t.routes["POST /modules/brain/v1/rooms/r1/redistil/dry-run"] = { _ in
            [
                "id": "rd1", "room": "r1", "dry_run": true, "state": "done", "total": 20, "read": 20, "kept": 80,
                "new_facts": 4,
                "archived": 1203, "summary": "Would keep 84 facts, archive 1,203 items", "change": NSNull(),
                "detail": "",
                "started_at": "x", "updated_at": "y",
            ]
        }
        t.routes["GET /modules/brain/v1/rooms/r1/redistil"] = { _ in
            [["id": "rd1", "dry_run": true, "state": "running", "total": 20, "read": 5, "detail": ""]]
        }
        let run = try await real(t).startRedistil(room: "r1", dryRun: true)
        #expect(run.state == .done && run.plan == "Keep \(84.formatted()) facts, archive \(1203.formatted()) items")
        let open = try await real(t).redistilStatus(room: "r1")
        #expect(open?.isOpen == true && open?.fraction == 0.25)
    }

    @Test func theCleanUpsOwnRefusalsAreInWords() async {
        let t = FakeBrainTransport()
        t.routes["POST /modules/brain/v1/rooms/r1/redistil/dry-run"] = { _ in
            throw BrainHTTPError(status: 409, code: "nothing_to_redistil")
        }
        await #expect(throws: BrainFailure.self) { try await real(t).startRedistil(room: "r1", dryRun: true) }
        do { _ = try await real(t).startRedistil(room: "r1", dryRun: true) } catch let f as BrainFailure {
            #expect(f.code == "nothing_to_redistil" && f.sentence.contains("nothing to clean up"))
        } catch { Issue.record("expected a BrainFailure") }
    }

    @Test func aCoreWithoutTheCardRouteShowsNoCard() async throws {
        #expect(try await real(FakeBrainTransport()).roomCard(room: "r1") == nil)
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/rooms/r1/card"] = { _ in
            ["text": "Room: A made-up room", "ids": ["a", "b"], "complete": false]
        }
        #expect(
            try await real(t).roomCard(room: "r1")
                == RoomCard(text: "Room: A made-up room", records: 2, complete: false))
    }

    // MARK: auto-save and the cap

    @Test func autoSaveTurnsOneKindOnOrOffAndAsksForTouchID() async {
        let (m, host) = await make()
        let c: BrainCandidates = m.candidates
        #expect(c.policy("core")?.savedTypes.isEmpty == true)
        await c.toggleSave("core", .preference)
        #expect(c.policy("core")?.savedTypes == ["preference"] && c.policy("core")?.autoAccept == true)
        await c.toggleSave("core", .fact)
        #expect(c.policy("core")?.savedTypes == ["fact", "preference"] && host.reasons.count == 2)
        await c.toggleSave("core", .preference)
        await c.toggleSave("core", .fact)
        #expect(c.policy("core")?.savedTypes.isEmpty == true && c.policy("core")?.autoAccept == false)
    }

    @Test func theDailyCapRoundTrips() async {
        let (m, host) = await make()
        #expect(m.candidates.policy("core")?.dailyDistils == 12)
        await m.candidates.setDailyDistils("core", 50)
        #expect(m.candidates.policy("core")?.dailyDistils == 50 && host.reasons.count == 1)
        host.declines = true
        await m.candidates.setDailyDistils("core", 6)
        #expect(m.candidates.policy("core")?.dailyDistils == 50)
    }

    // MARK: retention

    @Test func retentionShowsTheCountFirstAndOnlyThenAsksForTouchID() async {
        let (m, host) = await make()
        let care: RoomCareModel = m.care
        care.askRetention("core", days: 30)
        #expect(care.retentionAsk?.days == 30 && care.retentionAsk?.preview == nil)
        #expect(await until { care.retentionAsk?.preview != nil })
        #expect(care.retentionAsk?.preview?.wouldCompact == 412 && host.reasons.isEmpty)
        #expect(m.candidates.policy("core")?.retentionDays == nil)
        await care.confirmRetention("core")
        #expect(host.reasons.count == 1 && m.candidates.policy("core")?.retentionDays == 30)
        #expect(care.retentionAsk == nil)
        await care.keepEverything("core")
        #expect(m.candidates.policy("core")?.retentionDays == nil)
    }

    @Test func aDeclinedTouchIDKeepsTheAskOpenAndRetentionOff() async {
        let (m, host) = await make()
        m.care.askRetention("core", days: 90)
        #expect(await until { m.care.retentionAsk?.preview != nil })
        host.declines = true
        await m.care.confirmRetention("core")
        #expect(m.candidates.policy("core")?.retentionDays == nil && m.care.retentionAsk?.days == 90)
        m.care.cancelRetention()
        #expect(m.care.retentionAsk == nil)
    }

    @Test func aFailedCountSaysSoAndCannotBeTurnedOn() async {
        var s = SampleBrainService.Scenario()
        s.error = true
        let host = FakeHost()
        let m = BrainModel(host: host)
        s.m3 = true
        m.use(SampleBrainService(s, pace: .zero))
        m.care.askRetention("core", days: 30)
        #expect(await until { m.care.retentionAsk?.failed != nil })
        await m.care.confirmRetention("core")
        #expect(host.reasons.isEmpty)
    }

    // MARK: Clean up memory…

    @Test func theDryRunCountsThenApplyAsksForTouchIDAndUndoRoundTrips() async {
        let (m, host) = await make()
        let care: RoomCareModel = m.care
        care.check("core")
        if case .checking = care.cleanup {} else { Issue.record("the dry run starts at once") }
        #expect(await until { if case .ready = care.cleanup { true } else { false } })
        guard case .ready(let plan) = care.cleanup else { return }
        #expect(plan.plan == "Keep 84 facts, archive \(1203.formatted()) items" && host.reasons.isEmpty)
        care.apply("core")
        #expect(await until { if case .done = care.cleanup { true } else { false } })
        #expect(host.reasons.count == 1)
        guard case .done(let run) = care.cleanup, let change = run.change else {
            Issue.record("no result")
            return
        }
        #expect(run.summary == "Kept 84 facts, archived 1,203 items" && care.undone(change) == nil)
        care.undo(change)
        #expect(await until { care.undone(change) != nil })
        // The result line links to Activity's memory view, where the same change set is listed.
        care.openActivity()
        #expect(m.tab == .activity)
    }

    @Test func aDeclinedTouchIDPutsTheCountBack() async {
        let (m, host) = await make()
        m.care.check("core")
        #expect(await until { if case .ready = m.care.cleanup { true } else { false } })
        host.declines = true
        m.care.apply("core")
        #expect(await until { host.reasons.count == 1 })
        #expect(await until { if case .ready = m.care.cleanup { true } else { false } })
    }

    @Test func cancelStopsARunAndNothingIsApplied() async {
        let (m, host) = await make()
        m.care.pollEvery = .milliseconds(200)
        m.care.check("core")
        #expect(await until { if case .checking(let r) = m.care.cleanup { r != nil } else { false } })
        m.care.cancel("core")
        #expect(await until { m.care.cleanup == .idle })
        #expect(host.reasons.isEmpty)
    }

    @Test func aRoomWithNothingToReadAndAFailingCoreSayWhy() async {
        var s = SampleBrainService.Scenario()
        s.empty = true
        let (m, _) = await make(s)
        m.care.check("core")
        #expect(await until { m.care.cleanup == .nothing })
        m.care.dismiss()
        #expect(m.care.cleanup == .idle)
        var bad = SampleBrainService.Scenario()
        bad.error = true
        let host = FakeHost()
        let f = BrainModel(host: host)
        bad.m3 = true
        f.use(SampleBrainService(bad, pace: .zero))
        f.care.check("core")
        #expect(await until { if case .failed = f.care.cleanup { true } else { false } })
    }

    @Test func aRoomChangeDropsTheOldRoomsRun() async {
        let (m, _) = await make()
        m.care.check("core")
        #expect(await until { if case .ready = m.care.cleanup { true } else { false } })
        await m.care.enter("app")
        #expect(m.care.cleanup == .idle && m.care.roomID == "app")
    }

    // MARK: the room card

    @Test func theCardLoadsAndAnOlderCoreShowsNone() async {
        let (m, _) = await make()
        await m.care.loadCard("core")
        if case .ready(let c) = m.care.card { #expect(c.records == 4 && c.complete) } else { Issue.record("no card") }
        let host = FakeHost()
        let bare = BrainModel(host: host)
        await bare.care.loadCard("core")
        #expect(bare.care.card == RoomCareModel.CardState.none)
    }

    @Test func aFailingCardSaysSoInsteadOfHiding() async {
        var s = SampleBrainService.Scenario()
        s.error = true
        let host = FakeHost()
        let m = BrainModel(host: host)
        s.m3 = true
        m.use(SampleBrainService(s, pace: .zero))
        await m.care.loadCard("core")
        if case .failed = m.care.card {} else { Issue.record("expected a failed card") }
    }
}
