import CoreUI
import SwiftUI

/// Items left to right, wrapping to a new line: the chips of a setup page.
struct SetupFlow: Layout {
    var spacing = Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 600, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return (CGSize(width: width, height: y + row), frames)
    }
}

/// A group of tap-to-toggle chips: any number may be on.
struct SetupChips: View {
    let options: [String]
    @Binding var chosen: Set<String>
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        SetupFlow {
            ForEach(options, id: \.self) { o in
                let on = chosen.contains(o)
                Button {
                    if on { chosen.remove(o) } else { chosen.insert(o) }
                } label: {
                    HStack(spacing: Space.s1) {
                        if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                        Text(o).coreFont(size: MacTextSize.body, weight: .medium)
                    }
                    .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
                    .foregroundStyle(on ? palette.text : palette.text2)
                    .background(on ? palette.navActive : GlassInk.well, in: coreShape(Radius.control))
                    .contentShape(coreShape(Radius.control))
                }
                .buttonStyle(CoreQuietPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(reduce ? nil : Motion.out(Motion.hover), value: chosen)
    }
}

/// A big choice: symbol on a tile, a title and one line. Selected ones carry a check.
struct SetupOption: View {
    @Environment(\.coreAccent) private var paneAccent
    let symbol: String
    let title: String
    var sub: String = ""
    let on: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s2) {
                IconTile(symbol, hue: on ? GlassInk.accent(paneAccent) : GlassInk.slate, size: 40)
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                if !sub.isEmpty {
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).multilineTextAlignment(
                        .center
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.s4).padding(.horizontal, Space.s2)
            .coreWell(active: on || hover)
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(
                            GlassInk.accent(paneAccent), in: coreShape(Radius.chip)
                        )
                        .padding(Space.s2)
                }
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle())
        .onHover { hover = $0 }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The seven bars at the top of setup: Welcome, Core, You, AI, Look, Runner, Ready. Bars up to `at` are lit.
struct SetupBars: View {
    let at: Int
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(0..<7, id: \.self) { i in
                coreShape(Radius.chip / 3).fill(i <= at ? palette.primary : palette.track)
                    .frame(width: Space.s8 + Space.s3, height: Space.s1)
            }
        }
        .accessibilityElement().accessibilityLabel("Step \(min(at, 6)) of 6")
    }
}

/// A page's title, one line under it, and its content, in the one rhythm every setup page uses.
struct SetupPage<Content: View>: View {
    let meta: String?
    let title: String
    let sub: String
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let meta { Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
                Text(title).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
                if !sub.isEmpty {
                    Text(sub).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small caption over a group of choices.
struct SetupGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
            content
        }
    }
}
