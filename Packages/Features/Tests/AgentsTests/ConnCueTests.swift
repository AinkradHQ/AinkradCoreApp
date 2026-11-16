import Testing

@testable import Agents

struct ConnCueTests {
    @Test func onlyConnectionToolsBecomeCuesAndReadAsPlainWords() {
        #expect(ConnCue.kind("github.get_issue") == "GitHub")
        #expect(ConnCue.kind("jira.create_issue") == "Jira")
        #expect(ConnCue.kind("Bash") == nil)
        #expect(ConnCue.kind("mcp.something") == nil)
        #expect(ConnCue.line("github.get_issue", "#142") == "Get issue #142 with GitHub")
        #expect(ConnCue.line("jira.create_issue", "") == "Create issue with Jira")
        // Done reads in the past, and a provider keeps its capitals.
        #expect(ConnCue.line("github.get_issue", "#142", done: true) == "Got issue #142 from GitHub")
        #expect(ConnCue.line("jira.create_issue", "", done: true) == "Created issue with Jira")
        #expect(ConnCue.lowerFirst(ConnCue.line("github.create_pull_request", "")) == "create pull request with GitHub")
    }
}
