import Foundation
import Testing

@testable import Agents

/// Every kind of content a session shows has its own entry and card (2026-11-15).
struct SessionContentTests {
    @Test func aSubAgentToolBecomesASubAgentCard() {
        let k = EntryParser.rich(
            id: "t1", name: "Task",
            input: ["subagent_type": "Explore", "description": "Find the limits", "prompt": "Search the Core"])
        #expect(
            k
                == .subAgent(
                    id: "t1", type: "Explore", task: "Find the limits", prompt: "Search the Core", result: nil, ok: nil,
                    durationMs: nil))
    }

    @Test func aPlanToolBecomesAPlanCard() {
        #expect(
            EntryParser.rich(id: "p", name: "ExitPlanMode", input: ["plan": "1. Measure"])
                == .plan(id: "p", text: "1. Measure"))
        #expect(EntryParser.rich(id: "x", name: "Bash", input: ["command": "ls"]) == nil)
    }

    @Test func aMessageKeepsItsWordsAndItsFiles() {
        let m = MessageFiles.split("Look at this\n\n@/tmp/a.png @/tmp/b.txt")
        #expect(m.words == "Look at this")
        #expect(m.files == ["/tmp/a.png", "/tmp/b.txt"])
        #expect(MessageFiles.split("email me @ noon").files.isEmpty)
    }

    @Test func anImageLineIsAnImageBlock() {
        #expect(
            MarkdownBlock.parse("![Chart](https://example.com/c.png)") == [
                .image(alt: "Chart", src: "https://example.com/c.png")
            ])
    }
}
