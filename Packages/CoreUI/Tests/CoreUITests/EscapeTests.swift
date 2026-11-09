import Testing

@testable import CoreUI

@MainActor
struct EscapeTests {
    @Test func newestCloserGoesFirstAndOnlyOneRuns() {
        let esc = CoreEscape()
        var log: [String] = []
        esc.push {
            log.append("shell")
            return true
        }
        esc.push {
            log.append("dropdown")
            return true
        }
        #expect(esc.handle())
        #expect(log == ["dropdown"])
    }

    @Test func aCloserWithNothingToCloseLetsTheNextOneRun() {
        let esc = CoreEscape()
        var log: [String] = []
        esc.push {
            log.append("shell")
            return true
        }
        esc.push {
            log.append("empty")
            return false
        }
        #expect(esc.handle())
        #expect(log == ["empty", "shell"])
    }

    @Test func nothingHandledLeavesEscForThePane() {
        let esc = CoreEscape()
        esc.push { false }
        #expect(!esc.handle())
        #expect(!CoreEscape().handle())
    }

    @Test func removedCloserIsSkipped() {
        let esc = CoreEscape()
        var log: [String] = []
        esc.push {
            log.append("a")
            return true
        }
        let b = esc.push {
            log.append("b")
            return true
        }
        esc.remove(b)
        #expect(esc.handle())
        #expect(log == ["a"])
        #expect(esc.depth == 1)
    }
}
