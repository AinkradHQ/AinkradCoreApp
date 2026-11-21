import CoreUI
import SwiftUI

/// Sort (mockup 17, review before filing): the places the Core prepared, to rename, merge or send to Unsorted, then
/// Approve. While the local model still reads, its progress; an old run the Core filed by itself shows "sorted" with Undo.
struct SortStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let r = model.review
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(headline).coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if let n = r.notice {
                CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) {
                    Button("Dismiss") { r.notice = nil }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
            if let why = model.auto.failure {
                CoreNotice(symbol: "exclamationmark.triangle", title: why, tone: .fail) { EmptyView() }
            }
            content(r)
            footer(r)
        }
        .task(id: model.run) { await model.beginSort() }
        .accessibilityIdentifier("brain-import-sort")
    }

    private var preparing: Bool { model.auto.sort == .checking || model.review.semanticState == "pending" }

    @ViewBuilder private func content(_ r: ReviewModel) -> some View {
        switch model.auto.sort {
        case .checking: CoreBusyBar().accessibilityHidden(true)
        case .sorted(let n):
            CoreNotice(
                symbol: "checkmark", title: "Filed into \(BrainWords.plural(n, "place", "places")) before review",
                text: "This import was filed by itself. Undo puts everything back in one pile to review.", tone: .done
            ) {
                if model.auto.canUndo {
                    Button {
                        Task { await model.undoSort() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                }
            }
        case .review:
            if r.semanticState == "pending" {
                progress(r)
            } else if r.opened != nil {
                ReviewDetail(review: r)
            } else if r.showingChanges {
                TidyChangesList(review: r)
            } else if let id = r.mergingFor {
                MergePicker(review: r, id: id)
            } else if r.nothingToReview {
                Text("There is nothing new to file. Everything in this import is already in your Brain.")
                    .foregroundStyle(GlassInk.secondary).padding(Space.s4).frame(maxWidth: .infinity).coreWell()
                    .accessibilityIdentifier("brain-sort-nothing")
            } else {
                PlaceList(model: model)
            }
        }
    }

    /// "The local model is reading your work · 3,210 of 12,391 · about 6 min left".
    private func progress(_ r: ReviewModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let p = r.semanticProgress {
                CoreMeter(Double(p.done) / Double(max(p.total, 1)), label: "Sorting progress")
            } else {
                CoreBusyBar().accessibilityHidden(true)
            }
            HStack(spacing: Space.s2) {
                Text("The local model is reading your work").coreFont(size: MacTextSize.meta, weight: .semibold)
                Spacer(minLength: Space.s2)
                if let p = r.semanticProgress {
                    Text(Self.count(p, left: r.readingLeft)).coreFont(size: MacTextSize.meta).monospacedDigit()
                        .foregroundStyle(GlassInk.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("brain-sort-preparing")
    }

    @ViewBuilder private func footer(_ r: ReviewModel) -> some View {
        switch model.auto.sort {
        case .sorted:
            WizardFooter(
                back: ("Close", close), note: "Next, Brain learns from everything.",
                primary: ("Continue", { model.beginLearning() }))
        default:
            // While a name is typed, Return saves it and Esc cancels it: the footer gives its keys up.
            let inside = r.opened != nil || r.mergingFor != nil || r.showingChanges
            WizardFooter(
                back: r.renaming != nil
                    ? nil
                    : inside
                        ? (
                            "Back",
                            {
                                r.closeCard()
                                r.mergingFor = nil
                                r.closeChanges()
                            }
                        ) : ("Close", close),
                note: r.approveBlock ?? (preparing ? "" : tally(r)),
                primary: (r.nothingToReview ? "Continue" : "Approve", { Task { await model.approve() } }),
                enabled: !preparing && !r.busy && !model.approving && r.approveBlock == nil && r.renaming == nil
                    && !inside)
        }
    }

    /// "7 places · 12 in Unsorted".
    private func tally(_ r: ReviewModel) -> String {
        var s = BrainWords.plural(r.places.count, "place", "places")
        if let u = r.unsortedCard { s += " · \(u.itemCount.formatted()) in Unsorted" }
        return s
    }

    /// "3,210 of 12,391 · about 6 min left".
    static func count(_ r: SemanticProgress, left: Duration?) -> String {
        var s = "\(r.done.formatted()) of \(r.total.formatted())"
        if let left {
            let m = Int((Double(left.components.seconds) / 60).rounded(.up))
            s += m <= 1 ? " · under a minute left" : " · about \(m) min left"
        }
        return s
    }

    private var headline: String {
        if preparing {
            let n = model.counts.stored
            return n > 0 ? "Getting \(n.formatted()) items ready to sort" : "Getting your places ready"
        }
        if case .sorted = model.auto.sort { return "Sorted into places" }
        return "Check the places"
    }

    private var sub: String {
        preparing
            ? "Nothing goes into the Brain until you approve."
            : "Nothing goes into the Brain until you approve. Rename, merge, or send a place to Unsorted."
    }
}

/// Learn (mockup 17): every place read and written down, with its progress, the account used and the cost so far.
struct LearnStep: View {
    let model: ImportModel
    let close: () -> Void

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
            Text(
                "Brain reads every place and writes down what matters: who you are, your rules, what you know and what happened."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            if l == nil { CoreBusyBar().accessibilityHidden(true) }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(l?.places ?? []) { p in
                        let shown = LearnWords.shown(p)
                        CoreRow(
                            p.name, subtitle: LearnWords.detail(p), symbol: p.state == "done" ? "checkmark" : "folder"
                        ) {
                            trailing(p, shown)
                        }
                        .help(p.failure ?? "")
                    }
                }
            }
            .frame(maxHeight: Space.s8 * 14)
            .fixedSize(horizontal: false, vertical: true)
            .animation(Motion.out(Motion.ui), value: l?.places.map(\.state))
            if l?.places.contains(where: { $0.state == "waiting" }) == true {
                CoreNotice(
                    symbol: "key", title: "Brain needs an AI account",
                    text:
                        "It cannot learn new things without one. Your Claude subscription works, and costs nothing extra."
                ) { EmptyView() }
            }
            HStack(spacing: Space.s3) {
                Text("Closing this does not stop it.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                Button("Close", action: close).buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            }
        }
        .accessibilityIdentifier("brain-import-learn")
    }

    @ViewBuilder private func trailing(_ p: LearningWire.Place, _ shown: LearnWords.Shown) -> some View {
        switch shown {
        case .done: StateBadge("Done", tone: .done, symbol: "checkmark")
        case .waiting: StateBadge("Waiting for an AI account", tone: .queue, symbol: "key")
        case .failed(let words): StateBadge(words, tone: .fail, symbol: "exclamationmark.triangle")
        case .reading(let f):
            CoreMeter(f, label: "\(p.name) progress").frame(width: Space.s8 * 3)
        case .soon: Text("Soon").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }

    private func cost(_ l: LearningWire) -> String {
        var s = "\(AutoFlow.dollars(l.totalCostUsdMicros)) so far"
        if l.unpriced > 0 { s += " · \(l.unpriced) not priced yet" }
        return s
    }
}

/// A Learn place in words: what its row shows.
enum LearnWords {
    enum Shown: Equatable {
        case done, waiting, soon
        case reading(Double)
        /// "Couldn't reach the AI · retrying at 12:10".
        case failed(String)
    }

    static func shown(
        _ p: LearningWire.Place, now: Date = .now, zone: TimeZone = .current, locale: Locale = .current
    ) -> Shown {
        switch p.state {
        case "done": .done
        case "waiting": .waiting
        case "learning": .reading(p.sources == 0 ? 0 : min(1, Double(p.read) / Double(p.sources)))
        case "failed": .failed(failed(p.retryAt, now: now, zone: zone, locale: locale))
        default: .soon
        }
    }

    /// A failure and when it is tried again; without a time from the Core, only that it is tried again.
    static func failed(_ retryAt: String?, now: Date, zone: TimeZone, locale: Locale) -> String {
        let base = "Couldn't reach the AI"
        guard let s = retryAt, let at = SyncWords.date(s) else { return "\(base) · it tries again by itself" }
        if at <= now { return "\(base) · retrying now" }
        var f = Date.FormatStyle(date: .omitted, time: .shortened)
        f.timeZone = zone
        f.locale = locale
        return "\(base) · retrying at \(at.formatted(f))"
    }

    /// "120 of 412 read · learned 18 · with claude".
    static func detail(_ p: LearningWire.Place) -> String {
        var s = "\(p.read.formatted()) of \(p.sources.formatted()) read"
        if p.learned > 0 { s += " · learned \(p.learned.formatted())" }
        if let a = p.provider { s += " · with \(a)" }
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
        let n = l?.places.count ?? 0
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(n == 0 ? "Nothing new to learn from" : "Brain learned from \(BrainWords.plural(n, "place", "places"))")
                .coreFont(size: MacTextSize.headline, weight: .semibold)
            if let l, n > 0 {
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
