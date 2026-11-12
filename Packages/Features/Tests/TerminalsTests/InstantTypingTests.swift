import Foundation
import Testing

@testable import Terminals

@Suite struct InstantTypingTests {
    /// A screen whose cursor row is `text` and whose cursor sits at `x`.
    func screen(_ text: String, x: Int, alt: Bool = false, nextBlank: Bool = true) -> PredictionScreen {
        let row = Array(text)
        return PredictionScreen(
            x: x, y: 5, cols: 80, alternate: alt, atBottom: true, nextBlank: nextBlank,
            cell: { $0 < row.count ? row[$0] : " " })
    }
    func key(_ s: String) -> Data { Data(s.utf8) }
    let t0 = Date(timeIntervalSince1970: 1000)

    /// An engine that has measured a slow link and proven the line echoes.
    func slowAndTrusted() -> InstantTyping {
        var e = InstantTyping()
        var prompt = "$ "
        var now = t0
        for ch in ["a", "b", "c"] {
            e.typed(key(ch), screen(prompt, x: prompt.count), now: now)
            now = now.addingTimeInterval(0.2)
            prompt += ch
            e.output(screen(prompt, x: prompt.count), now: now)
        }
        #expect(e.showing == false)  // nothing pending
        return e
    }

    @Test func aTypedKeyShowsOnlyOnceTheLinkIsSlowAndTheLineProvenToEcho() {
        var e = InstantTyping()
        e.typed(key("a"), screen("$ ", x: 2), now: t0)
        #expect(!e.showing, "first key of a line is only tracked")
        e.output(screen("$ a", x: 3), now: t0.addingTimeInterval(0.2))
        #expect(e.trusted && e.slow, "rtt \(String(describing: e.rtt))")
        e.typed(key("b"), screen("$ a", x: 3), now: t0.addingTimeInterval(1))
        #expect(e.showing)
        #expect(e.cells.cells.map { "\($0.x)\($0.ch)" } == ["3b"] && e.cells.row == 5 && e.cursorX == 4)
    }

    @Test func realOutputConfirmsAndClearsThePrediction() {
        var e = slowAndTrusted()
        e.typed(key("d"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        #expect(e.showing)
        e.output(screen("$ abcd", x: 6), now: t0.addingTimeInterval(1.2))
        #expect(!e.hasPending && !e.showing && e.trusted)
    }

    @Test func aPartialEchoKeepsTheRestPredicted() {
        var e = slowAndTrusted()
        let now = t0.addingTimeInterval(1)
        e.typed(key("d"), screen("$ abc", x: 5), now: now)
        e.typed(key("e"), screen("$ abc", x: 5), now: now)
        e.output(screen("$ abcd", x: 6), now: now.addingTimeInterval(0.2))
        #expect(e.showing && e.cells.cells.map(\.ch) == ["e"])
    }

    @Test func aMismatchDropsThePredictionsAndStopsTrusting() {
        var e = slowAndTrusted()
        e.typed(key("d"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        e.output(screen("$ abcX", x: 6), now: t0.addingTimeInterval(1.2))
        #expect(!e.hasPending && !e.showing && !e.trusted)
        e.typed(key("e"), screen("$ abcX", x: 6), now: t0.addingTimeInterval(2))
        #expect(!e.showing, "tracked again, but shown only after one is confirmed")
    }

    @Test func backspaceErasesWhatWeTypedAndIsConfirmedByTheEcho() {
        var e = slowAndTrusted()
        e.typed(key("\u{7f}"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        #expect(e.showing && e.cells.cells.map { "\($0.x)" } == ["4"] && e.cells.cells[0].ch == " ")
        e.output(screen("$ ab", x: 4), now: t0.addingTimeInterval(1.2))
        #expect(!e.hasPending && e.trusted)
    }

    @Test func backspaceDoesNotEatThePromptOrTextWeDidNotType() {
        var e = InstantTyping()
        e.typed(key("\u{7f}"), screen("$ ", x: 2), now: t0)
        #expect(!e.hasPending)
    }

    @Test func anAlternateScreenNeverPredicts() {
        var e = slowAndTrusted()
        e.typed(key("d"), screen("$ abc", x: 5, alt: true), now: t0.addingTimeInterval(1))
        #expect(!e.hasPending && !e.showing)
        e.typed(key("d"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        e.output(screen("", x: 0, alt: true), now: t0.addingTimeInterval(1.1))
        #expect(!e.hasPending, "vim opened under the prediction")
    }

    @Test func aPasswordPromptNeverShowsAndTimesOut() {
        var e = InstantTyping()
        e.typed(key("p"), screen("Password:", x: 9), now: t0)
        e.typed(key("w"), screen("Password:", x: 9), now: t0.addingTimeInterval(0.1))
        #expect(!e.showing)
        e.output(screen("Password:", x: 9), now: t0.addingTimeInterval(3))
        #expect(!e.hasPending && !e.trusted)
    }

    @Test func aFastLinkTurnsItselfOff() {
        var e = slowAndTrusted()
        #expect(e.slow)
        var line = "$ abc"
        var now = t0.addingTimeInterval(10)
        for ch in ["d", "e", "f", "g", "h", "i", "j", "k"] {
            e.typed(key(ch), screen(line, x: line.count), now: now)
            now = now.addingTimeInterval(0.005)
            line += ch
            e.output(screen(line, x: line.count), now: now)
        }
        #expect(!e.slow)
        e.typed(key("z"), screen(line, x: line.count), now: now)
        #expect(!e.showing)
    }

    @Test func offModeNeverPredictsAndControlKeysResetTheLine() {
        var off = InstantTyping()
        off.mode = .off
        off.typed(key("a"), screen("$ ", x: 2), now: t0)
        #expect(!off.hasPending)
        var e = slowAndTrusted()
        e.typed(key("\r"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        #expect(!e.trusted && !e.hasPending)
        e.typed(key("\u{1b}[A"), screen("$ abc", x: 5), now: t0.addingTimeInterval(1))
        #expect(!e.hasPending)
    }

    @Test func notAtTheEndOfTheLineOrNearTheEdgeItDoesNotPredict() {
        var e = slowAndTrusted()
        e.typed(key("d"), screen("$ abcxyz", x: 5, nextBlank: false), now: t0.addingTimeInterval(1))
        #expect(!e.hasPending)
        e.typed(key("d"), screen("$ abc", x: 79), now: t0.addingTimeInterval(1))
        #expect(!e.hasPending)
    }
}
