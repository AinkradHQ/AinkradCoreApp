import AppKit
import CoreUI
import SwiftUI

/// The harness as a rounded tile: blue, with its symbol. (A tile, not a circle: rounded rectangles only.)
struct AgentMark: View {
    let harness: String
    var size: CGFloat = MacSize.controlLg
    var body: some View {
        Image(systemName: AgentsModel.harnessSymbol(harness))
            .font(.system(size: MacTextSize.title, weight: .medium))
            .foregroundStyle(GlassInk.primary)
            .frame(width: size, height: size)
            .background(GlassInk.blue.opacity(0.6), in: coreShape(Radius.control))
            .accessibilityHidden(true)
    }
}

/// An outcome in place: a symbol, the words, and the reason. Never colour alone.
struct NoticeBanner: View {
    let notice: InlineNotice
    var body: some View {
        CoreNotice(symbol: notice.symbol, title: notice.title, text: notice.detail, tone: notice.tone)
    }
}

/// A loading row: bars at rest, fading in once. Reduce Motion keeps the fade.
struct SkeletonRows: View {
    var count = 6
    @Environment(\.corePalette) private var palette
    @State private var shown = false
    var body: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(alignment: .top, spacing: Space.s3) {
                    coreShape(Radius.control).fill(palette.uDim).frame(
                        width: MacSize.controlLg, height: MacSize.controlLg)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        coreShape(Radius.chip).fill(palette.uDim).frame(width: Space.s8 * 6, height: Space.s3)
                        coreShape(Radius.chip).fill(palette.uDim).frame(width: Space.s8 * 3, height: Space.s3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .background(palette.glassCard, in: coreShape(Radius.row))
            }
        }
        .opacity(shown ? 0.8 : 0)
        .animation(Motion.out(Motion.ui), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading sessions")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A row that is a button: the well at rest, lighter on hover, a blue edge when selected. No focus ring, no resize.
struct AgentRowButton<Label: View>: View {
    var selected = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .background(
                selected ? GlassInk.blue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    selected ? GlassInk.blue.opacity(0.5) : GlassInk.wellEdge, lineWidth: 1)
            }
            .animation(Motion.out(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// The head of a pane section: a label that screen readers announce as a heading.
    func agentHeading() -> some View { accessibilityAddTraits(.isHeader) }
}

extension View {
    /// Copy in the context menu. (Not `.textSelection`: with it on many rows, VoiceOver and the accessibility tree recurse until the
    /// app overflows its stack, seen on macOS 27 with two session panes open.)
    func agentCopyMenu(_ text: String) -> some View {
        contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

/// A moving bar for "working, length unknown". Reduce Motion: the bar rests in the middle.
/// (The same bar as the Terminals module's; both belong in CoreUI, a proposal in the lane report.)
struct BusyBar: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / (Motion.tick * 1.5)
            let phase = reduce ? 0.5 : t - t.rounded(.down)
            GeometryReader { geo in
                let seg = geo.size.width * 0.3
                ZStack(alignment: .leading) {
                    coreShape(Space.s1 / 2).fill(palette.track)
                    coreShape(Space.s1 / 2).fill(palette.primary).frame(width: seg)
                        .offset(x: (geo.size.width - seg) * phase)  // grid: ok progress motion, not layout
                }
                .clipShape(coreShape(Space.s1 / 2))
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}
