import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    private(set) var reasons: [String] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw AdminDeclined() }
        return try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

@MainActor
struct BrainModelTests {
    func make(_ s: SampleBrainService.Scenario = .init()) async -> (BrainModel, FakeHost) {
        let host = FakeHost()
        let model = BrainModel(host: host)
        model.use(SampleBrainService(s))
        await model.reload()
        return (model, host)
    }

    @Test func theRoomActionsWaitForAService() {
        let host = FakeHost()
        let model = BrainModel(host: host)
        model.install()
        let ids = { host.shell.launcher.entries.map(\.id).filter { $0.hasPrefix("brain") } }
        #expect(Set(ids()) == ["brain", "brain-how"])
        model.use(SampleBrainService())
        #expect(Set(ids()) == ["brain", "brain-how", "brain-open-room", "brain-new-room", "brain-new-room-advanced"])
        model.detach()
        #expect(Set(ids()) == ["brain", "brain-how"])
    }

    @Test func noServiceMeansUnavailable() {
        let model = BrainModel(host: FakeHost())
        #expect(model.load == .unavailable)
        #expect(model.rooms.isEmpty && model.bellTexts.isEmpty)
        #expect(BrainWords.unavailableTitle == "Brain is coming")
    }

    @Test func switchingRoomsClearsTheOldRoomsViewFirst() async {
        let (m, _) = await make()
        await m.inspect("acme-shop")
        #expect(m.inspected?.room.id == "acme-shop")
        m.view("initech")
        #expect(m.inspected == nil && m.inspectingID == nil)
        #expect(m.viewingID == "initech")
    }

    @Test func inspectingAnotherRoomNeverKeepsTheFirst() async {
        let (m, _) = await make()
        await m.inspect("ainkrad")
        let task = Task { await m.inspect("initech") }
        await Task.yield()
        #expect(m.inspected == nil)  // cleared before the new answer arrives
        await task.value
        #expect(m.inspected?.room.id == "initech")
    }

    @Test func sealedRoomHasNoNumbersAndNoView() async {
        let (m, _) = await make()
        let r = m.room("umbrella")
        #expect(r?.counts == nil && r?.lock == .sealed)
        await m.inspect("umbrella")
        #expect(m.inspected == nil)
        m.view("umbrella")
        #expect(m.viewingLock?.sentence == "This room is sealed. Open it to see its memories.")
    }

    @Test func sealingTheViewedRoomClearsItAndSeals() async {
        let (m, _) = await make()
        await m.inspect("ainkrad")
        await m.seal("ainkrad")
        #expect(m.inspected == nil)
        #expect(m.room("ainkrad")?.mounted == false)
        #expect(m.room("ainkrad")?.counts == nil)
    }

    @Test func openingAsksForTouchIDAndCancelledLeavesItSealed() async {
        let (m, host) = await make()
        host.declines = true
        #expect(await m.open("umbrella") == false)
        #expect(m.room("umbrella")?.mounted == false)
        host.declines = false
        #expect(await m.open("umbrella"))
        #expect(m.room("umbrella")?.mounted == true)
        #expect(host.reasons.count == 2)
    }

    @Test func countsNeverIncludeUnmountedRooms() async {
        let (m, _) = await make()
        #expect(m.recordsPerRoom.contains { $0.room.id == "umbrella" } == false)
        #expect(m.recordsPerRoom.count == m.mountedRooms.count)
        #expect(m.visibleNeeds.allSatisfy { n in n.room.map { m.room($0)?.mounted == true } ?? true })
        await m.seal("globex")
        // its needs vanish with it: a count is data too
        #expect(m.visibleNeeds.contains { $0.room == "globex" } == false)
        #expect(m.recordsPerRoom.contains { $0.room.id == "globex" } == false)
    }

