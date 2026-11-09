import SwiftUI

extension MacTextSize {
    /// UserDefaults key for the text-size factor (Settings, Mac, Appearance, Text size).
    public static let scaleKey = "core.textScale"
    /// The smallest text the app draws, whatever the factor.
    public static let floor: CGFloat = 10

    /// The factor from the setting: 1.0 when unset, kept between 0.8 and 2.
    public static var scale: Double {
        let v = UserDefaults.standard.object(forKey: scaleKey) as? Double ?? 1
        return min(max(v, 0.8), 2)
    }

    /// A token size with the factor applied and the 10 pt floor. At 100 % the size is untouched; a size already under the
    /// floor (a tiny key cap) is never grown by the floor, only by a factor above 1.
    public static func scaled(_ size: CGFloat, by factor: Double? = nil) -> CGFloat {
        let f = factor.map { min(max($0, 0.8), 2) } ?? scale
        if f == 1 { return size }
        return max(min(size, floor), (size * f).rounded())
    }
}

private struct TextScaleKey: EnvironmentKey {
    static var defaultValue: Double { MacTextSize.scale }
}

extension EnvironmentValues {
    /// The text-size factor; `coreTheme()` keeps it in step with the setting so text redraws when it changes.
    public var coreTextScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct CoreFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.coreTextScale) private var scale
    func body(content: Content) -> some View {
        content.coreFont(size: MacTextSize.scaled(size, by: scale), weight: weight, design: design)
    }
}

extension View {
    /// The one way to set a point size: the size times the Text size setting, with the 10 pt floor.
    public func coreFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default)
        -> some View
    {
        modifier(CoreFontModifier(size: size, weight: weight, design: design))
    }
}

extension Font {
    /// For a `Font` value that cannot be a modifier (an argument). Pass the scale from `@Environment(\.coreTextScale)`.
    public static func core(
        size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, scale: Double
    ) -> Font {
        .system(size: MacTextSize.scaled(size, by: scale), weight: weight, design: design)
    }
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
                Image(systemName: symbol).coreFont(size: MacTextSize.meta - 1).accessibilityHidden(true)
            }
            Text(text).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1)
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

/// A number with a fixed count of decimals, in the reader's own separators.
public func coreDecimal(_ value: Double, _ digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

/// Seconds as `m:ss` (or `h:mm:ss` from an hour), in the reader's own digits.
public func coreClock(_ seconds: Int) -> String {
    let d = Duration.seconds(max(0, seconds))
    return seconds >= 3600
        ? d.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1)))
        : d.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
}
