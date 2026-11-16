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
