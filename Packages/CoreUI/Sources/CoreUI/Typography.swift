import SwiftUI

extension MacTextSize {
    /// UserDefaults key for the text-size factor. No Settings UI yet (lane L5 adds it).
    public static let scaleKey = "core.textScale"
    /// The smallest text the app draws, whatever the factor.
    public static let floor: CGFloat = 10

    /// The factor from the setting: 1.0 when unset, kept between 0.8 and 2.
    public static var scale: Double {
        let v = UserDefaults.standard.object(forKey: scaleKey) as? Double ?? 1
        return min(max(v, 0.8), 2)
    }

    /// A token size with the factor applied and the 10 pt floor. Call sites adopt it as the app lanes touch them.
    public static func scaled(_ size: CGFloat) -> CGFloat { max(floor, (size * scale).rounded()) }
}

/// A number and its unit joined by a no-break space, so a wrapped line never leaves "12" alone above "ms".
public func coreUnit(_ value: String, _ unit: String) -> String { "\(value)\u{00A0}\(unit)" }

/// A small label chip: one line, never truncated, at least `minWidth` wide. In a row it keeps its width while the title
/// beside it shrinks (higher layout priority).
public struct CoreChip: View {
    let text: String
    let symbol: String?
    let minWidth: CGFloat
    @Environment(\.corePalette) private var palette
    public init(_ text: String, symbol: String? = nil, minWidth: CGFloat = Space.s8 * 2) {
        self.text = text
        self.symbol = symbol
        self.minWidth = minWidth
    }
    public var body: some View {
        HStack(spacing: Space.s1) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: MacTextSize.meta - 1)).accessibilityHidden(true)
            }
            Text(text).font(.system(size: MacTextSize.meta, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, Space.s2)
        .frame(minWidth: minWidth, minHeight: MacSize.chip)
        .background(GlassInk.well, in: coreShape(Radius.chip))
        .overlay { coreShape(Radius.chip).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .fixedSize()
        .layoutPriority(2)
    }
}
