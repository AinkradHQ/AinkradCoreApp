import CoreKit
import CoreUI
import Foundation
import Testing

@testable import Agents

private func entry(_ seq: Int64, _ kind: EntryKind, at: Date = Date()) -> TranscriptEntry {
    TranscriptEntry(seq: seq, at: at, kind: kind)
}

struct EntryParserTests {
    @Test func knownTypesBecomeWords() {
        #expect(EntryParser.kind(["type": "assistant_text", "text": "hi"]) == .assistant("hi"))
        #expect(EntryParser.kind(["type": "message", "text": "go"]) == .user("go"))
        #expect(
            EntryParser.kind(["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "cargo test"]])
                == .toolUse(id: "t1", name: "Bash", summary: "cargo test"))
        #expect(
            EntryParser.kind([
                "type": "tool_result", "id": "t1", "name": "Bash", "status": "error", "exit_code": 1, "output": "x",
                "duration_ms": 1200,
            ])
                == .toolResult(id: "t1", name: "Bash", ok: false, exitCode: 1, output: "x", durationMs: 1200))
        #expect(
            EntryParser.kind([
                "type": "approval_request", "id": "r1", "tool": "Bash", "input": ["command": "git push"],
                "timeout_secs": 300,
            ])
                == .approvalRequest(id: "r1", tool: "Bash", input: "git push", timeoutSecs: 300))
        #expect(
            EntryParser.kind(["type": "approval_decided", "id": "r1", "approved": true])
                == .approvalDecided(id: "r1", approved: true))
        #expect(
            EntryParser.kind(["type": "ended", "outcome": ["kind": "token_cap"]])
                == .ended(kind: "token_cap", reason: nil))
    }

    @Test func bookkeepingIsHiddenAndUnknownKeepsItsWord() {
        for t in ["session_started", "usage", "turn_ended", "approval_requested"] {
            #expect(EntryParser.kind(["type": t]) == .hidden)
        }
        #expect(
            EntryParser.kind(["type": "brand_new_thing", "reason": "why"])
                == .note(type: "brand_new_thing", detail: "why"))
        #expect(EntryParser.kind([:]) == .note(type: "unknown", detail: ""))
    }

    @Test func aToolInputWithoutACommandIsItsJSONCut() {
        let long = String(repeating: "a", count: 900)
        #expect(EntryParser.summary(["blob": long]).count <= 401)
        #expect(EntryParser.summary(["file_path": "/a/b.rs", "x": 1]) == "/a/b.rs")
    }
}

@MainActor
struct TranscriptStoreTests {
    @Test func appendKeepsEachSeqOnceAndInOrder() {
        let t = TranscriptStore(sessionID: "as_1")
        #expect(t.append([entry(2, .assistant("b")), entry(1, .assistant("a"))]) == 2)
        #expect(t.entries.map(\.seq) == [1, 2])
        #expect(t.append([entry(2, .assistant("b")), entry(3, .assistant("c"))]) == 1)  // a resend
        #expect(t.entries.map(\.seq) == [1, 2, 3] && t.lastSeq == 3)
    }

    @Test func hiddenEntriesAdvanceTheCursorButAreNotShown() {
        let t = TranscriptStore(sessionID: "as_1")
        t.append([entry(1, .hidden), entry(2, .assistant("x"))])
        #expect(t.entries.map(\.seq) == [2] && t.lastSeq == 2)
    }

    @Test func aToolResultJoinsItsCallsRowInPlace() {
        let t = TranscriptStore(sessionID: "as_1")
        t.append([entry(1, .toolUse(id: "t", name: "Bash", summary: "ls")), entry(2, .assistant("x"))])
        t.append([entry(3, .toolResult(id: "t", name: nil, ok: true, exitCode: 0, output: "a", durationMs: 5))])
        #expect(t.entries.map(\.seq) == [1, 2] && t.lastSeq == 3)
        if case .toolDone(_, let name, let summary, let ok, _, _, _) = t.entries[0].kind {
            #expect(name == "Bash" && summary == "ls" && ok)
        } else {
            Issue.record("expected the call and its result as one row")
        }
    }

    @Test func aHoleIsShownNotFilled() {
        let t = TranscriptStore(sessionID: "as_1")
        t.append([entry(1, .assistant("a")), entry(5, .gap(from: 2, to: 4)), entry(6, .assistant("b"))])
        #expect(t.entries.map(\.seq) == [1, 5, 6])
    }

    @Test func approvalsFollowTheirEntries() {
        let t = TranscriptStore(sessionID: "as_1")
        let now = Date()
        t.append([entry(1, .approvalRequest(id: "r", tool: "Bash", input: "ls", timeoutSecs: 60), at: now)])
        #expect(t.approvals["r"]?.status(now: now, sessionOver: false) == .pending)
        #expect(t.approvals["r"]?.status(now: now.addingTimeInterval(61), sessionOver: false) == .expired)
        #expect(t.approvals["r"]?.status(now: now, sessionOver: true) == .expired)
        t.append([entry(2, .approvalDecided(id: "r", approved: false))])
        #expect(t.approvals["r"]?.status(now: now, sessionOver: false) == .denied)
    }

