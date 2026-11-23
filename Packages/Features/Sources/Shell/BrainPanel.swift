import CoreUI
import SwiftUI

/// The Brain dropdown (Designs/core/0-10/review/brain, dropdown): how it is, how much it knows and from how many places,
/// the four areas with what they took in today and their last two weeks, the live step while it learns, what it learned
/// today with Forget All, what waits to be checked, and Import / Open Brain. An older Core gets the counts it has.
struct BrainPanel: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let glance = shell.brainGlance?()
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let g = glance {
                DropHead(symbol: "brain", title: "Brain", meta: meta(g), badge: badge(g))
                if let k = g.known, !g.tiles.isEmpty {
                    (Text(k.formatted()).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        + Text(" things known\(g.places.map { ", from \($0) \($0 == 1 ? "place" : "places")" } ?? "")")
                        .font(.system(size: MacTextSize.body)).foregroundColor(palette.text2))
                        .contentTransition(.numericText())
                }
                if let i = g.importing { importing(i) }
                if g.tiles.isEmpty {
                    if g.doing != nil || g.flowStep != nil { doing(g) }
                    if !g.stats.isEmpty { HStack(spacing: Space.s2) { ForEach(g.stats) { stat($0) } } }
                } else {
                    Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
                        GridRow { ForEach(g.tiles.prefix(2)) { tile($0) } }
                        GridRow { ForEach(g.tiles.dropFirst(2).prefix(2)) { tile($0) } }
                    }
                    if g.doing != nil || g.flowStep != nil { doing(g) }
                }
                if g.learned > 0 { learned(g) }
                if g.toCheck > 0 { toCheck(g.toCheck) }
            } else {
                DropHead(
                    symbol: "brain", title: "Brain", meta: "Not ready yet", badge: DropBadge("Waiting", tone: .queue))
            }
            HStack(spacing: Space.s2) {
                if glance != nil, glance?.importing == nil, shell.brainOpenImport != nil {
                    Button {
                        openImport()
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .help("Import past sessions and notes")
                    .accessibilityIdentifier("brain-drop-import")
                }
                Spacer(minLength: 0)
                Button("Open Brain") { open(nil) }.buttonStyle(CoreButtonStyle(.prominent))
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 12)
        .corePanel(radius: Radius.pane, padding: 0, part: .popups)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Brain")
        .task { await shell.brainRefresh?() }
    }

    private func meta(_ g: BrainGlance) -> String {
        if g.flowStep != nil || g.doing != nil {
            return g.learningFrom.map { "Learning from \($0)" } ?? "Learning"
        }
        guard !g.tiles.isEmpty else { return g.status }
        return g.lastLearned.map { "\(g.status) · last learned \($0)" } ?? g.status
    }

    private func badge(_ g: BrainGlance) -> DropBadge {
        if !g.healthy { return DropBadge("Needs a look", tone: .warn) }
        return g.flowStep != nil ? DropBadge("Learning", tone: .done) : DropBadge("Healthy", tone: .done)
    }

    /// One area: its name and what it took in today, the count, and its last two weeks (or how it fills in).
    private func tile(_ t: BrainGlance.Tile) -> some View {
        Button {
            open(t.area)
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s1 + 2) {
                    Image(systemName: t.symbol).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .frame(width: Space.s5, height: Space.s5)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                        .accessibilityHidden(true)
                    Text(t.label).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2).lineLimit(1)
                    Spacer(minLength: 0)
                    if t.today > 0 {
                        Text("+\(t.today.formatted())").coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(palette.success).monospacedDigit()
                    }
                }
                Text(t.count > 0 ? t.count.formatted() : "Nothing yet")
                    .coreFont(size: t.count > 0 ? MacTextSize.large : MacTextSize.body, weight: .semibold)
                    .monospacedDigit().contentTransition(.numericText())
                    .frame(minHeight: Space.s6, alignment: .leading)
                if t.count == 0 {
                    Text("Learns as you work").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                } else if let s = t.series, s.count >= 2 {
                    bars(s)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .help("Open \(t.label) in Brain")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(t.label) in Brain")
    }

    private func bars(_ s: [Int]) -> some View {
        let top = Double(max(s.max() ?? 1, 1))
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(s.enumerated()), id: \.offset) { i, v in
                coreShape(1.5)
                    .fill(GlassInk.accent(accent).opacity(i == s.count - 1 ? 1 : 0.55))
                    .frame(height: max(2, Space.s4 * CGFloat(Double(v) / top)))
            }
        }
        .frame(height: Space.s4, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private static let steps: [(String, String)] = [
        ("Reading", "eye"), ("Understanding", "sparkles"), ("Remembering", "cylinder"),
    ]

    /// While it learns: what it does now, and the three steps with the one it is on.
    private func doing(_ g: BrainGlance) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let doing = g.doing {
                HStack(spacing: Space.s2) {
                    coreShape(2).fill(palette.success).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(doing).coreFont(size: MacTextSize.body, weight: .semibold)
                }
            }
            if let now = g.flowStep {
                HStack(alignment: .top, spacing: Space.s2) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Label(s.0, systemImage: i < now ? "checkmark" : s.1)
                                .coreFont(size: MacTextSize.meta, weight: i == now ? .semibold : .regular)
                                .foregroundStyle(i > now ? palette.text2 : palette.text)
                            if i == now, g.progress == nil {
                                CoreBusyBar()
                            } else {
                                CoreMeter(i < now ? 1 : i == now ? g.progress ?? 0 : 0, label: s.0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(s.0), \(i < now ? "done" : i == now ? "now" : "next")")
                    }
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: g.flowStep)
    }

    /// An import under way: its step, how far, and the way back into its panel.
    private func importing(_ i: BrainGlance.Importing) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Importing… \(i.step)").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.text2)
                Spacer(minLength: Space.s2)
                if let d = i.detail {
                    Text(d).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                }
            }
            Text(i.line).coreFont(size: MacTextSize.headline, weight: .semibold)
            if let p = i.progress { CoreMeter(p, label: "Import progress") } else { CoreBusyBar() }
            HStack {
                Spacer(minLength: 0)
                Button("Open Import") { openImport() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .accessibilityIdentifier("brain-drop-open-import")
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-drop-importing")
    }

    private func learned(_ g: BrainGlance) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "sparkles").foregroundStyle(palette.text2)
                .frame(width: Space.s6, height: Space.s6).background(GlassInk.well, in: coreShape(Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("+\(g.learned.formatted()) learned today").coreFont(size: MacTextSize.body, weight: .semibold)
                if let l = g.latest {
                    Text("Latest: \(l)").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(2)
                }
            }
            Spacer(minLength: Space.s2)
            Button("Forget All") { shell.brainUndoLearned?() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Forget everything learned today. It is kept in the archive, and Undo brings it back.")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    private func toCheck(_ n: Int) -> some View {
        Button {
            open("inbox")
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "tray").foregroundStyle(palette.primary)
                    .frame(width: Space.s6, height: Space.s6)
                    .background(GlassInk.accent(accent).opacity(0.2), in: coreShape(Radius.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(n) \(n == 1 ? "thing" : "things") to check").coreFont(
                        size: MacTextSize.body, weight: .semibold)
                    Text("About \(n * 10) seconds of your time").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right").foregroundStyle(palette.text2).accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
            .background(GlassInk.accent(accent).opacity(0.14), in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .help("Open To check")
        .accessibilityIdentifier("brain-drop-check")
    }

    private func stat(_ s: BrainGlance.Stat) -> some View {
        Button {
            open(s.area)
        } label: {
            DropStat("\(s.count)", s.label)
        }
        .buttonStyle(.plain)
        .accessibilityHint(s.area == nil ? "" : "Opens \(s.label) in Brain")
    }

    private func openImport() {
        shell.topMenu = nil
        shell.brainOpenImport?()
    }

    private func open(_ area: String?) {
        shell.topMenu = nil
        if let area, let go = shell.brainOpenArea { go(area) } else { shell.launcher.entry("brain")?.run() }
    }
}
