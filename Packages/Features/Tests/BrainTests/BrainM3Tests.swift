import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

@MainActor
struct BrainM3Tests {
    func make(noLocalModel: Bool = false) async -> (BrainModel, FakeHost, BrainCandidates) {
        let host = FakeHost()
        let model = BrainModel(host: host)
        var s = SampleBrainService.Scenario()
        s.m3 = true
        s.noLocalModel = noLocalModel
        model.use(SampleBrainService(s))
        await model.reload()
        return (model, host, model.candidates)
    }

    // MARK: Inbox

    @Test func theInboxListsEveryOpenRoomsCandidatesAndTheQueue() async {
        let (m, _, c) = await make(noLocalModel: true)
        defer { withExtendedLifetime(m) {} }
        #expect(c.items.count == 7 && m.tabCount(.inbox) == 7)
        #expect(c.inbox.queuedItems == 23 && c.inbox.queued.map(\.name) == ["Personal notes", "workan-space"])
        #expect(c.selected?.id == "c1")
    }

    @Test func acceptFilesItAndSelectsTheNext() async {
        let (m, _, c) = await make()
        defer { withExtendedLifetime(m) {} }
        #expect(await c.accept("c1"))
        #expect(c.items.count == 6 && !c.items.contains { $0.id == "c1" })
        #expect(c.selected?.id == "c2" && m.tabCount(.inbox) == 6)
    }

