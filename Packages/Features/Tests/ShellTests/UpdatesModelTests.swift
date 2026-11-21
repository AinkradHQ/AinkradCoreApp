import Foundation
import Testing

@testable import Shell

private struct Refused: LocalizedError { var errorDescription: String? { "The runner is offline." } }

private actor FakeUpdates: UpdatesSource {
    var minor = true
    var answer = CoreUpdateCheck(at: Date(timeIntervalSince1970: 100), status: .upToDate, current: "0.10.2")
    var list: [UpdatableRunner] = []
    var asked: [String] = []
    var refuse = false
    func supported() async -> Bool { minor }
    func check() async throws -> CoreUpdateCheck { answer }
    func runners() async throws -> [UpdatableRunner] { list }
    func updateRunner(_ id: String) async throws {
        if refuse { throw Refused() }
        asked.append(id)
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].updating = true }
    }
    func set(answer: CoreUpdateCheck) { self.answer = answer }
    func set(list: [UpdatableRunner]) { self.list = list }
    func set(minor: Bool) { self.minor = minor }
    func set(refuse: Bool) { self.refuse = refuse }
}

private func json(_ s: String) -> Data { Data(s.utf8) }

@MainActor
struct UpdatesModelTests {
    @Test func upToDate() async {
        let m = UpdatesModel()
        m.source = FakeUpdates()
        await m.load()
        await m.checkNow()
        #expect(m.check?.status == .upToDate)
        #expect(m.checkWords(lastChecked: nil) == "Up to date. Checked just now.")
    }

    @Test func available() async {
        let core = FakeUpdates()
        await core.set(answer: CoreUpdateCheck(at: Date(), status: .available, current: "0.10.2", latest: "0.10.3"))
        let m = UpdatesModel()
        m.source = core
        await m.load()
        await m.checkNow()
        #expect(m.check?.latest == "0.10.3" && m.checkWords(lastChecked: nil) == "Core 0.10.3 is ready.")
    }

    @Test func feedUnavailableSaysTheCoresReason() async {
        let core = FakeUpdates()
        await core.set(
            answer: CoreUpdateCheck(at: Date(), status: .feedUnavailable, reason: "The release server did not answer."))
        let m = UpdatesModel()
        m.source = core
        await m.load()
        await m.checkNow()
        #expect(m.checkWords(lastChecked: nil) == "Checked. The release server did not answer.")
    }

    @Test func anOlderCoresAnswerKeepsTodaysHonestWords() {
        // Core 0.10.2's stub: no reason, no runner version.
        let c = CoreUpdateCheck.decode(
            json(#"{"checked_at":"2026-11-21T10:00:00.123Z","current_version":"0.10.2","status":"feed_unavailable"}"#))
        #expect(c?.status == .feedUnavailable && c?.reason == nil && c?.latestRunner == nil)
        let at = ISO8601DateFormatter().date(from: "2026-11-21T10:00:00Z")!.addingTimeInterval(0.123)
        #expect(abs((c?.at ?? .distantPast).timeIntervalSince(at)) < 0.01)
        let m = UpdatesModel()
        m.debugSet(check: c, runners: [])
        #expect(m.checkWords(lastChecked: nil) == "Checked. No release feed is set up on this Core yet.")
    }

    @Test func aNewerCoresFieldsAreRead() {
        let c = CoreUpdateCheck.decode(
            json(
                #"{"checked_at":"2026-11-21T10:00:00Z","current_version":"0.10.2","latest_version":"0.10.3","#
                    + #""latest_runner_version":"0.10.3","status":"available"}"#))
        #expect(c?.status == .available && c?.latest == "0.10.3" && c?.latestRunner == "0.10.3")
        // A status this app does not know reads as no feed.
        #expect(CoreUpdateCheck.decode(json(#"{"status":"later"}"#))?.status == .feedUnavailable)
        #expect(CoreUpdateCheck.decode(json("{}")) == nil)
    }

    @Test func aCoreWithoutTheRoutesChecksNothing() async {
        let core = FakeUpdates()
        await core.set(minor: false)
        let m = UpdatesModel()
        m.source = core
        await m.load()
        await m.checkNow()
        #expect(m.check == nil && m.checkWords(lastChecked: nil) == "This Core is too old to check for updates.")
    }

    @Test func runnerStates() {
        let m = UpdatesModel()
        let rs = [
            UpdatableRunner(id: "a", name: "Attic", version: "0.10.1", behind: true),
            UpdatableRunner(id: "b", name: "Basement", version: "0.10.2"),
            UpdatableRunner(id: "c", name: "Cellar", version: "0.10.1", online: false, behind: true),
            UpdatableRunner(id: "d", name: "This Mac", version: "0.10.1", behind: true, builtIn: true),
            UpdatableRunner(id: "e", name: "Shed", version: "0.10.1", behind: true, updating: true),
            UpdatableRunner(id: "f", name: "Garage", version: "0.10.1", behind: true),
        ]
        m.debugSet(check: nil, runners: rs, asked: ["f"])
        #expect(rs.map(m.state) == [.behind, .upToDate, .offline, .withApp, .updating, .starting])
        #expect(m.behind.map(\.id) == ["a"])
    }

    @Test func updateAllAsksOnceBehindTheGateAndShowsThemUpdating() async {
        let core = FakeUpdates()
        await core.set(list: [
            UpdatableRunner(id: "a", name: "Attic", version: "0.10.1", behind: true),
            UpdatableRunner(id: "b", name: "Basement", version: "0.10.1", behind: true),
        ])
        let m = UpdatesModel()
        m.source = core
        var reasons: [String] = []
        m.gate = { reason, op in
            reasons.append(reason)
            try await op()
        }
        await m.load()
        await m.updateAllBehind()
        #expect(reasons == ["Update 2 runners."])
        #expect(await core.asked == ["a", "b"])
        #expect(m.runners.allSatisfy { m.state($0) == .updating })
    }

    @Test func aDeclinedUnlockAsksNothingAndARefusalShowsItsWords() async {
        let core = FakeUpdates()
        await core.set(list: [UpdatableRunner(id: "a", name: "Attic", version: "0.10.1", behind: true)])
        let m = UpdatesModel()
        m.source = core
        await m.load()
        m.gate = { _, _ in throw CancellationError() }
        await m.update(runner: "a")
        #expect(await core.asked.isEmpty && m.failure == nil)
        m.gate = nil
        await core.set(refuse: true)
        await m.update(runner: "a")
        #expect(m.failure == "The runner is offline." && m.asked.isEmpty)
    }

    @Test func installingAndRolledBackSteps() {
        var s = CoreUpdateStatus()
        s.phase = .install
        #expect(s.running && s.steps == [.done, .now, .wait])
        s.phase = .rolledBack
        s.error = "health_failed"
        #expect(!s.running && s.visible && s.steps == [.done, .done, .fail])
        #expect(s.errorWords == "Core did not answer in time.")
    }

    @Test func droppingTheSourceClearsEverything() async {
        let m = UpdatesModel()
        m.debugSet(
            check: CoreUpdateCheck(at: Date(), status: .upToDate), runners: [.init(id: "a", name: "A", version: nil)])
        m.source = nil
        #expect(!m.supported && m.check == nil && m.runners.isEmpty)
    }
}
