import CoreKit
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
    /// Answers for `coreStatus`, one per read; nil throws (the Core restarting). The last one repeats.
    var statuses: [CoreUpdateStatus?] = []
    var started = 0
    var startError: (any Error)?
    func coreStatus() async throws -> CoreUpdateStatus {
        let s = statuses.count > 1 ? statuses.removeFirst() : statuses.first ?? CoreUpdateStatus()
        guard let s else { throw CoreError.offline("connection refused") }
        if s.phase == .done {
            for i in list.indices where list[i].builtIn { list[i].version = s.current }
        }
        return s
    }
    func startCore() async throws {
        if let startError { throw startError }
        started += 1
    }
    func set(statuses: [CoreUpdateStatus?]) { self.statuses = statuses }
    func set(startError: (any Error)?) { self.startError = startError }
    func finish(_ id: String) {
        if let i = list.firstIndex(where: { $0.id == id }) {
            list[i].updating = false
            list[i].behind = false
            list[i].version = "0.10.3"
        }
    }
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
        #expect(m.checkWords(lastChecked: nil).hasPrefix("Checked ") && m.target == nil)
    }

    @Test func available() async {
        let core = FakeUpdates()
        await core.set(answer: CoreUpdateCheck(at: Date(), status: .available, current: "0.10.2", latest: "0.10.3"))
        let m = UpdatesModel()
        m.source = core
        await m.load()
        await m.checkNow()
        #expect(m.check?.latest == "0.10.3" && m.target == "0.10.3")
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
                    + #""runner_latest_version":"0.10.3","status":"available"}"#))
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

    @Test func runnerStatesTellTheCoreHostTheMacAndTheOthersApart() {
        let m = UpdatesModel()
        m.macRunnerID = "mac"
        let rs = [
            UpdatableRunner(id: "a", name: "Attic", version: "0.10.1", behind: true),
            UpdatableRunner(id: "b", name: "Basement", version: "0.10.2"),
            UpdatableRunner(id: "c", name: "Cellar", version: "0.10.1", online: false, behind: true),
            UpdatableRunner(id: "host", name: "Core host", version: "0.10.1", behind: true, builtIn: true),
            UpdatableRunner(id: "mac", name: "Laptop", version: "0.10.1", behind: true),
            UpdatableRunner(id: "e", name: "Shed", version: "0.10.1", behind: true, updating: true),
            UpdatableRunner(id: "f", name: "Garage", version: "0.10.1", behind: true),
        ]
        m.debugSet(check: nil, runners: rs, queue: ["f"])
        #expect(rs.map(m.state) == [.behind, .upToDate, .offline, .withCore, .withApp, .updating, .queued])
        #expect(m.behind.map(\.id) == ["a"])
        // The Core host leads the Runners section; the Mac's own runner is not in it (it sits under This Mac app).
        #expect(m.listed.map(\.id) == ["host", "a", "b", "c", "e", "f"])
        #expect(m.macRunner?.id == "mac" && m.hostRunner?.id == "host")
    }

    @Test func aDeclinedUnlockAsksNothingAndARefusalShowsPlainWords() async {
        let core = FakeUpdates()
        await core.set(list: [UpdatableRunner(id: "a", name: "Attic", version: "0.10.1", behind: true)])
        let m = UpdatesModel()
        m.pause = { _ in }
        m.source = core
        await m.load()
        m.gate = { _, _ in throw CancellationError() }
        await m.update(runner: "a")
        #expect(await core.asked.isEmpty && m.failure == nil && m.asked.isEmpty)
        m.gate = nil
        await core.set(refuse: true)
        await m.update(runner: "a")
        // A refusal that is not the Core's own answer never shows its raw text.
        #expect(m.failure == UpdatesOutcome.generic && m.asked.isEmpty)
    }

    @Test func cancellationsAreSilentEvenWhenTheClientWrapsThem() {
        struct ClientError: Error, LocalizedError {
            var operationID = "listRunners"
            var underlyingError: any Error = CancellationError()
            var errorDescription: String? {
                "Client error - operationID: listRunners, underlying error: CancellationError()"
            }
        }
        #expect(UpdatesOutcome.of(ClientError()) == .silent)
        #expect(UpdatesOutcome.of(URLError(.cancelled)) == .silent)
        #expect(UpdatesOutcome.of(CoreError.stepUpCancelled) == .silent)
        #expect(UpdatesOutcome.of(CoreError.rateLimited(retryAfter: 248)) == .wait(248))
        #expect(UpdatesOutcome.of(URLError(.badServerResponse)) == .words(UpdatesOutcome.generic))
        #expect(
            UpdatesOutcome.of(CoreError.http(status: 409, code: "busy", message: "An update is already running."))
                == .words("An update is already running."))
    }

    @Test func aRateLimitBecomesTheCountdownAndUnlocks() async {
        let core = FakeUpdates()
        await core.set(startError: CoreError.rateLimited(retryAfter: 248))
        var clock = Date(timeIntervalSince1970: 1000)
        let m = UpdatesModel()
        m.now = { clock }
        m.pause = { _ in }
        m.source = core
        var s = CoreUpdateStatus()
        s.current = "0.10.2"
        s.available = "0.10.3"
        await core.set(statuses: [s])
        await m.load()
        #expect(m.hero == .available && m.canUpdateEverything)
        await m.updateEverything()
        #expect(m.waitLeft(at: clock) == 248 && m.failure == nil && !m.pressed && m.run == nil)
        // Pressed again during the wait: nothing is sent.
        await core.set(startError: nil)
        await m.updateEverything()
        #expect(await core.started == 0)
        clock = clock.addingTimeInterval(249)
        #expect(m.waitLeft(at: clock) == nil)
    }

    /// The whole run as Oracle showed it: snapshot, install, the connection drops while the Core restarts, health, done;
    /// then the Linux runners one at a time, never the Mac's own.
    @Test func updateEverythingFollowsTheRestartThenTheRunnersInOrder() async {
        let core = FakeUpdates()
        await core.set(list: [
            UpdatableRunner(id: "host", name: "Core host", version: "0.10.2", behind: true, builtIn: true),
            UpdatableRunner(id: "a", name: "build-box", version: "0.10.2", behind: true),
            UpdatableRunner(id: "mac", name: "Laptop", version: "0.10.1", behind: true),
            UpdatableRunner(id: "b", name: "lab-pi", version: "0.10.2", behind: true),
        ])
        func st(_ p: CoreUpdateStatus.Phase, _ current: String = "0.10.2") -> CoreUpdateStatus {
            var s = CoreUpdateStatus()
            s.current = current
            s.phase = p
            s.available = p == .done ? nil : "0.10.3"
            s.to = p == .idle ? nil : "0.10.3"
            return s
        }
        await core.set(statuses: [
            st(.idle), st(.snapshot), st(.install), nil, nil, st(.health, "0.10.3"), st(.done, "0.10.3"),
        ])
        var clock = Date(timeIntervalSince1970: 1000)
        let m = UpdatesModel()
        m.macRunnerID = "mac"
        m.now = { clock }
        var seen: [String] = []
        m.pause = { s in
            clock = clock.addingTimeInterval(s)
            if let r = m.run { seen.append("\(r.step.name)\(r.gapSince == nil ? "" : " gap")") }
            // Runners finish while the model waits on them.
            for id in ["a", "b"] where m.updatingSince[id] != nil || m.asked[id] != nil {
                await core.finish(id)
            }
        }
        var reasons: [String] = []
        m.gate = { reason, op in
            reasons.append(reason)
            try await op()
        }
        m.source = core
        await m.load()
        await m.updateEverything()
        #expect(seen.contains("Install") && seen.contains("Restart gap") && seen.contains("Health check"))
        #expect(reasons == ["Update the Core to 0.10.3.", "Update build-box.", "Update lab-pi."])
        #expect(await core.asked == ["a", "b"])
        #expect(m.finished?.version == "0.10.3" && m.hero == .done && !m.pressed && m.queue.isEmpty)
    }

    @Test func updateEverythingLocksAtTheFirstPress() async {
        let core = FakeUpdates()
        var s = CoreUpdateStatus()
        s.current = "0.10.2"
        s.available = "0.10.3"
        var done = s
        done.phase = .done
        done.current = "0.10.3"
        done.available = nil
        await core.set(statuses: [s, done])
        let m = UpdatesModel()
        m.pause = { _ in }
        m.source = core
        await m.load()
        var second: Task<Void, Never>?
        m.gate = { _, op in
            // The second press lands while Touch ID is still up.
            #expect(m.pressed)
            second = Task { await m.updateEverything() }
            await second?.value
            try await op()
        }
        await m.updateEverything()
        #expect(await core.started == 1 && !m.pressed)
    }

    @Test func theRestartGapShowsThenReconnects() {
        let m = UpdatesModel()
        var clock = Date(timeIntervalSince1970: 1000)
        m.now = { clock }
        var s = CoreUpdateStatus()
        s.current = "0.10.2"
        s.phase = .install
        s.to = "0.10.3"
        m.receive(s)
        #expect(m.run?.step == .install && m.hero == .updating)
        clock = clock.addingTimeInterval(3)
        m.debugDrop()
        #expect(m.run?.step == .restart && m.run?.gapSeconds(at: clock.addingTimeInterval(2)) == 3)
        #expect(m.run?.took[.install] == 3)
        clock = clock.addingTimeInterval(4)
        s.phase = .health
        m.receive(s)
        #expect(m.run?.gapSince == nil && m.run?.backAt == clock && m.run?.step == .health)
        #expect(m.run?.took[.restart] == 4)
        s.phase = .rolledBack
        s.error = "health_failed"
        m.receive(s)
        #expect(m.run == nil && m.hero == .wentBack)
    }

    @Test func installingAndRolledBackSteps() {
        var s = CoreUpdateStatus()
        s.phase = .install
        #expect(s.running && s.steps == [.done, .now, .wait])
        #expect(CoreUpdateStatus.decode(json(#"{"state":"restarting"}"#))?.phase == .restart)
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
