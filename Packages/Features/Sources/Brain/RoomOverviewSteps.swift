import CoreUI
import SwiftUI

/// The three steps of a write and where each stands, mapped from the Core's `stage`.
struct OverviewSteps: Equatable {
    enum Mark { case done, active, pending }
    var pick: Mark
    var write: Mark
    var check: Mark
    /// Why it waits or retries, in one line; nil while it simply works.
    var wait: String?
    /// Queued or waiting for a runner: nothing is being written yet, so no clock.
    var waiting: Bool { stageWaits }
    private var stageWaits = false

    /// Nil when the Core sent no stage (an older Core): the caller keeps the plain "Writing…" line.
    init?(_ stage: OverviewStage?, picked: Int? = nil) {
        switch stage {
        case nil: return nil
        case .queued:
            self.init(.active, .pending, .pending, "Waiting for its turn (one room at a time)")
            stageWaits = true
        case .waitingRunner:
            let text = "Waiting for a runner with a sandbox to come online"
            // A runner is needed once the items are chosen, so a known count means the choosing is behind us.
            if picked != nil {
                self.init(.done, .active, .pending, text)
            } else {
                self.init(.active, .pending, .pending, text)
            }
            stageWaits = true
        case .picking: self.init(.active, .pending, .pending, nil)
        case .reading: self.init(.done, .done, .active, nil)
        case .retrying: self.init(.done, .active, .pending, "The first answer could not be used. Trying once more.")
        case .starting, .writing, .other: self.init(.done, .active, .pending, nil)
        }
    }

    private init(_ a: Mark, _ b: Mark, _ c: Mark, _ wait: String?) {
        pick = a
        write = b
        check = c
        self.wait = wait
    }

    /// "1:05" for 65 seconds; minutes are not capped, a negative span reads 0:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

/// The writing state's step list: done steps a check, the active one the working bar, pending ones a quiet marker.
struct OverviewStepList: View {
    let steps: OverviewSteps
    let picked: Int?
    /// When the current stage began; the clock counts from here.
    let since: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            row("Pick the items that matter", steps.pick) {
                if steps.pick == .done, let n = picked {
                    Quiet("Picked \(n.formatted()) \(n == 1 ? "item" : "items") on your Core")
                }
            }
            row("Your AI account writes the overview", steps.write) {
                if steps.write == .active, !steps.waiting { clock }
            }
            row("Check and save", steps.check) {}
        }
        .coreFont(size: MacTextSize.body)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview-steps")
    }

    private func row<D: View>(_ title: String, _ mark: OverviewSteps.Mark, @ViewBuilder detail: () -> D) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Marker(mark: mark)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).foregroundStyle(mark == .pending ? GlassInk.secondary : GlassInk.primary)
                if mark == .active, let w = steps.wait { Quiet(w) }
                detail()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var clock: some View {
        if let since {
            // Ticks every second; the Core itself is polled on the model's own 2 s beat.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Quiet(OverviewSteps.clock(ctx.date.timeIntervalSince(since))).monospacedDigit()
            }
        }
        Quiet("This usually takes 1 to 3 minutes.")
    }
}

private struct Quiet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
}

/// A rounded-square box: a check when done, the sweeping bar when active (waiting shows it still), an empty well pending.
private struct Marker: View {
    let mark: OverviewSteps.Mark
    var body: some View {
        Group {
            switch mark {
            case .done:
                Image(systemName: "checkmark").font(.system(size: MacTextSize.meta, weight: .semibold))
                    .foregroundStyle(GlassInk.green)
            case .active: CoreWorkingBar(width: Space.s5)
            case .pending: coreShape(Space.s1 / 2).fill(GlassInk.track).frame(width: Space.s2, height: Space.s2)
            }
        }
        .frame(width: Space.s5, height: Space.s4 + Space.s1 / 2, alignment: .leading)
        .accessibilityHidden(true)
    }
}