    @Test func rejectRemovesItWithoutTouchID() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        #expect(await c.reject("c2"))
        #expect(c.items.count == 6 && host.reasons.isEmpty)
    }

    @Test func editSavesYourWordsThenAccepts() async {
        let (m, _, c) = await make()
        defer { withExtendedLifetime(m) {} }
        c.startEdit("c1")
        c.setDraft(kind: .landmine, text: "  New words.  ")
        #expect(c.isEdited(c.items[0]))
        #expect(await c.saveEdit())
        #expect(c.draft == nil && !c.items.contains { $0.id == "c1" })
    }

    @Test func anEmptyEditCannotBeSavedAndCancelKeepsTheOriginal() async {
        let (m, _, c) = await make()
        defer { withExtendedLifetime(m) {} }
        c.startEdit("c1")
        c.setDraft(kind: .decision, text: "   ")
        #expect(await c.saveEdit() == false && c.items.count == 7)
        c.cancelEdit()
        #expect(c.draft == nil && !c.isEdited(c.items[0]))
    }

    @Test func filtersNarrowTheList() async {
        let (m, _, c) = await make()
        defer { withExtendedLifetime(m) {} }
        c.kindFilter = .openThread
        #expect(c.visible.count == 2)
        c.roomFilter = "app"
        #expect(c.visible.map(\.id) == ["c7"])
    }

    // MARK: room policy and auto-accept

    @Test func autoAcceptAsksForTouchIDAndStartsWithTheLowRiskKinds() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadPolicy("core")
        #expect(c.policy("core")?.autoAccept == false)
        await c.setAutoAccept("core", true)
        #expect(host.reasons.count == 1)
        #expect(c.policy("core")?.autoAccept == true && c.policy("core")?.kinds == [.fact, .openThread])
        await c.toggleKind("core", .decision)
        #expect(c.policy("core")?.kinds == [.fact, .openThread, .decision] && host.reasons.count == 2)
        await c.setAutoAccept("core", false)
        #expect(c.policy("core")?.autoAccept == false)
    }

    @Test func aCancelledTouchIDLeavesThePolicyAsItWas() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadPolicy("core")
        host.declines = true
        await c.setAutoAccept("core", true)
        await c.setModel("core", .localOnly)
        #expect(c.policy("core")?.autoAccept == false && c.policy("core")?.model == .cloud && c.notice == nil)
    }

    @Test func aPolicyChangeAsksAndCloudClearsTheLocalQueue() async {
        let (m, host, c) = await make(noLocalModel: true)
        defer { withExtendedLifetime(m) {} }
        await c.loadPolicy("personal")
        #expect(c.policy("personal")?.needsLocalModel == true)
        await c.setModel("personal", .cloud)
        #expect(host.reasons.count == 1 && c.policy("personal")?.model == .cloud)
        #expect(c.policy("personal")?.needsLocalModel == false)
        await c.setModel("personal", .cloud)
        #expect(host.reasons.count == 1)  // no change, no prompt
    }

    // MARK: runner history

    @Test func everyTurnOnOfRunnerHistoryAsksForTouchID() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadRunners()
        await c.toggleRunner("vps-1")
        #expect(c.runnerSheet?.tools == ["claude_code", "codex"])  // not installed stays off
        #expect(await c.turnOnRunner())
        #expect(c.runners.first { $0.id == "vps-1" }?.enabled == true && host.reasons.count == 1)
        await c.toggleRunner("vps-1")  // off: no prompt
        #expect(c.runners.first { $0.id == "vps-1" }?.enabled == false && host.reasons.count == 1)
        await c.toggleRunner("vps-1")
        #expect(await c.turnOnRunner())
        #expect(host.reasons.count == 2)
    }

    @Test func aCancelledTouchIDKeepsTheRunnerOffAndTheSheetOpen() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadRunners()
        await c.toggleRunner("vps-1")
        host.declines = true
        #expect(await c.turnOnRunner() == false)
        #expect(c.runners.first { $0.id == "vps-1" }?.enabled == false && c.runnerSheet != nil)
    }

    @Test func anOfflineRunnerHasNoSwitch() async {
        let (m, _, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadRunners()
        await c.toggleRunner("studio")
        #expect(c.runnerSheet == nil)
    }

    // MARK: the Core's routes

    @Test func coreCandidatesComeFromEachOpenRoomsInboxNewestFirst() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        @Sendable func room(_ id: String, _ name: String, open: Bool) -> [String: Any] {
            [
                "id": id, "name": name, "kind": "product", "state": "active", "review_days": 90, "sources": 3,
                "open": open,
            ]
        }
        @Sendable func record(_ id: String, _ type: String, _ body: String, _ day: String, _ sources: [String])
            -> [String: Any]
        {
            [
                "id": id, "type": type, "status": "candidate", "body": body, "tags": [String](), "sources": sources,
                "created_at": "2026-11-\(day)T10:00:00Z",
            ]
        }
        t.routes["GET \(base)/rooms"] = { _ in [room("r1", "Alpha", open: true), room("r2", "Beta", open: false)] }
        t.routes["GET \(base)/rooms/r1/inbox"] = { _ in
            [
                "waiting": 2,
                "items": [
                    record("a", "rule", "Old", "01", ["i1"]), record("b", "decision", "New", "02", ["i1", "i2"]),
                ],
            ]
        }
        t.routes["GET \(base)/rooms/r1/distils"] = { _ in [Any]() }
        t.routes["GET \(base)/rooms/r2/distils"] = { _ in
            [["state": "needs_local_model", "sources": 5], ["state": "done", "sources": 9]]
        }
        let inbox = try await CoreBrainService(transport: t).candidates()
        #expect(inbox.items.map(\.id) == ["b", "a"])
        #expect(inbox.items[1].kind == .landmine && inbox.items[0].sources.count == 2)
        #expect(inbox.queued == [QueuedRoom(room: "r2", name: "Beta", items: 5)])
    }

    @Test func coreEditSendsTheTypeAndTheTextAndPolicySendsFactsOnly() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        nonisolated(unsafe) var sent: [[String: Any]] = []
        let note: @Sendable (Data?) -> Void = { b in
            sent.append((try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:])
        }
        t.routes["POST \(base)/rooms/r1/inbox/a"] = { b in
            note(b)
            return [
                "id": "a", "type": "decision", "status": "accepted", "body": "x", "tags": [String](),
                "sources": [String](), "created_at": "2026-11-01T10:00:00Z",
            ]
        }
        let svc = CoreBrainService(transport: t)
        try await svc.decide("a", room: "r1", .edit(kind: .landmine, text: "Words"))
        #expect(sent.last?["action"] as? String == "edit" && sent.last?["type"] as? String == "rule")
        @Sendable func policy(_ auto: [String]) -> [String: Any] {
            ["room": "r1", "model": "cloud", "allowed_providers": ["approved_cloud"], "auto_accept": auto]
        }
        t.routes["GET \(base)/rooms/r1/policy"] = { _ in policy([]) }
        t.routes["GET \(base)/rooms/r1/distils"] = { _ in [Any]() }
        t.routes["PATCH \(base)/rooms/r1/policy"] = { b in
            note(b)
            return policy(["fact", "preference", "summary"])
        }
        let p = try await svc.setPolicy(room: "r1", PolicyChange(autoAccept: true, kinds: [.fact, .decision]))
        #expect((sent.last?["auto_accept"] as? [String]) == ["fact", "preference", "summary"])
        #expect(p.autoAccept && p.kinds == [.fact] && p.autoKindsAllowed == [.fact])
    }

    @Test func runnerHistoryIsTheRunnerSourceOnTheSourcesRoute() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        @Sendable func row(_ id: String, _ on: Bool) -> [String: Any] {
            [
                "id": id, "device": "vps-1", "kind": "claude_code", "enabled": on, "roots": [String](),
                "cursor": [String: Any](),
            ]
        }
        nonisolated(unsafe) var sent: [String: Any] = [:]
        t.routes["GET \(base)/sources"] = { _ in [row("core_transcript", true), row("runner-vps1", false)] }
        t.routes["PUT \(base)/sources/runner-vps1"] = { b in
            sent = (try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            return row("runner-vps1", true)
        }
        let svc = CoreBrainService(transport: t)
        let list = try await svc.runners()
        #expect(list.map(\.id) == ["vps1"] && list[0].name == "vps-1" && list[0].enabled == false)
        let on = try await svc.setRunnerHistory("vps1", enabled: true, tools: [])
        #expect(on.enabled && sent["enabled"] as? Bool == true)
    }

    @Test func aSyncThatFindsNoSharedHistorySaysSo() {
        var r = SyncResultWire()
        r.idle = "no_connection"
        #expect(r.summary().contains("doesn't share its history"))
    }
}
