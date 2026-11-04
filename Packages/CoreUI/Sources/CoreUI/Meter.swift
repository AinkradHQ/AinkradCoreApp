import SwiftUI

/// A time or quantity left as a bar (`fx.meter`): a rounded track and a fill that shrinks. Blue, or amber when it is nearly out;
/// pair it with words, the bar alone never says which. Reduce Motion: the fill still changes, without the glide.
public struct CoreMeter: View {
    let value: Double
    let low: Bool
    let height: CGFloat
    let label: String
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// `value` is 0...1.
    public init(_ value: Double, low: Bool = false, height: CGFloat = Space.s1, label: String) {
        self.value = min(max(value, 0), 1)
        self.low = low
        self.height = height
        self.label = label
    }

    public var body: some View {
        coreShape(height / 2).fill(palette.track)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    coreShape(height / 2).fill(low ? palette.warning : palette.primary)
                        .frame(width: geo.size.width * value)
                        .animation(reduce ? nil : .linear(duration: 1), value: value)
                }
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}
