import Foundation
import Testing

@testable import Agents
@testable import Shell

/// Messages typed during a turn wait in the queue and go out together when the turn ends (Ahmed, 2026-11-16).
@MainActor
struct QueueTests {
    private let running = "as_01JC4X7Q3MZ8N5V2K9R001"

    private func make() async -> (AgentsModel, FakeAgentsAPI) {
        let api = FakeAgentsAPI.prototypeWorld()
        let defaults = UserDefaults(suiteName: "queue-tests-\(UUID())")!
        let m = AgentsModel(shell: ShellModel(), notifier: FakeNotifier(), defaults: defaults, host: FakeHost())
        m.attach(api)
        await m.firstLoad?.value
        await m.reloadAll()
        return (m, api)
    }

    @Test func typingDuringATurnQueuesAndSendsNothing() async {
        let (m, api) = await make()
        let sends = api.calls.filter { $0 == "send" }.count
        m.drafts[running] = "also add a test"
        m.enqueue(running)
        #expect(m.queued[running]?.map(\.text) == ["also add a test"])
        #expect(m.drafts[running] == "")
        #expect(api.calls.filter { $0 == "send" }.count == sends)
    }

    @Test func attachedFilesQueueWithTheirMessageAndComeBackToEdit() async {
        let (m, _) = await make()
        let f = URL(fileURLWithPath: "/tmp/shot.png")
        m.attachments[running] = [f]
        m.enqueue(running)  // files alone are a message
        #expect(m.queued[running]?.first?.files == [f] && m.queued[running]?.first?.text == "")
        #expect(m.attachments[running] == nil)
        m.editAllQueued(running)
        #expect(m.attachments[running] == [f] && m.queued[running]?.isEmpty == true)
    }

    @Test func editTakesItBackToTheFieldBeforeWhatWasTyped() async {
        let (m, _) = await make()
        m.drafts[running] = "first"
        m.enqueue(running)
        m.drafts[running] = "second"
        let id = try! #require(m.queued[running]?.first?.id)
        m.editQueued(running, id)
        #expect(m.queued[running]?.isEmpty == true)
        #expect(m.drafts[running] == "first\n\nsecond")
    }

    @Test func upOnAnEmptyFieldTakesEveryQueuedMessageBackToEdit() async {
        let (m, _) = await make()
        for t in ["one", "two"] {
            m.drafts[running] = t
            m.enqueue(running)
        }
        m.editAllQueued(running)
        #expect(m.queued[running]?.isEmpty == true)
        #expect(m.drafts[running] == "one\n\ntwo")
    }

    @Test func queuedMessagesGoOutTogetherWhenTheTurnEnds() async {
        let (m, api) = await make()
        m.drafts[running] = "one"
        m.enqueue(running)
        m.drafts[running] = "two"
        m.enqueue(running)
        #expect(AgentsModel.joined(m.queued[running] ?? []) == "one\n\ntwo")
        // A queue also waits while an approval is open: answer this session's first.
        _ = m.transcript(running)
        _ = await until { m.transcripts[running]?.load == .ready }
        for r in m.pending where r.session == running { await m.decide(r, approved: false) }
        api.update(running) { $0.state = .waiting }
        await m.reloadAll()
        let s = try! #require(m.sessions.session(running))
        #expect(s.live && s.idle, "state \(s.state)")
        #expect(m.canReply(s))
        #expect(!m.waiting(running))
        #expect(!m.sending.contains(running))
        m.syncDerived()
        #expect(await until { api.calls.contains("send") && m.queued[running]?.isEmpty == true })
    }
}

/// The side panel's Files touched counts every edit the conversation shows (review 2026-11-16).
@MainActor
struct FilesTouchedTests {
    @Test func plainEditStepsCountWithTheirLineCounts() {
        #expect(AgentsModel.lineCounts("+40 -6") == (40, 6))
        #expect(AgentsModel.lineCounts("+2 −1 lines") == (2, 1))
        #expect(AgentsModel.lineCounts("done") == (0, 0))
        #expect(AgentsModel.isEdit("MultiEdit") && !AgentsModel.isEdit("Read"))
    }
}

/// Permission and Plan modes (Ahmed, 2026-11-16): shown from the session, cycled with ⇧⇥ as in Claude Code, switched
/// through the Core.
@MainActor
struct SessionModeTests {
    private func info(policy: String?, plan: Bool = false, harness: String = "claude") -> AgentSessionInfo {
        AgentSessionInfo(
            id: "s", runner: "r", harness: harness, state: .running, createdAt: .now, updatedAt: .now, policy: policy,
            plan: plan)
    }

    @Test func theModeComesFromTheSession() {
        #expect(SessionMode.of(info(policy: nil)) == nil, "an older Core does not say: no chip")
        #expect(SessionMode.of(info(policy: "ask")) == .ask)
        #expect(SessionMode.of(info(policy: "accept_edits")) == .acceptEdits)
        #expect(SessionMode.of(info(policy: "ask", plan: true)) == .plan)
    }

    @Test func shiftTabCyclesAsClaudeCodeDoes() {
        #expect(SessionMode.ask.next(harness: "claude") == .acceptEdits)
        #expect(SessionMode.acceptEdits.next(harness: "claude") == .plan)
        #expect(SessionMode.plan.next(harness: "claude") == .ask)
        #expect(SessionMode.acceptEdits.next(harness: "codex") == .ask, "no Plan where the tool has none")
        #expect(SessionMode.sandboxed.next(harness: "claude") == nil, "sandboxed is chosen at start")
    }

    @Test func switchingGoesThroughTheCore() async {
        let api = FakeAgentsAPI.prototypeWorld()
        let m = AgentsModel(
            shell: ShellModel(), notifier: FakeNotifier(), defaults: UserDefaults(suiteName: "mode-\(UUID())")!,
            host: FakeHost())
        m.attach(api)
        await m.firstLoad?.value
        await m.reloadAll()
        let id = "as_01JC4X7Q3MZ8N5V2K9R002"
        await m.setMode(id, to: .plan)
        #expect(api.calls.contains("setMode"))
        #expect(m.sessions.session(id).map { SessionMode.of($0) } == .plan)
    }
}
