import CoreKit
import CoreUI
import Foundation
import Shell
import Testing

@testable import Agents

@MainActor
final class FakeHost: AgentsHost {
    var notice: InlineNotice?
    private(set) var asked: [(String, Bool)] = []
    func elevate(reason: String, force: Bool) async -> InlineNotice? {
        asked.append((reason, force))
        return notice
    }
}

@MainActor
final class FakeNotifier: ApprovalNotifier {
    var permission: NotificationPermission = .allowed
    var onOpen: (@MainActor (String) -> Void)?
    private(set) var posted: [String] = []
    private(set) var requested = 0
    func refresh() async {}
    func request() async -> NotificationPermission {
        requested += 1
        permission = .allowed
        return .allowed
    }
    func post(id: String, title: String, body: String, session: String) { posted.append(id) }
    func clear(id: String) {}
}

@MainActor
struct ModelTests {
    private func make(_ api: FakeAgentsAPI = FakeAgentsAPI.prototypeWorld(), host: FakeHost? = FakeHost()) async -> (
        AgentsModel, FakeAgentsAPI, FakeHost?, FakeNotifier
    ) {
        let notifier = FakeNotifier()
        let defaults = UserDefaults(suiteName: "agents-tests-\(UUID())")!
        let m = AgentsModel(shell: ShellModel(), notifier: notifier, defaults: defaults, host: host)
        m.attach(api)
        await m.reloadAll()
        return (m, api, host, notifier)
    }

    @Test func startupFindsTheThreeWaitingApprovalsAndPutsThemInTheBell() async {
        let (m, _, _, n) = await make()
        #expect(m.sessions.items.count == 11)
        #expect(m.pending.count == 3)
        #expect(m.shell.bell.items.filter { $0.kind == .approval }.count == 3)
        #expect(m.count(.needsYou) == 3 && m.count(.active) == 5 && m.count(.ended) == 6)
        #expect(n.posted.isEmpty)  // what was waiting when the app opened is in the bell, not a banner
        #expect(m.shown().prefix(3).allSatisfy { m.waiting($0.id) })
    }

    @Test func approveAsksForTouchIDThenDecides() async throws {
        let (m, api, host, _) = await make()
        let r = try #require(m.pending.first)
        await m.decide(r, approved: true)
        #expect(host?.asked.count == 1 && host?.asked.first?.1 == false)
        #expect(api.calls.contains("decide:true"))
        #expect(m.transcripts[r.session]?.approvals[r.id]?.decision == true)
        #expect(m.pending.count == 2 && m.shell.bell.items.count == 2)
    }

    @Test func touchIDDeclinedLeavesTheApprovalPendingWithAnInlineNotice() async throws {
        let host = FakeHost()
        host.notice = InlineNotice(title: "Cancelled, nothing was done.")
        let (m, api, _, _) = await make(host: host)
        let r = try #require(m.pending.first)
        await m.decide(r, approved: true)
        #expect(!api.calls.contains { $0.hasPrefix("decide") })
        #expect(m.pending.count == 3)
        #expect(m.approvalNotices[r.id]?.title == "Cancelled, nothing was done.")
    }

