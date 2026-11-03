import CoreUI
import SwiftUI

/// The harness as a rounded tile: blue, with its symbol. (A tile, not a circle: rounded rectangles only.)
struct AgentMark: View {
    let harness: String
    var size: CGFloat = MacSize.controlLg
    @Environment(\.corePalette) private var palette
    var body: some View {
        Image(systemName: AgentsModel.harnessSymbol(harness))
            .font(.system(size: MacTextSize.title, weight: .medium))
            .foregroundStyle(palette.btnInk)
            .frame(width: size, height: size)
            .background(harness == "claude" ? palette.btnPrimary : palette.navActive, in: coreShape(Radius.control))
            .accessibilityHidden(true)
    }
}

/// An outcome in place: a symbol, the words, and the reason. Never colour alone.
struct NoticeBanner: View {
    let notice: InlineNotice
    @Environment(\.corePalette) private var palette

    var body: some View {
        let c = palette.tone(notice.tone)
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: notice.symbol).foregroundStyle(c.ink).frame(width: Space.s4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(notice.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                if !notice.detail.isEmpty {
                    Text(notice.detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(c.fill, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }
}

/// A progress bar (the system uses bars, never spinners). `value` is 0 to 1.
struct MeterBar: View {
    let value: Double
    var tone: Tone = .run
    @Environment(\.corePalette) private var palette
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(Radius.chip / 2).fill(palette.track)
                coreShape(Radius.chip / 2).fill(palette.tone(tone).ink)
                    .frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}

/// A loading row: bars that rest at a low light, and breathe while Reduce Motion is off.
struct SkeletonRows: View {
    var count = 6
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var dim = false
    var body: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(alignment: .top, spacing: Space.s3) {
                    coreShape(Radius.control).fill(palette.uDim).frame(
                        width: MacSize.controlLg, height: MacSize.controlLg)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        coreShape(Radius.chip).fill(palette.uDim).frame(width: 180, height: Space.s3)
                        coreShape(Radius.chip).fill(palette.uDim).frame(width: 110, height: Space.s3 - 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .background(palette.glassCard, in: coreShape(Radius.row))
            }
        }
        .opacity(reduce ? 0.7 : dim ? 0.5 : 0.9)
        .animation(reduce ? nil : .easeInOut(duration: Motion.tick).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading sessions")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A button that is a row: the card tint at rest, lighter on hover, the nav colour when selected, the one focus ring.
struct AgentRowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, selected: selected)
    }
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.corePalette) private var palette
        @Environment(\.isFocused) private var focused
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(
                    selected
                        ? palette.navActive
                        : hovering || configuration.isPressed ? palette.rowHover : palette.glassCard,
                    in: coreShape(Radius.row)
                )
                .overlay { if selected { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
                .coreFocusRing(focused, radius: Radius.row, palette: palette)
                .animation(Motion.out(Motion.hover), value: hovering)
                .onHover { hovering = $0 }
                .focusEffectDisabled()
        }
    }
}

extension View {
    /// The head of a pane section: a label that screen readers announce as a heading.
    func agentHeading() -> some View { accessibilityAddTraits(.isHeader) }
}
