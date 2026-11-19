import CoreUI
import SwiftUI

/// Sort (mockup 17): the Core sorted everything into places and accepted them; the person can undo it or go on.
struct SortStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let auto = model.auto
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(headline).coreFont(size: MacTextSize.headline, weight: .semibold)
            Text("Not sure about one? Fix it later in Places. Nothing is final.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            if case .waiting = auto.sort {
                CoreBusyBar().accessibilityHidden(true)
            }
            if let why = auto.failure {
                CoreNotice(symbol: "exclamationmark.triangle", title: why, tone: .fail) { EmptyView() }
            }
            if case .undone = auto.sort {
                WizardFooter(
                    back: ("Close", close), primary: ("Sort it myself", { model.sortMyself() }))
            } else {
                HStack(spacing: Space.s3) {
                    Button("Close", action: close).buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                    if case .sorted = auto.sort {
                        Button {
                            Task { await model.undoSort() }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(CoreButtonStyle(.secondary))
                    }
                    Spacer(minLength: Space.s3)
                    Text("Next, Brain learns from everything. This step is always done, it cannot be skipped.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    Button("Continue") { model.beginLearning() }
                        .buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(.primary).disabled(!canContinue)
                }
            }
        }
        .task(id: model.run) { model.beginSort() }
        .accessibilityIdentifier("brain-import-sort")
    }

    private var canContinue: Bool {
        switch model.auto.sort {
        case .sorted, .nothing: true
        default: false
        }
    }

    private var headline: String {
        let items = model.counts.stored.formatted()
        switch model.auto.sort {
        case .waiting: return "Sorting into places"
        case .sorted(let n): return "Sorted \(items) items into \(BrainWords.plural(n, "place", "places")), all accepted"
        case .undone(let n): return "Undone. \(n.formatted()) items are back in one pile for now."
        case .nothing: return "Nothing was sorted by itself. Sort it yourself, or keep going."
        }
    }
}

/// Learn (mockup 17): every place read and written down, with its progress, the account used and the cost so far.
struct LearnStep: View {
    let model: ImportModel

    var body: some View {
        let l = model.auto.learning
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Learning from your work").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: Space.s3)
                if let l {
                    Text(cost(l)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                        .accessibilityIdentifier("brain-import-cost")
                }
            }
            Text("Brain reads every place and writes down what matters: who you are, your rules, what you know and what happened.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            if l == nil { CoreBusyBar().accessibilityHidden(true) }
            VStack(spacing: 2) {
                ForEach(l?.places ?? []) { p in
                    CoreRow(p.name, subtitle: detail(p), symbol: p.state == "done" ? "checkmark" : "folder") {
                        trailing(p)
                    }
                }
            }
            .animation(Motion.out(Motion.ui), value: l?.places.map(\.state))
            if l?.places.contains(where: { $0.state == "waiting" }) == true {
                CoreNotice(
                    symbol: "key", title: "Brain needs an AI account",
                    text: "It cannot learn new things without one. Your Claude subscription works, and costs nothing extra."
                ) { EmptyView() }
            }
            Text("Closing this does not stop it.").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityIdentifier("brain-import-learn")
    }

    @ViewBuilder private func trailing(_ p: LearningWire.Place) -> some View {
        switch p.state {
        case "done": StateBadge("Done", tone: .done, symbol: "checkmark")
        case "waiting": StateBadge("Waiting", tone: .queue, symbol: "clock")
        case "learning":
            CoreMeter(p.sources == 0 ? 0 : min(1, Double(p.read) / Double(p.sources)), label: "\(p.name) progress")
                .frame(width: Space.s8 * 3)
        default: Text("Soon").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }

    private func detail(_ p: LearningWire.Place) -> String {
        var s = "\(p.read.formatted()) of \(p.sources.formatted()) read"
        if p.learned > 0 { s += " · learned \(p.learned.formatted())" }
        if let a = p.provider { s += " · with \(a)" }
        return s
    }

    private func cost(_ l: LearningWire) -> String {
        var s = "\(AutoFlow.dollars(l.totalCostUsdMicros)) so far"
        if l.unpriced > 0 { s += " · \(l.unpriced) not priced yet" }
        return s
    }
}

/// Done: what Brain learned, place by place, and the cost.
struct AutoDoneStep: View {
    let brain: BrainModel
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let l = model.auto.learning
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Brain learned from \(BrainWords.plural(l?.places.count ?? 0, "place", "places"))")
                .coreFont(size: MacTextSize.headline, weight: .semibold)
            if let l {
                Text("\(AutoFlow.dollars(l.totalCostUsdMicros)) in total. From now on it keeps learning by itself.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                VStack(spacing: 2) {
                    ForEach(l.places) { p in
                        CoreRow(p.name, subtitle: "Learned \(p.learned.formatted()) things", symbol: "folder")
                    }
                }
            }
            WizardFooter(
                primary: (
                    "Open the Brain",
                    {
                        brain.retry()
                        brain.explore(false)
                        brain.show(.overview)
                        close()
                    }
                ))
        }
        .accessibilityIdentifier("brain-import-done")
    }
}
