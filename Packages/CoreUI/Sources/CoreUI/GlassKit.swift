import SwiftUI

/// The one visual language for content on Liquid Glass (Ahmed, 2026-11-05: glassy, visual, animated, readable, consistent):
/// white ink, soft white wells for cards, gradient icon tiles in a hue per subject, vivid status colours.
public enum GlassInk {
    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.72)
    public static let track = Color.white.opacity(0.24)
    public static let well = Color.white.opacity(0.08)
    public static let wellHover = Color.white.opacity(0.13)
    public static let wellEdge = Color.white.opacity(0.14)
    public static let blue = Color(red: 0.25, green: 0.6, blue: 1)
    public static let green = Color(red: 0.2, green: 0.85, blue: 0.45)
    public static let orange = Color(red: 1, green: 0.62, blue: 0.1)
    public static let red = Color(red: 1, green: 0.38, blue: 0.4)
    public static let violet = Color(red: 0.62, green: 0.45, blue: 1)
    public static let slate = Color(red: 0.55, green: 0.6, blue: 0.7)
}

/// A white glyph on a gradient tile in a subject's hue. It bounces when `bounce` changes.
public struct IconTile<Trigger: Equatable>: View {
    let symbol: String
    let hue: Color
    let size: CGFloat
    let bounce: Trigger
    public init(_ symbol: String, hue: Color, size: CGFloat = 32, bounce: Trigger) {
        self.symbol = symbol
        self.hue = hue
        self.size = size
        self.bounce = bounce
    }
    public var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
            .symbolEffect(.bounce, value: bounce)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [hue, hue.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                in: coreShape(size > 40 ? Radius.control + 4 : Radius.control)
            )
            .overlay {
                coreShape(size > 40 ? Radius.control + 4 : Radius.control).strokeBorder(
                    .white.opacity(0.25), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

extension IconTile where Trigger == Int {
    public init(_ symbol: String, hue: Color, size: CGFloat = 32) { self.init(symbol, hue: hue, size: size, bounce: 0) }
}

/// A titled glass card: icon tile, title and one line, then the content in a soft white well. Rises in when shown.
public struct GlassSection<Content: View>: View {
    let title: String
    let sub: String?
    let symbol: String
    let hue: Color
    let index: Int
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    public init(
        _ title: String, sub: String? = nil, symbol: String, hue: Color, index: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.hue = hue
        self.index = index
        self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(symbol, hue: hue, bounce: shown)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: MacTextSize.headline + 1, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let sub { Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary) }
                }
            }
            content
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .coreRise(shown, index)
        .onAppear { shown = true }
    }
}

/// A fact on one line: an icon, the name, and the value at the right (monospaced for identifiers).
public struct InfoRow<Trailing: View>: View {
    let symbol: String
    let key: String
    let value: String
    let mono: Bool
    let trailing: Trailing
    public init(
        _ symbol: String, _ key: String, _ value: String, mono: Bool = false, @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.key = key
        self.value = value
        self.mono = mono
        self.trailing = trailing()
    }
    public var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
                .frame(width: 20).accessibilityHidden(true)
            Text(key).foregroundStyle(GlassInk.secondary)
            Spacer(minLength: Space.s3)
            Text(value).font(.system(size: MacTextSize.body, weight: .medium, design: mono ? .monospaced : .default))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            trailing
        }
        .font(.system(size: MacTextSize.body))
        .frame(minHeight: MacSize.controlMd)
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Trailing == EmptyView {
    public init(_ symbol: String, _ key: String, _ value: String, mono: Bool = false) {
        self.init(symbol, key, value, mono: mono) { EmptyView() }
    }
}

/// One permission as a tile: icon, name and what it allows. Lit in its hue when held or chosen, dim when not.
public struct ScopeTile: View {
    let symbol: String
    let name: String
    let detail: String
    let hue: Color
    let on: Bool
    public init(symbol: String, name: String, detail: String, hue: Color, on: Bool) {
        self.symbol = symbol
        self.name = name
        self.detail = detail
        self.hue = hue
        self.on = on
    }
    public var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            IconTile(symbol, hue: on ? hue : GlassInk.slate.opacity(0.5), bounce: on)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.capitalized).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: MacTextSize.title))
                .foregroundStyle(on ? hue : GlassInk.track).contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? hue.opacity(0.16) : GlassInk.well, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(on ? hue.opacity(0.5) : GlassInk.wellEdge, lineWidth: 1) }
        .opacity(on ? 1 : 0.75)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: on)
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "on" : "off")
    }
}

extension View {
    /// Rises 10 pt and fades in, one after another by `index`; Reduce Motion fades only.
    public func coreRise(_ shown: Bool, _ index: Int) -> some View {
        modifier(RiseModifier(shown: shown, index: index))
    }
}

private struct RiseModifier: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || reduce ? 0 : 10)
            .animation(
                (reduce ? Animation.easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2))
                    .delay(Double(min(index, 10)) * 0.05),
                value: shown)
    }
}
