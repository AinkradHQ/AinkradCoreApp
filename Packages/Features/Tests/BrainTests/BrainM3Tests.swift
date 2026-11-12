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

    @Test func autoAcceptAsksForTouchIDAndStartsWithFacts() async {
        let (m, host, c) = await make()
        defer { withExtendedLifetime(m) {} }
        await c.loadPolicy("core")
        #expect(c.policy("core")?.autoAccept == false)
        await c.setAutoAccept("core", true)
        #expect(host.reasons.count == 1)
        #expect(c.policy("core")?.autoAccept == true && c.policy("core")?.kinds == [.fact])
        await c.toggleKind("core", .decision)
        #expect(c.policy("core")?.kinds == [.fact, .decision] && host.reasons.count == 2)
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
        #expect(c.runnerSheet?.name == "vps-1 (Azure)")
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

    @Test func kindsComeFromTheTypeAndTheTag() {
        #expect(CandidateKind(type: "rule", tags: ["landmine"]) == .landmine)
        #expect(CandidateKind(type: "rule", tags: []) == .rule)
        #expect(CandidateKind(type: "task", tags: ["open-thread", "x"]) == .openThread)
        #expect(CandidateKind(type: "task", tags: []) == .task)
        #expect(CandidateKind(type: "project-state", tags: []) == .projectState)
        #expect(CandidateKind.landmine.retag(["x", "open-thread"]) == ["x", "landmine"])
        #expect(CandidateKind.fact.retag(["landmine"]).isEmpty)
    }

    @Test func coreCandidatesComeFromEachOpenRoomsInboxNewestFirst() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        @Sendable func room(_ id: String, _ name: String, open: Bool) -> [String: Any] {
            [
                "id": id, "name": name, "kind": "product", "state": "active", "review_days": 90, "sources": 3,
                "open": open,
            ]
        }
        @Sendable func record(_ id: String, _ type: String, _ tags: [String], _ day: String) -> [String: Any] {
            [
                "id": id, "type": type, "status": "candidate", "body": "Body \(id)", "tags": tags,
                "distilled_at": "2026-11-\(day)T10:00:00Z", "tool": "claude",
                "distilled_by": ["provider": "anthropic", "account": "Max account"],
                "sources": [
                    [
                        "item_id": "i1", "source_kind": "claude_code", "title": "Session", "quote": "the quote",
                        "started_at": "2026-11-01T09:00:00Z", "room": "Alpha",
                    ]
                ],
            ]
        }
        t.routes["GET \(base)/rooms"] = { _ in [room("r1", "Alpha", open: true), room("r2", "Beta", open: false)] }
        t.routes["GET \(base)/rooms/r1/inbox"] = { _ in
            ["waiting": 2, "items": [record("a", "rule", ["landmine"], "01"), record("b", "decision", [], "02")]]
        }
        t.routes["GET \(base)/rooms/r1/distils"] = { _ in [Any]() }
        t.routes["GET \(base)/rooms/r2/distils"] = { _ in
            [["state": "needs_local_model", "sources": 5], ["state": "done", "sources": 9]]
        }
        let inbox = try await CoreBrainService(transport: t).candidates()
        #expect(inbox.items.map(\.id) == ["b", "a"] && inbox.items[1].kind == .landmine)
        let b = inbox.items[0]
        #expect(b.app == "Claude Code" && b.account == "Anthropic, Max account")
        #expect(b.sources.first?.title == "Session" && b.sources.first?.quote == "the quote")
        #expect(inbox.queued == [QueuedRoom(room: "r2", name: "Beta", items: 5)])
    }

    @Test func coreEditSendsTheTypeAndTheMarkerTagAndPolicySendsTypes() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        nonisolated(unsafe) var sent: [[String: Any]] = []
        let note: @Sendable (Data?) -> Void = { b in
            sent.append((try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:])
        }
        t.routes["POST \(base)/rooms/r1/inbox/a"] = { b in
            note(b)
            return [
                "id": "a", "type": "rule", "status": "accepted", "body": "x", "tags": ["landmine"],
                "sources": [Any](), "distilled_at": "2026-11-01T10:00:00Z",
            ]
        }
        let svc = CoreBrainService(transport: t)
        try await svc.decide("a", room: "r1", .edit(kind: .openThread, text: "Words", tags: ["landmine", "x"]))
        #expect(sent.last?["type"] as? String == "task" && sent.last?["tags"] as? [String] == ["x", "open-thread"])
        @Sendable func policy(_ auto: [String], _ min: Int) -> [String: Any] {
            [
                "room": "r1", "model": "cloud", "allowed_providers": ["approved_cloud"], "auto_accept": auto,
                "min_sources": min, "local_models": [String](),
                "accounts": [["id": 1, "provider": "anthropic", "name": "Max", "state": "active"]],
            ]
        }
        t.routes["GET \(base)/rooms/r1/policy"] = { _ in policy(["preference"], 1) }
        t.routes["GET \(base)/rooms/r1/distils"] = { _ in [Any]() }
        t.routes["PATCH \(base)/rooms/r1/policy"] = { b in
            note(b)
            return policy(["decision", "fact", "preference"], 3)
        }
        let p = try await svc.setPolicy(
            room: "r1", PolicyChange(autoAccept: true, kinds: [.fact, .decision], minSources: 3))
        // Types the app has no row for (preference) are kept; Landmines would send `rule`, Open threads `task`.
        #expect(sent.last?["auto_accept"] as? [String] == ["decision", "fact", "preference"])
        #expect(sent.last?["min_sources"] as? Int == 3)
        #expect(p.kinds == [.fact, .decision] && p.otherAuto == ["preference"] && p.minSources == 3)
        #expect(p.provider == "Anthropic" && p.accounts == ["Max"])
    }

    @Test func turningOnRunnerHistorySharesThenSwitchesTheSourceUnderOneTouchID() async throws {
        let t = FakeBrainTransport()
        let base = BrainRoutes.base
        @Sendable func row(_ on: Bool, offered: Bool) -> [String: Any] {
            [
                "id": "runner-d_1", "device": "d_1", "kind": "claude_code", "enabled": on, "roots": [String](),
                "cursor": [String: Any](), "items": 4,
                "runner": ["online": true, "tools": ["claude"], "history_offered": offered],
            ]
        }
        nonisolated(unsafe) var log: [String] = []
        nonisolated(unsafe) var policySent: [String: Any] = [:]
        t.routes["GET \(base)/sources"] = { _ in [row(false, offered: false)] }
        t.routes["GET /api/v1/runners"] = { _ in
            [["id": "d_1", "name": "vps-1", "policy": ["terminals": true, "agents": true, "agent_capacity": 2]]]
        }
        t.routes["PUT /api/v1/runners/d_1/policy"] = { b in
            log.append("policy")
            policySent = (try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            return ["policy": policySent, "restarting": true]
        }
        t.routes["PUT \(base)/sources/runner-d_1"] = { _ in
            log.append("source")
            return row(true, offered: true)
        }
        let svc = CoreBrainService(transport: t)
        let list = try await svc.runners()
        #expect(
            list.first?.name == "vps-1" && list.first?.tools.map(\.name) == ["Claude Code"] && list.first?.items == 4)
        let on = try await svc.setRunnerHistory("d_1", enabled: true)
        #expect(log == ["policy", "source"] && policySent["share_history"] as? Bool == true)
        #expect(policySent["agent_capacity"] as? Int == 2 && on.enabled && on.restarting)
    }

    @Test func aSyncThatFindsNoSharedHistorySaysSo() {
        var r = SyncResultWire()
        r.idle = "no_connection"
        #expect(r.summary().contains("doesn't share its history"))
    }
}
