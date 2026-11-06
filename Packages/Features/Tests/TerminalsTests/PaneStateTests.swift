import Testing

@testable import Terminals

/// Every state the prototype shows, from what the API can say. Words are the prototype's; nothing is invented.
@MainActor @Suite struct PaneStateTests {
    private func view(
        _ t: TerminalItem, _ link: Link = .none, runner r: RunnerItem? = runner(), note: ResumeNote? = nil
    )
        -> PaneView
    { PaneView.make(item: t, runner: r, link: link, note: note) }

    @Test func attachedHereSoleAndLetterboxed() {
        let live = view(item(attached: 1), .attached(letterbox: false))
        #expect(live.chip.label == "Attached" && live.controls == .running && live.banner == nil)
        #expect(live.info == "80×24 · sized by this Mac · 1 attached")
        let lb = view(item(attached: 2), .attached(letterbox: true))
        #expect(lb.banner?.title == "Sized by another device (80×24)")
        #expect(lb.info.contains("letterboxed"))
    }

    @Test func attachedElsewhereOffersAttachHere() {
        let v = view(item(attached: 2))
        #expect(v.chip.label == "Attached elsewhere")
        #expect(v.card?.actions == [.attach] && v.card?.note == "Needs Touch ID. The screen repaints from a snapshot.")
        #expect(!v.screenVisible)
    }

    @Test func detachedIsRunningNotAttachedAndOrphanedAddsTheIdleNote() {
        let plain = view(item())
        #expect(plain.card?.title == "Still running" && plain.card?.note == "Needs Touch ID.")
        // The Core flags every running terminal with no client as orphaned: it is the same state, with the idle rule in words.
        let o = view(item(orphaned: true))
        #expect(o.chip.label == "Running, not attached" && o.card?.actions == [.attach])
        #expect(o.card?.note?.contains("idle for too long") == true && o.info.contains("closes when idle"))
    }

    @Test func endedStatesAreReadOnlyOrGone() {
        let ok = view(item(status: "exited", code: 0))
        #expect(ok.chip.label == "Exited · code 0" && ok.controls == .ended && ok.dim && ok.screenVisible)
        #expect(view(item(status: "exited", signal: "TERM")).chip.label == "Exited · signal TERM")
        #expect(view(item(status: "exited")).chip.label == "Exited · no exit code")
        let gone = view(item(status: "reaped"))
        #expect(gone.card?.title == "Output is gone" && !gone.screenVisible)
        let lost = view(item(status: "exited", signal: "host_lost"))
        #expect(lost.banner?.title == "Ended: the runner lost it" && lost.card?.actions == [.closePane, .newTerminal])
    }

    @Test func runnerOfflineBeatsNotAttached() {
        let v = view(item(), runner: runner(online: false))
        #expect(v.banner?.title == "mac-studio is not connected" && v.banner?.action == .runner)
        #expect(v.card?.actions == [.retry])
        // An attached terminal keeps its screen while the runner flaps: the link says what is true.
        #expect(
            view(item(attached: 1), .attached(letterbox: false), runner: runner(online: false)).chip.label == "Attached"
        )
    }

    @Test func linkStatesStepUpReconnectingAttachingFailed() {
        let s = view(item(), .stepUp)
        #expect(s.chip.label == "Verification expired" && s.card?.actions == [.verify] && s.dim)
        let r = view(item(), .reconnecting)
        #expect(
            r.banner?.busy == true && r.controls == .pending && r.info == "Input is paused until the connection is back"
        )
        #expect(view(item(), .attaching).banner?.busy == true)
        let f = view(item(), .failed(code: "too_many_attaches", message: "Too many clients."))
        #expect(f.banner?.title == "Too many clients." && f.banner?.help == "too_many_attaches")
    }

    @Test func resumedAndRepaintedBannersDismiss() {
        let a = view(item(attached: 1), .attached(letterbox: false), note: .resumed(from: 4_182_913, to: 4_190_000))
        #expect(a.banner?.title == "Resumed. Nothing was lost" && a.banner?.action == .dismiss)
        #expect(a.banner?.detail.contains("4,182,913") == true)
        let b = view(item(attached: 1), .attached(letterbox: false), note: .repainted)
        #expect(b.banner?.title == "Screen repainted from a snapshot")
    }

    @Test func anUnknownStatusShowsItsRawWord() {
        let v = view(item(status: "frozen"))
        #expect(v.chip.label == "Newer state" && v.banner?.title == "A newer state")
    }

    @Test func runnerStatusAndRefusals() {
        #expect(RunnerStatus(runner()) == .ok)
        #expect(RunnerStatus(runner(degraded: true)) == .degraded)
        #expect(RunnerStatus(runner(online: false)) == .off)
        #expect(RunnerStatus(runner(avg1: 36.8)) == .busy)
        let busy = NewTerminalModel.refusal(.http(status: 503, code: "runner_busy", message: "m"), runner: "r")
        #expect(busy.title == "r is too busy right now" && busy.http == 503)
        let other = NewTerminalModel.refusal(.http(status: 409, code: "something_new", message: "Words."), runner: "r")
        #expect(other.title == "Words." && other.code == "something_new")
    }
}
