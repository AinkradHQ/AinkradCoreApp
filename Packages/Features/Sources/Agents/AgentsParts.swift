import AppKit
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
    var body: some View {
        CoreNotice(symbol: notice.symbol, title: notice.title, text: notice.detail, tone: notice.tone)
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

/// A row that is a button: the card tint at rest, lighter on hover, the nav colour when selected, and the one focus ring, drawn
/// from this row's own focus (a row never shows the ring because another control has it).
struct AgentRowButton<Label: View>: View {
    let id: String
    var focus: FocusState<String?>.Binding
    var selected = false
    var waiting = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .focused(focus, equals: id)
            .focusEffectDisabled()
            .background(
                selected ? palette.navActive : hovering ? palette.rowHover : palette.glassCard,
                in: coreShape(Radius.row)
            )
            .overlay {
                // A session that waits on you keeps the edge the selected row has, so it stands out in a long list.
                if selected || waiting { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
            }
            .coreFocusRing(focus.wrappedValue == id, radius: Radius.row, palette: palette)
            .animation(Motion.out(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// The head of a pane section: a label that screen readers announce as a heading.
    func agentHeading() -> some View { accessibilityAddTraits(.isHeader) }
}

/// A shortcut beside a button's words, on one line (the shared keycap wraps a two-key shortcut in a narrow button).
struct AgentKeyHint: View {
    let keys: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(keys).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
            .fixedSize().padding(.horizontal, Space.s1).background(palette.uDim, in: coreShape(Radius.chip / 2))
            .accessibilityHidden(true)
    }
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
