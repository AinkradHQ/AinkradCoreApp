import CoreUI
import SwiftUI

// Pieces the widgets share. Ink comes from CoreUI's GlassInk; the soft shadow in DeskWidget keeps it readable on the sky.

/// A number that rolls up from zero when it first shows and rolls to every new value after.
struct RollingNumber: View {
    let value: Double
    var format: (Double) -> String = { String(Int($0)) }
    var size: CGFloat
    var design: Font.Design = .default
    var ink: Color?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0
    var body: some View {
        Text(format(shown)).font(.system(size: size, weight: .semibold, design: design)).monospacedDigit()
            .foregroundStyle(ink ?? palette.text)
            .contentTransition(.numericText(value: shown))
            .lineLimit(1).minimumScaleFactor(0.6)
            .onAppear { roll() }
            .onChange(of: value) { _, _ in roll() }
            .accessibilityLabel(format(value))
    }
    private func roll() {
        withAnimation(Motion.out(reduce ? Motion.hover : Motion.move)) { shown = value }
    }
}

/// The prototype's status mark: a small rounded square (never a circle). The word beside it says the same thing.
/// A live one (a session or connection actually running) breathes: opacity only, so it stays under Reduce Motion too.
public struct StatusDot: View {
    let color: Color
    var live = false
    @State private var dim = false
    public init(color: Color, live: Bool = false) {
        self.color = color
        self.live = live
    }
    public var body: some View {
        coreShape(2).fill(color).frame(width: Space.s2, height: Space.s2)
            .opacity(live && dim ? 0.45 : 1)
            .animation(live ? Motion.out(Motion.tick).repeatForever(autoreverses: true) : nil, value: dim)
            .onAppear { if live { dim = true } }
            .accessibilityHidden(true)
    }
}

/// `.wd-card`: a tappable neutral card (the Needs you row).
struct WidgetCard: View {
    let title: String
    let sub: String
    var compact = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                StatusDot(color: palette.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .lineLimit(compact ? 1 : 3).multilineTextAlignment(.leading)
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.row))
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
    }
}
