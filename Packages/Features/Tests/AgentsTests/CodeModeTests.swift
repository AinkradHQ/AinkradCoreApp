import CoreKit
import Foundation
import Shell
import Testing

@testable import Agents

struct CodeModeTests {
    @Test func toolNamesAreRecognisedWithOrWithoutTheHarnessPrefix() {
        #expect(CodeModeTool.of("ainkrad_run") == .run)
        #expect(CodeModeTool.of("mcp__ainkrad__ainkrad_run") == .run)
        #expect(CodeModeTool.of("mcp__ainkrad__ainkrad_search") == .search)
        #expect(CodeModeTool.of("Bash") == nil)
    }

    @Test func aFinishedScriptGivesValueConsoleAndFooter() {
        let r = CodeModeResult.parse("{\"open\":4}\nconsole:\nfound 4\n[3 calls, 1180 ms]")
        #expect(r.value == "{\"open\":4}" && r.console == "found 4")
        #expect(r.calls == 3 && r.ms == 1180 && r.footer == "[3 calls, 1180 ms]")
        #expect(r.code == nil && r.message == nil)
    }

    @Test func aFailedScriptGivesMessageLineAndRefusalCodeInWords() {
        let r = CodeModeResult.parse("error: too many calls (line 7) [too_many_calls]\n[100 calls, 8210 ms]")
        #expect(r.message == "too many calls" && r.line == 7 && r.code == "too_many_calls")
        #expect(r.summary == CodeModeWords.refusal("too_many_calls"))
        #expect(r.footer == "[100 calls, 8210 ms]")
    }

    @Test func oneCallIsSingular() {
        #expect(CodeModeResult.parse("null\n[1 call, 5 ms]").footer == "[1 call, 5 ms]")
    }

    @Test func aCoreHeldApprovalReadsAsACodeModeAsk() {
        let input =
            #"{"summary":"Create an issue","args":{"project":"CP","api_token":"[redacted]"},"reason":"Reaches Jira."}"#
        let r = ApprovalRequest(
            id: "cm_1", session: "s", tool: "ainkrad.connections.jira.create_issue", input: input,
            requestedAt: .now, timeoutSecs: 100)
        #expect(r.codeModeOp == "connections.jira.create_issue")
        let ask = r.codeMode
        #expect(ask?.summary == "Create an issue" && ask?.reason == "Reaches Jira.")
        #expect(ask?.args.map(\.key) == ["api_token", "project"])
        #expect(ask?.args.first?.hidden == true && ask?.args.last?.hidden == false)
        #expect(r.shownInput == "Create an issue")
        #expect(ApprovalWords.ask(r.tool).verb == "create issue with Jira")
    }

    @Test func aHarnessApprovalIsNotACodeModeCard() {
        let r = ApprovalRequest(
            id: "r", session: "s", tool: "Bash", input: "{\"summary\":\"x\"}", requestedAt: .now, timeoutSecs: nil)
        #expect(r.codeMode == nil && r.shownInput == "{\"summary\":\"x\"}")
    }

    @Test func operationsReadAsPlainWords() {
        #expect(CodeModeWords.op("brainAiSearch").did == "searched the Brain")
        #expect(CodeModeWords.op("connections.github.get_issue").did == "read issue with GitHub")
        #expect(CodeModeWords.op("getCoreHealth").will == "check the Core's health")
        #expect(CodeModeWords.op("createWidget").will == "create widget")
    }
}

@MainActor
struct CoreHeldApprovalTests {
    private static let input = #"{"summary":"Create an issue","args":{"project":"CP"},"reason":"Reaches Jira."}"#
    private func held(_ id: String, at: Date = Date(timeIntervalSince1970: 1_000)) -> CoreApproval {
        CoreApproval(
            id: id, tool: "ainkrad.connections.jira.create_issue", input: Self.input, requestedAt: at,
            expiresAt: at.addingTimeInterval(900))
    }

    @Test func aListedApprovalIsPendingUntilItsTimeRunsOut() {
        let t = TranscriptStore(sessionID: "s")
        t.holdCore([held("cm_1")])
        let r = t.approvals["cm_1"]
        #expect(r?.codeMode?.summary == "Create an issue" && r?.timeoutSecs == 900)
        #expect(r?.status(now: Date(timeIntervalSince1970: 1_100), sessionOver: false) == .pending)
        #expect(r?.status(now: Date(timeIntervalSince1970: 1_900), sessionOver: false) == .expired)
    }

    @Test func oneTheCoreNoLongerListsGoesUnlessYouAnsweredIt() {
        let t = TranscriptStore(sessionID: "s")
        t.holdCore([held("cm_1"), held("cm_2")])
        t.mark("cm_2", approved: true)
        t.holdCore([])
        #expect(t.approvals["cm_1"] == nil)
        #expect(t.approvals["cm_2"]?.decision == true)
        #expect(t.heldList.map(\.id) == ["cm_2"])
    }

    @Test func aFetchFailureOrAnEmptyReadKeepsNothingStale() async {
        let api = FakeAgentsAPI()
        api.held["s"] = [held("cm_1")]
        let m = (try? await api.approvals("s")) ?? []
        #expect(m.map(\.id) == ["cm_1"])
        _ = try? await api.decide("s", request: "cm_1", approved: false)
        #expect(((try? await api.approvals("s")) ?? []).isEmpty)
    }

    @Test func closedAndUnknownRequestsAreNewsNotErrors() {
        let gone = AgentsModel.closedApproval(CoreError.http(status: 404, code: "not_found", message: "x"))
        let closed = AgentsModel.closedApproval(CoreError.http(status: 409, code: "approval_closed", message: "x"))
        #expect(gone?.title == "The Core no longer has this request.")
        #expect(closed?.title == "This request was already answered or timed out.")
        #expect(gone?.tone == .queue && closed?.tone == .queue)
        #expect(AgentsModel.closedApproval(CoreError.http(status: 409, code: "other", message: "x")) == nil)
        #expect(AgentsModel.closedApproval(CoreError.http(status: 500, code: "boom", message: "x")) == nil)
    }
}
