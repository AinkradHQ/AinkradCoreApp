import CoreUI
import SwiftUI

/// Motion of the account page, from the mockup: bars fill in 700 ms, chart columns grow in 500 ms 35 ms apart, the verdict
/// swaps with a 340 ms fade, 4 pt rise and 2 pt blur, a blip runs each flowing link every 1.5 s. Reduce Motion keeps every
/// cue still: bars stand at their value, the links are plain accent lines, swaps are 200 ms fades.
enum DetailMotion {
    static func swap(_ reduce: Bool) -> Animation { reduce ? .easeOut(duration: 0.2) : Motion.out(0.34) }
    static func fill(_ reduce: Bool) -> Animation? { reduce ? nil : Motion.out(0.7) }
    static let blip: Double = 1.5
}

extension EnvironmentValues {
    /// Reduce Motion for the account page: the system's, or the snapshot walk's stand-in.
    @Entry var detailReduce = false
    /// False for the first frame of the page, so its bars grow from zero.
    @Entry var detailShown = true
}

extension View {
    /// Swaps its content with a fade, a 4 pt rise and a light blur whenever `key` changes.
    func detailSwap<K: Hashable>(_ key: K) -> some View { modifier(DetailSwap(key: key)) }
}

private struct DetailSwap<K: Hashable>: ViewModifier {
    let key: K
    @Environment(\.detailReduce) private var reduce
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            content.id(key)
                .transition(
                    .asymmetric(
                        insertion: reduce
                            ? .opacity : .opacity.combined(with: .offset(y: 4)),
                        removal: .opacity))
        }
        .animation(DetailMotion.swap(reduce), value: key)
    }
}

/// A rounded bar that fills to `value` (from zero when the page opens), with an optional tick at `tick`.
struct DetailBar: View {
    let value: Double
    var tick: Double?
    var height: CGFloat = 10
    var tint: Color?
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.detailReduce) private var reduce
    @Environment(\.detailShown) private var shown

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                coreShape(3).fill(palette.track)
                coreShape(3).fill(tint ?? GlassInk.accent(accent))
                    .frame(width: w * min(1, max(0, shown || reduce ? value : 0)))
                if let tick {
                    // A 1 pt gap in the page's colour keeps the tick readable over a fill of any accent.
                    coreShape(1).fill(GlassInk.primary.opacity(0.85)).frame(width: 2, height: height + 6)
                        .padding(.horizontal, 1).background(palette.bg, in: coreShape(2))
                        .offset(x: min(w - 4, max(0, w * tick - 2)))  // grid: ok the tick marks a share of the bar
                }
            }
            .animation(DetailMotion.fill(reduce), value: shown)
            .animation(DetailMotion.fill(reduce), value: value)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// The AI order as a lane: where new AI sessions come in, each account of the order, and the lines between them. The
/// lines up to the account that takes new work now carry the flow; an account it passes over is dimmed with a dashed line.
struct DetailLane: View {
    let model: AccountsModel
    let account: AccountItem
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette

    var body: some View {
        let rows = Self.shown(model.laneRows, me: account.id)
        let work = rows.firstIndex { $0.chip == .inUse }
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: Space.s2) {
                IconTile("sparkles", hue: GlassInk.slate, size: 36)
                Text("New AI sessions").coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 96)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                DetailLink(
                    flow: work.map { i <= $0 } ?? false, passed: work.map { i < $0 } ?? false, delay: Double(i) * 0.18)
                node(row, work: i == work)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The AI order")
    }

    /// The first four, or the first three and this account when it sits further down.
    static func shown(_ rows: [OrderRow], me: Int64) -> [OrderRow] {
        guard rows.count > 4, let i = rows.firstIndex(where: { $0.account.id == me }), i >= 4 else {
            return Array(rows.prefix(4))
        }
        return Array(rows.prefix(3)) + [rows[i]]
    }

    private func node(_ row: OrderRow, work: Bool) -> some View {
        let me = row.account.id == account.id
        let skip = !OrderChips.usable(row.chip)
        let share = Self.share(row.account)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                IconTile(
                    ProviderLook.symbol(row.account.provider), hue: work ? GlassInk.accentInk(accent) : GlassInk.slate,
                    size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    Text("\(DetailFacts.ordinal(row.number)) · \(me ? "this account" : model.kindName(row.account))")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            DetailBar(
                value: share?.0 ?? 0, height: 4,
                tint: row.chip == .limitHit || (me && model.detailState(account) == .full) ? palette.warning : nil)
            Group {
                if work {
                    StateBadge("Takes new work", tone: .run, symbol: "checkmark")
                } else if me && skip {
                    let w = model.detailWords(account)
                    StateBadge(w.chip, tone: w.tone, symbol: w.symbol)
                } else if skip {
                    StateBadge(row.chip.badge.label, tone: row.chip.badge.tone, symbol: row.chip.badge.symbol)
                } else {
                    Text(share?.1 ?? row.sentence).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: MacSize.chip, alignment: .leading)
            .detailSwap("\(work)-\(row.chip)")
        }
        .padding(Space.s3)
        .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
        .background(me ? GlassInk.wellHover : .clear, in: coreShape(Radius.cardMac))
        .opacity(skip ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    /// The bar and its words: a plan's 5-hour window, else the Core's meter, else the month's spend of its budget.
    static func share(_ a: AccountItem) -> (Double, String)? {
        if let w = a.health?.windows.first(where: { $0.name == "five_hour" }) {
            return (w.utilization, "\(Int((min(1, w.utilization) * 100).rounded()))% of 5 hours")
        }
        if let s = a.monthSpendUSDMicros, let l = a.monthLimitUSDMicros, l > 0 {
            let f = Double(s) / Double(l)
            return (f, "\(Int((min(1, f) * 100).rounded()))% of budget")
        }
        if let f = a.meter?.fraction { return (f, "\(Int((min(1, f) * 100).rounded()))% used") }
        return nil
    }
}

/// The line between two lane nodes. `flow`: new work travels it (a 22 pt blip every 1.5 s); `passed`: the account before
/// it is skipped, so the line is dashed. Reduce Motion: a flowing line is plain accent, no blip.
struct DetailLink: View {
    let flow: Bool
    let passed: Bool
    let delay: Double
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.detailReduce) private var reduce

    var body: some View {
        GeometryReader { g in
            let w = max(0, g.size.width - Space.s3)
            ZStack(alignment: .leading) {
                if passed {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 1))
                        p.addLine(to: CGPoint(x: w, y: 1))
                    }
                    .stroke(GlassInk.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .frame(width: w, height: 2)
                } else {
                    coreShape(1)
                        .fill(
                            flow
                                ? (reduce ? GlassInk.accent(accent) : GlassInk.accent(accent).opacity(0.55))
                                : palette.track
                        )
                        .frame(width: w, height: 2)
                }
                if flow && !reduce {
                    TimelineView(.animation) { tl in
                        let t =
                            (tl.date.timeIntervalSinceReferenceDate + delay)
                            .truncatingRemainder(dividingBy: DetailMotion.blip) / DetailMotion.blip
                        coreShape(1).fill(GlassInk.accentInk(accent)).frame(width: 22, height: 2)
                            .opacity(min(1, min(t, 1 - t) / 0.15))
                            .offset(x: max(0, w - 22) * t)  // grid: ok motion
                    }
                }
            }
            .padding(.horizontal, Space.s2 - 2)
            .frame(maxHeight: .infinity)
            .animation(Motion.out(Motion.ui), value: flow)
        }
        .frame(width: Space.s8 + Space.s4, height: 2)
        .accessibilityHidden(true)
    }
}