    @Test func theCoreSayingStepUpRequiredElevatesAndRetriesOnce() async throws {
        let (m, api, host, _) = await make()
        api.failNext = CoreError.stepUpRequired
        let r = try #require(m.pending.first)
        await m.decide(r, approved: false)
        #expect(host?.asked.map(\.1) == [false, true])
        #expect(
            api.calls.filter { $0.hasPrefix("decide") }.count == 2
                || m.transcripts[r.session]?.approvals[r.id]?.decision == false)
    }

    @Test func aRefusedDecisionTakesTheChoiceBackAndSaysWhy() async throws {
        let (m, api, _, _) = await make()
        api.failNext = CoreError.http(status: 502, code: "runner_failed", message: "no such request waits")
        let r = try #require(m.pending.first)
        await m.decide(r, approved: true)
        #expect(m.pending.count == 3)
        #expect(m.approvalNotices[r.id]?.detail.contains("no such request") == true)
    }

    @Test func aNewApprovalOnTheFeedReachesTheBellAndMacOS() async {
        let (m, api, _, n) = await make()
        api.append(
            "as_01JC4X7Q3MZ8N5V2K9R004",
            [.approvalRequest(id: "req_new", tool: "Bash", input: "rm -rf node_modules", timeoutSecs: 300)])
        api.update("as_01JC4X7Q3MZ8N5V2K9R004") { $0.state = .running }
        await m.handle(
            .event(
                AgentEvent(
                    kind: "agent.approval_requested", session: "as_01JC4X7Q3MZ8N5V2K9R004", request: "req_new",
                    tool: "Bash")))
        #expect(m.pending.count == 4)
        #expect(m.shell.bell.items.contains { $0.id == "agents.ap.as_01JC4X7Q3MZ8N5V2K9R004.req_new" })
        #expect(n.posted == ["agents.ap.as_01JC4X7Q3MZ8N5V2K9R004.req_new"])
        m.notifyApprovals = false
        api.append(
            "as_01JC4X7Q3MZ8N5V2K9R004", [.approvalRequest(id: "req_2", tool: "Bash", input: "ls", timeoutSecs: 300)])
        await m.handle(
            .event(AgentEvent(kind: "agent.approval_requested", session: "as_01JC4X7Q3MZ8N5V2K9R004", request: "req_2"))
        )
        #expect(n.posted.count == 1 && m.pending.count == 5)
    }

    @Test func aGapRefetchesTheListAndTheTranscripts() async {
        let (m, api, _, _) = await make()
        api.add(
            AgentSessionInfo(
                id: "as_late", runner: "d_mac", harness: "codex", state: .running, createdAt: Date(), updatedAt: Date(),
                index: 99))
        await m.handle(.gap)
        #expect(m.sessions.session("as_late") != nil)
    }

    @Test func transcriptEventsAppendToAnOpenTranscriptOnly() async {
        let (m, api, _, _) = await make()
        let id = "as_01JC4X7Q3MZ8N5V2K9R001"
        let before = m.transcripts[id]?.lastSeq ?? 0
        api.append(id, [.assistant("more")])
        await m.handle(.event(AgentEvent(kind: "agent.transcript", session: id, from: before + 1, to: before + 1)))
        #expect(m.transcripts[id]?.lastSeq == before + 1)
        let ended = "as_01JC4X7Q3MZ8N5V2K9R006"
        let calls = api.calls.filter { $0 == "transcript" }.count
        await m.handle(.event(AgentEvent(kind: "agent.transcript", session: ended)))
        #expect(api.calls.filter { $0 == "transcript" }.count == calls)  // nobody is reading it
    }

    @Test func anUnknownEventKindIsSkipped() async {
        let (m, _, _, _) = await make()
        await m.handle(.event(AgentEvent(kind: "agent.from_the_future", session: "as_x")))
        #expect(m.sessions.items.count == 11)
    }

    @Test func theComposerSendsOnlyWhileRunning() async throws {
        let (m, api, host, _) = await make()
        let running = "as_01JC4X7Q3MZ8N5V2K9R001"
        let ended = "as_01JC4X7Q3MZ8N5V2K9R006"
        m.drafts[running] = "hello"
        m.drafts[ended] = "hello"
        #expect(m.canSend(running) && !m.canSend(ended))
        await m.send(running)
        #expect(api.calls.contains("send") && host?.asked.count == 1 && m.drafts[running] == "")
        m.drafts[running] = String(repeating: "x", count: 16 * 1024 + 1)
        #expect(!m.canSend(running))
    }

    @Test func cancelAsksFirstAndRunsOnConfirm() async throws {
        let (m, api, _, _) = await make()
        let id = "as_01JC4X7Q3MZ8N5V2K9R001"
        m.confirmCancel(id)
        let sheet = try #require(m.shell.sheet)
        #expect(sheet.actions.map(\.label) == ["Keep running", "Cancel session"])
        sheet.actions[1].run()
        try await Task.sleep(for: .milliseconds(200))
        #expect(api.calls.contains("cancel") && m.sessions.session(id)?.over == true)
    }

    @Test func resumeAndWakeGoThroughTouchID() async throws {
        let (m, api, host, _) = await make()
        m.resume("as_01JC4X7Q3MZ8N5V2K9R011")
        m.wake("as_01JC4X7Q3MZ8N5V2K9R006")
        try await Task.sleep(for: .milliseconds(200))
        #expect(api.calls.contains("resume") && api.calls.contains("wake") && host?.asked.count == 2)
    }

    @Test func aRefusedNewSessionComesBackAsWords() async {
        let (m, api, _, _) = await make()
        api.failNext = CoreError.http(status: 409, code: "runner_offline", message: "mac-studio is not connected")
        let n = await m.create(NewAgentSession(runner: "d_mac", harness: "claude", prompt: "go"))
        #expect(n?.title == "That runner is offline" && n?.detail == "mac-studio is not connected")
        let ok = await m.create(NewAgentSession(runner: "d_mac", harness: "claude", prompt: "go"))
        #expect(ok == nil && m.shell.panes.contains { $0.id.hasPrefix("agents.s-as_new") })
    }

    @Test func theNotificationQuestionIsAskedOnceInTheAppsWordsFirst() async {
        let api = FakeAgentsAPI.prototypeWorld()
        let notifier = FakeNotifier()
        notifier.permission = .notAsked
        let m = AgentsModel(
            shell: ShellModel(), notifier: notifier, defaults: UserDefaults(suiteName: "agents-tests-\(UUID())")!)
        m.attach(api)
        await m.refreshPermission()
        #expect(m.shouldAskAboutNotifications && notifier.requested == 0)
        await m.turnOnNotifications()
        #expect(notifier.requested == 1 && !m.shouldAskAboutNotifications && m.notifierPermission == .allowed)
        m.declineNotificationsForNow()
        #expect(!m.shouldAskAboutNotifications)
    }

    @Test func launcherAndPaneHeadsFollowTheSessions() async {
        let (m, _, _, _) = await make()
        #expect(m.shell.launcher.entry("agents.list") != nil && m.shell.launcher.entry("agents.new")?.isAction == true)
        #expect(m.shell.launcher.entries.filter { $0.id.hasPrefix("agents.s-") }.count == 11)
        m.openSession("as_01JC4X7Q3MZ8N5V2K9R001")
        #expect(m.shell.panes.first?.chip?.label == "Waiting on you")
    }

    @Test func detachClearsTheBell() async {
        let (m, _, _, _) = await make()
        m.detach()
        #expect(m.shell.bell.items.isEmpty)
    }
}