    @Test func aDecisionSeenBeforeItsRequestStillApplies() {
        let t = TranscriptStore(sessionID: "as_1")
        t.start(after: 10)
        t.append([entry(12, .approvalDecided(id: "r", approved: true))])
        t.prepend([entry(11, .approvalRequest(id: "r", tool: "Bash", input: "ls", timeoutSecs: nil))], after: 10)
        #expect(t.approvals["r"]?.decision == true)
    }

    @Test func theTailLoadsFirstAndEarlierPagesPrepend() async {
        let api = FakeAgentsAPI()
        let s = AgentSessionInfo(
            id: "as_1", runner: "d_r", harness: "claude", state: .running, createdAt: Date(), updatedAt: Date())
        api.add(s, entries: (1...450).map { .assistant("m\($0)") })
        let t = TranscriptStore(sessionID: "as_1")
        await t.refresh(api, knownLast: 450)
        #expect(t.entries.first?.seq == 251 && t.entries.last?.seq == 450 && t.hasEarlier)
        await t.loadEarlier(api)
        #expect(t.entries.first?.seq == 51 && t.entries.count == 400)
        await t.loadEarlier(api)
        await t.loadEarlier(api)
        #expect(t.entries.first?.seq == 1 && !t.hasEarlier && t.entries.count == 450)
    }

    @Test func aRefreshAfterAGapContinuesFromTheCursor() async {
        let api = FakeAgentsAPI()
        api.add(
            AgentSessionInfo(
                id: "as_1", runner: "d_r", harness: "claude", state: .running, createdAt: Date(), updatedAt: Date()),
            entries: [.assistant("a")])
        let t = TranscriptStore(sessionID: "as_1")
        await t.refresh(api, knownLast: 1)
        api.append("as_1", [.assistant("b"), .assistant("c")])
        await t.resync(api, knownLast: 3)
        #expect(t.entries.map(\.seq) == [1, 2, 3])
        #expect(api.calls.filter { $0 == "transcript" }.count >= 2)
    }

    @Test func aFailedFirstLoadSaysSoAndKeepsNothing() async {
        let api = FakeAgentsAPI()
        api.add(
            AgentSessionInfo(
                id: "as_1", runner: "d_r", harness: "claude", state: .running, createdAt: Date(), updatedAt: Date()))
        api.failNext = CoreError.offline("down")
        let t = TranscriptStore(sessionID: "as_1")
        await t.refresh(api, knownLast: 0)
        if case .failed = t.load {} else { Issue.record("expected a failed load") }
    }
}

@MainActor
struct SessionsStoreTests {
    private func s(_ id: String, _ age: Double, index: Int64) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id, runner: "d_r", harness: "claude", state: .running, createdAt: Date().addingTimeInterval(-age),
            updatedAt: Date(), index: index)
    }

    @Test func upsertReplacesInPlaceAndPlacesNewOnesByTime() {
        let st = SessionsStore()
        st.upsert(s("b", 100, index: 2))
        st.upsert(s("a", 200, index: 1))
        st.upsert(s("c", 10, index: 3))
        #expect(st.items.map(\.id) == ["c", "b", "a"])
        var b = s("b", 100, index: 2)
        b.state = .ended
        st.upsert(b)
        #expect(st.items.map(\.id) == ["c", "b", "a"] && st.session("b")?.over == true)
    }

    @Test func burnSamplesOnlyWhenTheTotalChangesAndKeepsAWindow() {
        let st = SessionsStore()
        func with(_ t: Int64, cost: Int64? = nil) -> AgentSessionInfo {
            var x = s("a", 10, index: 1)
            x.usage = AgentUsageInfo(input: t, output: 0, costMicros: cost)
            return x
        }
        st.upsert(with(100))
        st.upsert(with(100))
        st.upsert(with(250, cost: 2_000_000))
        #expect(st.burn["a"] == [100, 250])
        for i in 0..<100 { st.upsert(with(Int64(300 + i))) }
        #expect(st.burn["a"]?.count == SessionsStore.burnKeep && st.burn["a"]?.last == 399)
        #expect(st.totalCostMicros == 0)  // the last update reported no cost
        st.upsert(with(400, cost: 1_500_000))
        #expect(st.totalCostMicros == 1_500_000)
    }

    @Test func promptSizeCountsBytesAgainstSixtyFourKiB() {
        #expect(!PromptSize.over(String(repeating: "a", count: 65_536)))
        #expect(PromptSize.over(String(repeating: "a", count: 65_537)))
        #expect(PromptSize.over(String(repeating: "é", count: 40_000)))  // two bytes each
        #expect(PromptSize.words("") == nil)
    }

    @Test func unknownStatesKeepTheirWord() {
        var x = s("x", 1, index: 1)
        x.state = SessionState(rawValue: "hibernating")
        #expect(x.state.label == "hibernating" && !x.live && !x.over)
        let o = SessionOutcome(rawValue: "exploded")
        #expect(o.label == "exploded")
    }

    @Test func pagesLoadOlderOnesAndStopWhenShort() async {
        let api = FakeAgentsAPI()
        for i in 1...60 { api.add(s("s\(i)", Double(1000 - i), index: Int64(i))) }
        let st = SessionsStore()
        await st.reload(api)
        #expect(st.items.count == 50 && st.hasMore)
        await st.loadMore(api)
        #expect(st.items.count == 60 && !st.hasMore)
    }
}
