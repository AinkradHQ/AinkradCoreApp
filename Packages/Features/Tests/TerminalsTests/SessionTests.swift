import CoreKit
import Foundation
import Testing

@testable import Terminals

@MainActor
@Suite(.serialized) struct SessionTests {
    private func make(_ t: TerminalItem = item(), service: FakeService = FakeService(), host: FakeHost = FakeHost())
        -> (TerminalSession, FakeService, FakeHost)
    {
        service.terminalList = [t]
        return (TerminalSession(item: t, runner: runner(), service: service, host: host), service, host)
    }

    @Test func outputStampsAreCoalescedToOneASecondAndBucketedIntoTheStrip() {
        let (s, _, _) = make()
        let now = Date(timeIntervalSince1970: 100_000)
        s.noteOutput(at: now.addingTimeInterval(-3_599))
        // One burst, one stamp.
        for i in (0..<10).reversed() { s.noteOutput(at: now.addingTimeInterval(-Double(i) * 0.1)) }
        #expect(s.outputTimes.count == 2)
        let heat = s.heat(now: now)
        #expect(heat.count == 12 && heat[0] == 1 && heat[11] == 1 && heat[5] == 0)
    }

    @Test func attachAsksForTouchIDThenShowsTheLink() async {
        let (s, svc, host) = make()
        host.isElevated = false
        svc.attachResults = [.success(FakeLink())]
        await s.attach()
        #expect(s.link == .attached(letterbox: false) && host.reasons.count == 1)
        #expect(svc.attachAfters == [0])
        s.shutDown()
    }

    @Test func decliningTouchIDLeavesTheTerminalRunning() async {
        let (s, svc, host) = make()
        host.declines = true
        await s.attach()
        #expect(s.link == .stepUp && svc.attachAfters.isEmpty)
        #expect(s.view.card?.actions == [.verify])
    }

    @Test func aDroppedSocketReconnectsAfterTheLastByteAndSaysResumed() async {
        let (s, svc, _) = make()
        let first = FakeLink()
        svc.attachResults = [.success(first), .success(FakeLink(seq: 5000))]
        await s.attach()
        first.push(.output(Data("hello".utf8)), cursor: 4096)
        first.push(.closed(.dropped), cursor: 4096)
        #expect(await until { s.link == .reconnecting })
        #expect(await until { s.link == .attached(letterbox: false) })
        #expect(svc.attachAfters == [0, 4096], "reattached from the byte it had")
        #expect(s.note == nil, "no note until output arrives")
        s.shutDown()
    }

    @Test func reconnectNeverPromptsAndStopsAtStepUp() async {
        let (s, svc, host) = make()
        let l = FakeLink()
        svc.attachResults = [.success(l)]
        await s.attach()
        host.isElevated = false
        l.push(.closed(.dropped))
        #expect(await until { s.link == .stepUp })
        #expect(host.reasons.count == 1, "only the first attach asked")
    }

    @Test func closeCode4003IsStepUpAndDetachKeepsTheTerminalRunning() async {
        let (s, svc, _) = make()
        let l = FakeLink()
        svc.attachResults = [.success(l)]
        await s.attach()
        l.push(.closed(.stepUpExpired))
        #expect(await until { s.link == .stepUp })

        let (d, svc2, _) = make()
        let l2 = FakeLink()
        svc2.attachResults = [.success(l2)]
        await d.attach()
        d.detach()
        #expect(d.link == .none && l2.detached && d.item.status == "running")
    }

    @Test func attachRefusalsBecomeWordsAndTheChildExitEndsTheLink() async {
        let (s, svc, _) = make()
        svc.attachResults = [.failure(.http(status: 429, code: "too_many_attaches", message: "Too many."))]
        await s.attach()
        #expect(s.link == .failed(code: "too_many_attaches", message: "Too many."))

        let (e, svc2, _) = make()
        let l = FakeLink()
        svc2.attachResults = [.success(l)]
        await e.attach()
        l.push(.exited(code: 3, signal: nil))
        #expect(await until { e.item.status == "exited" })
        #expect(e.item.exitCode == 3 && e.view.chip.label == "Exited · code 3" && l.detached)
    }

    @Test func othersAttachedMeansLetterboxUntilWeType() async {
        let (s, svc, _) = make(item(attached: 1))
        let l = FakeLink(cols: 64, rows: 24)
        svc.attachResults = [.success(l)]
        await s.attach()
        #expect(s.link == .attached(letterbox: true) && s.item.cols == 64)
        s.surface.onInput?(Data("x".utf8))
        #expect(s.link == .attached(letterbox: false))
        #expect(l.inputs == [Data("x".utf8)])
        s.shutDown()
    }

    @Test func signalAndEndNeedElevationAndReport() async {
        let (s, svc, host) = make()
        #expect(await s.run(.stop))
        #expect(svc.signals == ["INT"] && host.reasons.isEmpty)
        #expect(await s.run(.pause) && s.paused)
        #expect(await s.run(.resume) && !s.paused && svc.signals == ["INT", "TSTP", "CONT"])
        host.declines = true
        #expect(!(await s.run(.forceQuit)) && svc.signals == ["INT", "TSTP", "CONT"])
        host.declines = false
        #expect(await s.run(.forceQuit) && host.reasons.last?.contains("SIGKILL") == true)
        #expect(await s.end() && svc.closed == ["t_1"] && s.item.status == "exited")
    }
}
