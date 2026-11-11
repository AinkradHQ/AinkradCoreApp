import Foundation
import Testing

@testable import Agents

struct SessionPageTests {
    private func request(timeout: Int? = 900, decision: Bool? = nil, decidedAt: Date? = nil) -> ApprovalRequest {
        var r = ApprovalRequest(
            id: "r1", session: "s1", tool: "Bash", input: "ls", requestedAt: Date(timeIntervalSince1970: 1000),
            timeoutSecs: timeout)
        r.decision = decision
        r.decidedAt = decidedAt
        return r
    }
    private let soon = Date(timeIntervalSince1970: 1100)

    @Test func approvalStatesMapToFourCards() {
        let at = Date(timeIntervalSince1970: 1050)
        #expect(ApprovalCardState.of(request(), now: soon, sessionOver: false) == .waiting(left: 800))
        #expect(
            ApprovalCardState.of(request(decision: true, decidedAt: at), now: soon, sessionOver: false)
                == .allowed(at: at))
        #expect(
            ApprovalCardState.of(request(decision: false, decidedAt: at), now: soon, sessionOver: false)
                == .deniedByYou(at: at))
        let late = Date(timeIntervalSince1970: 3000)
        #expect(ApprovalCardState.of(request(), now: late, sessionOver: false) == .deniedNoAnswer(minutes: 15))
        #expect(ApprovalCardState.of(request(), now: soon, sessionOver: true) == .deniedNoAnswer(minutes: 15))
    }

    @Test func resultWords() {
        #expect(ApprovalCardState.waiting(left: 5).result == nil)
        #expect(ApprovalCardState.allowed(at: nil).result == "Allowed")
        #expect(ApprovalCardState.deniedByYou(at: nil).result == "Denied by you")
        #expect(ApprovalCardState.deniedNoAnswer(minutes: 15).result == "Denied: no answer in 15 min")
        #expect(ApprovalCardState.deniedByYou(at: Date()).result?.hasPrefix("Denied by you · ") == true)
    }

    @Test func pathsAreShortened() {
        #expect(
            PathWords.short("cd /var/lib/akrw/ainkrad-agent-runs-4f2/run-1794395097917 && ls -la")
                == "cd …/run-…917 && ls -la")
        #expect(PathWords.short("cat /etc/hosts") == "cat /etc/hosts")
        #expect(PathWords.short("ls /var/lib/akrw/data") == "ls …/data")
    }

    @MainActor @Test func decidedAtComesFromTheDecisionEntry() {
        let store = TranscriptStore(sessionID: "s1")
        let t0 = Date(timeIntervalSince1970: 2000)
        let t1 = Date(timeIntervalSince1970: 2060)
        store.append([
            TranscriptEntry(
                seq: 1, at: t0, kind: .approvalRequest(id: "a", tool: "Bash", input: "ls", timeoutSecs: 900)),
            TranscriptEntry(seq: 2, at: t1, kind: .approvalDecided(id: "a", approved: false)),
            TranscriptEntry(seq: 3, at: t1, kind: .note(type: "approval_escalated", detail: "x")),
            TranscriptEntry(seq: 4, at: t1, kind: .note(type: "other", detail: "")),
        ])
        #expect(store.approvals["a"]?.decidedAt == t1)
        let shown = TranscriptView.visible(store.entries).map(\.seq)
        #expect(shown == [1, 4])
    }
}
