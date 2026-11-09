import CoreUI
import SwiftUI

private let tileColumns = [GridItem(.adaptive(minimum: Space.s8 * 6), spacing: Space.s3, alignment: .top)]
private let needColumns = [GridItem(.adaptive(minimum: Space.s8 * 6), spacing: Space.s3, alignment: .top)]

/// Overview: what needs you, how healthy the Brain is, records per mounted room and how fast search is. It reads what
/// the service says; it never computes health (BM-85, BM-89).
struct OverviewTab: View {
    let model: BrainModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            banner
            if model.health == .paused {
                BrainNotice(
                    symbol: "exclamationmark.octagon", title: BrainWords.pausedLine(names: model.pausedNames),
                    tone: .fail)
            }
            if !model.visibleNeeds.isEmpty {
                LazyVGrid(columns: needColumns, spacing: Space.s3) {
                    ForEach(model.visibleNeeds) { n in NeedTile(model: model, need: n) }
                }
            }
            if let o = model.overview {
                BrainTitle("Health")
                LazyVGrid(columns: tileColumns, spacing: Space.s3) {
                    ForEach(o.tiles) { HealthTileView(tile: $0) }
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    RecordsPerRoom(model: model)
                    SpeedChart(speed: o.speed, target: o.speedTarget)
                }
                .fixedSize(horizontal: false, vertical: true)
                Facts(facts: o.facts)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-overview")
    }

    /// Paused is red with the way out; Needs you is a blue count; Healthy is green. Same words on every surface.
    @ViewBuilder private var banner: some View {
        let n = model.needsTotal
        switch model.health {
        case .paused:
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Text("Paused").font(.system(size: MacTextSize.large, weight: .semibold))
                            .foregroundStyle(GlassInk.redInk)
                        count(n, GlassInk.red)
                    }
                    Text(BrainWords.pausedWhy).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                Button {
                    Task { await model.clearPaused() }
                } label: {
                    Text("Clear pause with Touch ID")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.busy != nil)
            }
            .padding(Space.s4).background(GlassInk.red.opacity(0.14), in: coreShape(Radius.cardMac))
        case .needsYou:
            head("Needs you", GlassInk.blue, n, "Some things wait for a decision. Nothing is wrong.")
        case .healthy:
            head("Healthy", GlassInk.green, nil, "Nothing waits for you. Every check is in date.")
        }
    }

    private func head(_ title: String, _ hue: Color, _ n: Int?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).foregroundStyle(hue)
                if let n { count(n, hue) }
            }
            Text(text).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(hue.opacity(0.12), in: coreShape(Radius.cardMac))
    }

    private func count(_ n: Int, _ hue: Color) -> some View {
        Text("\(n)").font(.system(size: MacTextSize.meta, weight: .bold)).monospacedDigit()
            .padding(.horizontal, 6).frame(minHeight: 18).background(hue, in: coreShape(5))
    }
}

/// One thing that waits: its count, what it is, and (for a mounted room) the room's name. Opens the tab that settles it.
private struct NeedTile: View {
    let model: BrainModel
    let need: NeedItem
    @State private var hovering = false
    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { model.tab = need.tab }
        } label: {
            HStack(spacing: Space.s3) {
                Text("\(need.n)").font(.system(size: MacTextSize.large, weight: .bold)).monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(BrainWords.glue(need.text)).font(.system(size: MacTextSize.body)).fixedSize(
                        horizontal: false, vertical: true)
                    if let name = model.roomName(need) {
                        Text(name).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 2, alignment: .leading)
            .background(GlassInk.blue.opacity(hovering ? 0.2 : 0.12), in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: hovering)
        .accessibilityLabel(
            "\(need.n) \(need.text)\(model.roomName(need).map { ", \($0)" } ?? ""). Opens \(need.tab.title).")
    }
}

private struct HealthTileView: View {
    let tile: HealthTile
    var body: some View {
        let (label, hue) = style
        let plain = BrainWords.tile(tile.id, tile.name)
        VStack(alignment: .leading, spacing: Space.s2) {
            // The tag keeps its whole word: when title and tag do not fit side by side the tag drops under the title.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    title(plain.name)
                    Spacer(minLength: Space.s2)
                    BrainChip(label, hue)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    title(plain.name)
                    BrainChip(label, hue)
                }
            }
            BrainBar(fraction: tile.meter / 100, hue: hue)
            Text(BrainWords.glue(tile.text)).foregroundStyle(GlassInk.secondary).fixedSize(
                horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading).coreWell()
        .help(plain.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plain.name), \(label). \(tile.text). \(plain.help)")
    }
    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
    }
    /// Words and colour together: nothing is only a colour.
    private var style: (String, Color) {
        switch tile.status {
        case .ok: ("Good", GlassInk.green)
        case .warn: ("Needs a look", GlassInk.blue)
        case .bad: ("Failed", GlassInk.red)
        case .off: ("Off", GlassInk.slate)
        }
    }
}

