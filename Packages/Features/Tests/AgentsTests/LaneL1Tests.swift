import Foundation
import Testing

@testable import Agents

struct LaneL1Tests {
    @Test func titleIsTheFirstLineOfThePrompt() {
        #expect(AgentWords.title(prompt: "\n  Fix the tests \nthen push") == "Fix the tests")
        #expect(AgentWords.title(prompt: "   ") == nil)
        #expect(AgentWords.title(prompt: nil) == nil)
        #expect(AgentWords.title(prompt: String(repeating: "あ", count: 200))!.count == 90)
        let s = AgentSessionInfo(
            id: "as_01JC8ZK9R003", runner: "d", harness: "claude-code", state: .running, createdAt: Date(),
            updatedAt: Date())
        #expect(AgentWords.fallbackTitle(s) == "Claude · K9R003")
    }

    @Test func endedCodesBecomeWords() {
        #expect(AgentWords.endedWords("token_cap") == "Ended: token limit reached")
        #expect(AgentWords.endedWords("budget") == "Ended: budget reached")
        #expect(AgentWords.reasonWords("host_lost") == "The runner's terminal process was lost")
        #expect(AgentWords.reasonWords("paused by admin") == "Cancelled")
        #expect(AgentWords.reasonWords("some_new_code") == "Some new code")
        #expect(AgentWords.reasonWords("It asked to stop.") == "It asked to stop.")
    }

    @Test func promptSizeShowsOnlyNearTheLimit() {
        let limit = PromptSize.limit
        #expect(AgentWords.promptSizeWords(bytes: 10, limit: limit) == nil)
        #expect(AgentWords.promptSizeWords(bytes: limit - 2048, limit: limit) == "About 2 KiB left")
        #expect(AgentWords.promptSizeWords(bytes: limit + 7000, limit: limit)?.hasPrefix("Too long") == true)
    }

    @Test func noAccountLeftNamesEachStep() {
        let e = FailoverEnd(
            result: "ended", why: "no account is available", reasons: ["entry 1: cooling", "entry 3: at cap"])
        let t = SessionCues.notMoved(e, steps: ["claude · sonnet", "codex · default model"])!
        #expect(t.text.contains("Claude · sonnet: cooling."))
        #expect(t.text.contains("Chain step 3: at cap."))
        #expect(!t.text.lowercased().contains("entry"))
    }

    @Test func lettersTypedInAFieldAreNotShortcuts() {
        for k in ["a", "c", "k", "r", "f", "h", "w", "K"] {
            #expect(PaneKeys.shortcut(k, typing: true) == nil)
        }
        #expect(PaneKeys.shortcut("K", typing: false) == "k")
        #expect(PaneKeys.shortcut("f", typing: false) == nil)
    }

    @MainActor @Test func transcriptKeepsAWindowAndRemembersWhereItStops() {
        let t = TranscriptStore(sessionID: "as_1")
        let n = TranscriptStore.window + 50
        t.append((1...n).map { TranscriptEntry(seq: Int64($0), at: Date(), kind: .assistant("x\($0)")) })
        #expect(t.entries.count == TranscriptStore.window)
        #expect(t.entries.first?.seq == 51)
        #expect(t.heldAfter == 50 && t.hasEarlier)
    }
}
