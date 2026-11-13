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