/// Counts per mounted room, by memory type. Counts only, no titles. Sealed rooms never appear (Q2). Eight blue shades are
/// not tellable apart, so the bar shows the shape, the row names its biggest type, and hover and VoiceOver give the lot.
private struct RecordsPerRoom: View {
    let model: BrainModel
    var body: some View {
        let rows = model.recordsPerRoom
        let top = Double(rows.map(\.counts.records).max() ?? 1)
        BrainCard("Records per room", sub: "Rooms open on this Mac. Counts only, no titles.") {
            VStack(spacing: Space.s2) {
                ForEach(rows, id: \.room.id) { row in
                    let all = BrainWords.breakdown(row.counts.byType)
                    HStack(spacing: Space.s3) {
                        Text(row.room.name).frame(width: Space.s8 * 4, alignment: .leading).lineLimit(1)
                        TypeBar(shares: row.counts.byType, total: top)
                        Text(BrainWords.mostly(row.counts.byType)).font(.system(size: MacTextSize.meta))
                            .foregroundStyle(GlassInk.secondary).lineLimit(1)
                            .frame(width: Space.s8 * 3.5, alignment: .leading)
                        Text(row.counts.records.formatted()).monospacedDigit()
                            .frame(width: Space.s8 * 2, alignment: .trailing)
                    }
                    .help("\(row.room.name), \(row.counts.records.formatted()): \(all)")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.room.name), \(row.counts.records.formatted()): \(all)")
                }
            }
            Text("The darkest part is the most common kind. Hover a row for the full breakdown.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).padding(.top, Space.s1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct TypeBar: View {
    let shares: [TypeShare]
    let total: Double
    static func opacity(_ i: Int) -> Double { max(0.35, 1 - Double(i) * 0.09) }
    var body: some View {
        GeometryReader { g in
            let sum = Double(max(shares.reduce(0) { $0 + $1.count }, 1))
            let width = g.size.width * (sum / max(total, 1))
            HStack(spacing: 1) {
                ForEach(Array(shares.enumerated()), id: \.offset) { i, s in
                    Rectangle().fill(GlassInk.blue.opacity(Self.opacity(i)))
                        .frame(width: max(width * Double(s.count) / sum - 1, 0))
                }
            }
            .clipShape(coreShape(3)).frame(width: width, alignment: .leading)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Local search p95 over the last days as bars against the target line. The latest is lit and printed in words. The
/// target is named above its line on a well, and the left edge carries the values.
private struct SpeedChart: View {
    let speed: [Double]
    let target: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    private let axis = Space.s8 * 1.75
    var body: some View {
        let top = max(speed.max() ?? 0, target) * 1.25
        BrainCard(
            "Local search speed",
            sub:
                "Slowest 5 in 100 searches, last \(speed.count) days, against the \(coreUnit("\(Int(target))", "ms")) target."
        ) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(coreUnit("\(Int(speed.last ?? 0))", "ms")).font(
                    .system(size: MacTextSize.large, weight: .semibold)
                )
                .monospacedDigit()
                Text("today").foregroundStyle(GlassInk.secondary)
            }
            GeometryReader { g in
                let y = g.size.height * (1 - target / top)
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: Space.s1) {
                        ForEach(Array(speed.enumerated()), id: \.offset) { i, v in
                            coreShape(3).fill(GlassInk.blue.opacity(i == speed.count - 1 ? 1 : 0.55))
                                .frame(height: g.size.height * (v / top) * (shown || reduce ? 1 : 0.02))
                        }
                    }
                    .padding(.leading, axis).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    Path { p in
                        p.move(to: CGPoint(x: axis, y: y))
                        p.addLine(to: CGPoint(x: g.size.width, y: y))
                    }
                    .stroke(GlassInk.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    axisLabel(coreUnit("\(Int(top))", "ms")).offset(y: 0)
                    axisLabel(coreUnit("\(Int(target))", "ms")).offset(y: y - Space.s2)
                    axisLabel("0").offset(y: g.size.height - Space.s3)
                    Text("Target \(coreUnit("\(Int(target))", "ms"))").font(.system(size: MacTextSize.meta))
                        .foregroundStyle(GlassInk.primary).padding(.horizontal, Space.s2)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                        .frame(maxWidth: .infinity, alignment: .trailing).offset(y: y - Space.s4 - 2)
                }
            }
            .frame(height: Space.s8 * 4)
            HStack {
                Text("\(speed.count) days ago")
                Spacer()
                Text("Today")
            }
            .padding(.leading, axis).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { withAnimation(Motion.calm(Motion.out(Motion.reveal), reduce)) { shown = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Local search \(Int(speed.last ?? 0)) milliseconds today, target \(Int(target)), highest in \(speed.count) days \(Int(speed.max() ?? 0))"
        )
    }
    private func axisLabel(_ t: String) -> some View {
        Text(t).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).monospacedDigit()
    }
}

private struct Facts: View {
    let facts: BrainFacts
    var body: some View {
        BrainCard("Also worth knowing") {
            // Two pairs per row, each label beside its value, never a screen apart.
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                GridRow {
                    cell(0, "\(facts.staleShare)%")
                    cell(1, facts.recall)
                }
                GridRow {
                    cell(2, "\(facts.secretBlocks)")
                    cell(3, "\(facts.flaggedSources)")
                }
            }
        }
    }
    @ViewBuilder private func cell(_ i: Int, _ value: String) -> some View {
        let f = BrainWords.facts[i]
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(f.title).foregroundStyle(GlassInk.secondary)
            Text(value).font(.system(size: MacTextSize.body, weight: .semibold)).monospacedDigit()
        }
        .help(f.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(f.title): \(value). \(f.help)")
        .gridColumnAlignment(.leading)
    }
}