    @Test func pausedIsOneSentenceAndClearingNeedsTouchID() async {
        let (m, host) = await make(.init(paused: true))
        #expect(m.health == .paused)
        #expect(m.pausedNames == ["Globex", "Northwind"])
        #expect(
            BrainWords.pausedLine(names: m.pausedNames)
                == "Search is stopped for Globex and Northwind. Other rooms keep working, each one alone.")
        host.declines = true
        #expect(await m.clearPaused() == false)
        #expect(m.health == .paused)
        host.declines = false
        #expect(await m.clearPaused())
        #expect(m.health == .needsYou)
    }

    @Test func notificationTextCarriesNamesAndCountsOnly() async {
        let (m, _) = await make()
        #expect(m.bellTexts.contains("3 memories wait in Ainkrad"))
        #expect(m.bellTexts.contains("1 conflict to settle in Acme Shop"))
        #expect(m.bellTexts.contains("4 captures have no room yet"))
        #expect(BrainWords.push(kind: .waiting, n: 3) == "3 memories wait in a room")
        // nothing in any line comes from a record: sample titles all start with "Sample:"
        #expect(m.bellTexts.allSatisfy { !$0.contains("Sample") && !$0.contains("secret") })
        let bell = m.host.shell.bell
        #expect(bell.items.count == m.visibleNeeds.count)
        await m.seal("ainkrad")
        #expect(m.host.shell.bell.items.contains { $0.title.contains("Ainkrad") } == false)
    }

    @Test func quickRoomRunsAtOnceWithDefaults() async {
        let (m, host) = await make()
        await m.quickRoom()
        let made = m.room("new-room")
        #expect(made?.mode == .synced && made?.provider == .local)
        #expect(host.reasons.isEmpty)
        #expect(m.quickName == "New room 2")
        #expect(await m.createRoom(NewRoomDraft(name: "Synced one", kind: .client)))
        #expect(host.reasons.isEmpty, "every room is synced: nothing wider to confirm")
    }

    @Test func failureIsWordedAndRetryable() async {
        let (m, _) = await make(.init(error: true))
        #expect(m.load == .failed("Core did not answer. Nothing was changed."))
    }

    @Test func healthComesFromTheServiceNotTheUI() async {
        let (m, _) = await make(.init(healthy: true))
        #expect(m.health == .healthy && m.needsTotal == 0)
        #expect(m.chip.label == "Healthy")
        let (n, _) = await make()
        #expect(n.chip.label == "Needs you, \(n.needsTotal)")
    }
}

@MainActor
struct PlainWordsTests {
    @Test func theBreakdownNamesEveryTypeBiggestFirst() {
        let shares = [
            TypeShare("rule", 410), TypeShare("fact", 820), TypeShare("summary", 1), TypeShare("identity", 2),
        ]
        #expect(BrainWords.breakdown(shares) == "820 facts, 410 rules, 2 identities, 1 summary")
        #expect(BrainWords.mostly(shares) == "67% facts")
        #expect(BrainWords.mostly([]) == "")
    }

    @Test func aNumberNeverLeavesItsUnit() {
        #expect(
            BrainWords.glue("Local search 212 ms, target 300 ms") == "Local search 212\u{00A0}ms, target 300\u{00A0}ms")
        #expect(BrainWords.keyRenews("19 h") == "Key renews in 19\u{00A0}h")
        #expect(BrainWords.glue("Three rooms") == "Three rooms")
    }

    @Test func healthTilesGetPlainNamesAndKeepTheTermInHelp() {
        let t = BrainWords.tile("restore", "Restore drill")
        #expect(t.name == "Backup test" && t.help.contains("Restore drill"))
        #expect(BrainWords.tile("isolation", "Isolation").help.contains("Isolation"))
        #expect(BrainWords.tile("unknown", "Whatever").name == "Whatever")
    }

    @Test func anActivityRowIsAWholeSentence() async {
        let host = FakeHost()
        let m = BrainModel(host: host)
        m.use(SampleBrainService(.init(), pace: .zero))
        await m.reload()
        await m.activity.load()
        let e = m.activity.events[0]
        let s = BrainWords.sentence(e, room: m.room(e.room)?.name)
        #expect(s.contains(e.actor) && s.hasSuffix(".") && !s.contains(e.actionCode))
    }

    @Test func overviewIsGlobalAndNeverCountsASealedRoom() async {
        let host = FakeHost()
        let m = BrainModel(host: host)
        m.use(SampleBrainService(.init(), pace: .zero))
        await m.reload()
        #expect(m.recordsPerRoom.allSatisfy { $0.room.mounted })
        #expect(m.visibleNeeds.allSatisfy { n in n.room.map { m.room($0)?.mounted ?? false } ?? true })
    }
}

@MainActor
struct SampleImportTests {
    @Test func theSampleImportReachesReviewAndCommitsWithoutReadingThisMac() async throws {
        var s = SampleBrainService.Scenario()
        s.imports = true
        let routes = try #require(SampleBrainService(s).importRoutes)
        #expect(SampleBrainService().importRoutes == nil)
        let m = ImportModel(
            host: FakeHost(), routes: routes, sources: SampleImportSource.all, poll: .milliseconds(1), pause: { _ in })
        await m.scan()
        #expect(m.chosen.map(\.id) == ["claude_code", "codex", "opencode", "antigravity"])
        m.start()
        for _ in 0..<500 where m.step != .review { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(m.step == .review && m.review.visible.last?.isUnsorted == true)
        await m.review.accept("ainkrad")
        await m.commit()
        #expect(m.step == .done && m.result?.rooms.map(\.room) == ["ainkrad"])
    }

    @Test func sampleRulesNameRoomsAndLatestIsNewestFirst() async throws {
        let svc = SampleBrainService()
        #expect(try await svc.rules().contains { $0.room == "ainkrad" })
        let days = try await svc.latest(room: "ainkrad").map(\.startedAt)
        #expect(!days.isEmpty && days == days.sorted(by: >))
    }
}
