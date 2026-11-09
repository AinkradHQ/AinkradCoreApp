import CoreUI
import SwiftUI

/// The aside shared by Activity's feed and egress log: a title, a result chip, the rule that refused (if any), then the ids
/// and codes. Never content.
struct ActivityDetail: View {
    struct Rule {
        let name: String
        let code: String
        let text: String?
        let fix: String?
    }
    let title: String
    let chip: (String, Color)
    let sub: String
    let rule: Rule?
    let why: String?
    let lines: [DetailLine]
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s2)
                BrainChip(chip.0, chip.1)
            }
            Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            if let rule {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "shield").foregroundStyle(GlassInk.redInk).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BrainWords.blockedBy(rule.name)).fontWeight(.semibold)
                        if let t = rule.text { Text(t) }
                        if let f = rule.fix { Text(f).foregroundStyle(GlassInk.secondary) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: MacTextSize.meta))
                .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassInk.red.opacity(0.14), in: coreShape(Radius.control))
                .help("Rule code: \(rule.code)")
            } else if let why {
                Label(why, systemImage: "exclamationmark.triangle").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.redInk)
            }
            Grid(alignment: .topLeading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                ForEach(lines) { l in
                    GridRow {
                        Text(l.key).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
                        Text(l.value).font(.system(size: MacTextSize.meta, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: MacTextSize.meta)).padding(.top, Space.s1)
            Label(note, systemImage: "info.circle").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary).padding(.top, Space.s1)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-activity-detail")
    }
}

/// One feed or egress row: when, what, who and where, why it was refused, and the result as a chip.
struct ActivityRowView: View {
    let time: String
    let title: String
    let subtitle: String
    let why: String?
    let blockedBy: String?
    let help: String
    let chip: (String, Color)
    let selected: Bool
    let fresh: Bool
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: Space.s3) {
                Text(time).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .frame(width: Space.s8 * 2.6, alignment: .leading).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    if let why {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "shield").accessibilityHidden(true)
                            Text(why)
                            if let blockedBy { Text(blockedBy).fontWeight(.semibold) }
                        }
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.redInk).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BrainChip(chip.0, chip.1)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(
                fresh && !reduce
                    ? GlassInk.blue.opacity(0.2) : selected || hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    selected ? Color.white.opacity(0.28) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: hovering)
        .animation(.easeOut(duration: Motion.reveal), value: fresh)
        .help(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A short list of chips that wrap. Used for the rooms a pause names.
struct ChipFlow: Layout {
    var spacing: CGFloat = Space.s2
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(b.width, subviews)
        for (i, p) in r.points.enumerated() {
            subviews[i].place(at: CGPoint(x: b.minX + p.x, y: b.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var maxX: CGFloat = 0
        var pts: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            row = max(row, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + row), pts)
    }
}

/// The red Paused banner every Brain tab can show. One source: the model's paused rooms and `BrainWords`, so the words match
/// the Overview, the Home tile and the bell. On Checks it carries the way out; elsewhere it opens Checks.
struct PausedBanner: View {
    let model: BrainModel
    let full: Bool

    var body: some View {
        if model.health == .paused {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.octagon").font(.system(size: MacTextSize.large))
                    .foregroundStyle(GlassInk.redInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Paused").font(.system(size: MacTextSize.title, weight: .semibold))
                    Text(BrainWords.pausedWhy).foregroundStyle(GlassInk.secondary)
                    ChipFlow {
                        ForEach(model.pausedNames, id: \.self) { BrainChip($0, GlassInk.red) }
                    }
                    .padding(.top, Space.s1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(BrainWords.pausedLine(names: model.pausedNames))
                if full {
                    HStack(spacing: Space.s2) {
                        Button("Run leakage check again") { Task { await model.checks.run("leakage") } }
                            .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.checks.running["leakage"] != nil)
                        Button {
                            Task { await model.clearPaused() }
                        } label: {
                            Label("Clear", systemImage: "lock")
                        }
                        .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.busy != nil).help("Needs Touch ID")
                    }
                } else {
                    Button("Open Checks") { withAnimation(.smooth(duration: 0.3)) { model.tab = .checks } }
                        .buttonStyle(CoreButtonStyle(.secondary))
                }
            }
            .padding(Space.s4)
            .background(GlassInk.red.opacity(0.14), in: coreShape(Radius.cardMac))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("brain-paused")
        }
    }
}
