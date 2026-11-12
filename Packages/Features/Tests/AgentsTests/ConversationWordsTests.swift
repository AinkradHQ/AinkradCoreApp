import CoreUI
import Foundation
import Testing

@testable import Agents

/// The conversation screen's copy and flow (ui-fixes ai-session-conversation, ai-sessions-2026-11-12 new-quick).
struct ConversationWordsTests {
    private func session(
        _ state: SessionState, outcome: SessionOutcome? = nil, reason: String? = nil, keepsOpen: Bool? = nil,
        project: String? = nil, branch: String? = nil, runner: String = "r1", updated: TimeInterval = 0
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: "s-\(updated)", runner: runner, harness: "claude", state: state, outcome: outcome,
            outcomeReason: reason, createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: updated), project: project, branch: branch, keepsOpen: keepsOpen)
    }

    @Test func eventsAreSentenceCaseWithTheRunner() {
        #expect(
            ConversationWords.event(.started(harness: "claude", resumed: false), runner: "Oracle")
                == "Started on Oracle")
        #expect(ConversationWords.event(.started(harness: nil, resumed: true), runner: "Oracle") == "Woke up on Oracle")
        #expect(ConversationWords.event(.gap(from: 3, to: 9), runner: "") == "Entries 3 to 9 were not kept")
        #expect(ConversationWords.event(.ended(kind: "succeeded", reason: nil), runner: "") == "Ended: finished")
        #expect(ConversationWords.event(.note(type: "compacted", detail: ""), runner: "") == "Compacted")
        #expect(ConversationWords.event(.user("hi"), runner: "") == nil)
    }

    @Test func turnsAreNumberedAndTimedFromTheirMessage() {
        let t = { (s: TimeInterval) in Date(timeIntervalSince1970: s) }
        let e = [
            TranscriptEntry(seq: 1, at: t(0), kind: .started(harness: "claude", resumed: false)),
            TranscriptEntry(seq: 2, at: t(100), kind: .user("a")),
            TranscriptEntry(seq: 3, at: t(141), kind: .turnEnded(costMicros: 40_000, tokens: nil)),
            TranscriptEntry(seq: 4, at: t(200), kind: .user("b")),
            TranscriptEntry(seq: 5, at: t(210), kind: .user("queued")),
            TranscriptEntry(seq: 6, at: t(325), kind: .turnEnded(costMicros: nil, tokens: nil)),
            TranscriptEntry(seq: 7, at: t(400), kind: .turnEnded(costMicros: nil, tokens: nil)),
        ]
        let turns = ConversationWords.turns(e)
        #expect(turns[3] == .init(number: 1, seconds: 41))
        #expect(turns[6] == .init(number: 2, seconds: 125))
        #expect(turns[7] == .init(number: 3, seconds: nil))
        #expect(ConversationWords.turn(turns[3], cost: 40_000) == ["Turn 1 done", "41 s", "$0.04"])
        #expect(ConversationWords.turn(turns[6], cost: nil) == ["Turn 2 done", "2 min 5 s"])
        #expect(ConversationWords.turn(nil, cost: nil) == ["Turn done"])
        #expect(ConversationWords.took(120) == "2 min")
    }

    @Test @MainActor func savedAgyFallsBackToClaude() {
        #expect(AgentPrefs.harness("agy") == "claude")
        #expect(AgentPrefs.harness(nil) == "claude")
        #expect(AgentPrefs.harness("codex") == "codex")
    }

    @Test @MainActor func startFromIsSentOnlyForAnExistingFolder() {
        #expect(NewSessionSheet.base(.folder, " dev ") == "dev")
        #expect(NewSessionSheet.base(.repo, "dev") == nil)
        #expect(NewSessionSheet.base(.fresh, "dev") == nil)
    }

    @Test func oneNoticeAtATimeMostUrgentFirst() {
        let lost = session(.lost)
        // Lost wins over a reconnect or a leftover notice: it is the only one that carries Resume.
        #expect(ConversationWords.banner(lost, runner: "Azure Dev", reconnecting: true, notice: nil)?.resume == true)
        #expect(
            ConversationWords.banner(lost, runner: "Azure Dev", reconnecting: false, notice: InlineNotice(title: "X"))?
                .title == "Session lost")
        let live = session(.waiting)
        #expect(
            ConversationWords.banner(live, runner: "", reconnecting: true, notice: InlineNotice(title: "X"))?.title
                == "Reconnecting")
        #expect(
            ConversationWords.banner(live, runner: "", reconnecting: false, notice: InlineNotice(title: "X"))?.title
                == "X")
        let b = ConversationWords.banner(lost, runner: "Azure Dev", reconnecting: false, notice: nil)
        #expect(
            b?.title == "Session lost" && b?.text == "Azure Dev dropped it. The transcript is kept."
                && b?.resume == true)
        #expect(ConversationWords.banner(session(.waiting), runner: "", reconnecting: false, notice: nil) == nil)
        #expect(
            ConversationWords.banner(session(.waiting, keepsOpen: false), runner: "", reconnecting: false, notice: nil)?
                .title == "One answer, then it ends")
    }

    @Test func placeholdersFollowTheState() {
        #expect(ConversationWords.placeholder(session(.waiting)) == "Message Claude Code")
        #expect(ConversationWords.placeholder(session(.running)) == "Type to queue a message for after this turn")
        #expect(ConversationWords.placeholder(session(.lost)) == "Send a message to bring it back")
        #expect(
            ConversationWords.placeholder(session(.ended, outcome: .succeeded))
                == "This AI session ended. Start again opens a new one with the same first message.")
    }

    @Test func recentPlacesOnePerProjectNewestFirst() {
        let all = [
            session(.ended, project: "AinkradCore", branch: "main", updated: 1),
            session(.waiting, project: "AinkradCoreApp", branch: "development", updated: 3),
            session(.waiting, project: "AinkradCore", branch: "feat/x", runner: "r2", updated: 2),
            session(.waiting, updated: 4),
        ]
        let p = ConversationWords.recentPlaces(all)
        #expect(p.map(\.project) == ["AinkradCoreApp", "AinkradCore"])
        #expect(p[1].branch == "feat/x" && p[1].runner == "r2")
        #expect(ConversationWords.recentPlaces(all, limit: 1).count == 1)
    }

    @Test func theSheetOffersTheApprovedTools() {
        #expect(NewSessionSheet.tools == ["claude", "codex", "opencode"])
    }
}
