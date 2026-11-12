import CoreUI
import SwiftUI

// Pieces the widgets share. Ink comes from GlassInk; bars are CoreMeter. Reduce Motion keeps fades and colour only.

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
        Text(format(shown)).coreFont(size: size, weight: .semibold, design: design).monospacedDigit()
            .foregroundStyle(ink ?? palette.text)
            .contentTransition(.numericText(value: shown))
            .lineLimit(1).minimumScaleFactor(0.6)
            .onAppear { roll() }
            .onChange(of: value) { _, _ in roll() }
            .accessibilityLabel(format(value))
    }
    private func roll() {
        withAnimation(Motion.calm(Motion.out(Motion.reveal), reduce)) { shown = value }
    }
}

/// The prototype's status mark: a small rounded square (never a circle). The word beside it says the same thing.
/// A live one breathes (opacity, so it stays under Reduce Motion too).
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
            .coreLoop(live ? .easeInOut(duration: 1.1).repeatForever() : nil, value: dim)
            .onAppear { if live { dim = true } }
            .accessibilityHidden(true)
    }
}
