import Testing

@testable import Agents

struct ApprovalQuestionTests {
    @Test func theCardTitleIsAQuestion() {
        #expect(ApprovalWords.ask("Bash").question == "Run this command?")
        #expect(ApprovalWords.ask("Edit").question == "Change this file?")
        #expect(ApprovalWords.ask("WebFetch").question == "Reach the internet?")
        #expect(ApprovalWords.ask("Weird").question == "Use Weird?")
    }
}
