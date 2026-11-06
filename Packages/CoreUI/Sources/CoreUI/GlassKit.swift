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
    public static let blue = Color(red: 96 / 255, green: 165 / 255, blue: 255 / 255)
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
                in: coreShape(size > 40 ? Radius.cardMac : Radius.control)
            )
            .overlay {
                coreShape(size > 40 ? Radius.cardMac : Radius.control).strokeBorder(
                    .white.opacity(0.25), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

extension IconTile where Trigger == Int {
    public init(_ symbol: String, hue: Color, size: CGFloat = 32) { self.init(symbol, hue: hue, size: size, bounce: 0) }
}

/// A titled glass card: icon tile, title and one line, an optional action at the top right, then the content in a soft
/// white well. Rises in when shown.
public struct GlassSection<Content: View, Accessory: View>: View {
    let title: String
    let sub: String?
    let symbol: String
    let hue: Color
    let index: Int
    let accessory: Accessory
    let content: Content
    @State private var shown = false
    public init(
        _ title: String, sub: String? = nil, symbol: String, hue: Color, index: Int = 0,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.hue = hue
        self.index = index
        self.accessory = accessory()
        self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(symbol, hue: hue, bounce: shown)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let sub { Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary) }
                }
                Spacer(minLength: Space.s3)
                accessory
            }
            content
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .coreRise(shown, index)
        .onAppear { shown = true }
    }
}

extension GlassSection where Accessory == EmptyView {
    public init(
        _ title: String, sub: String? = nil, symbol: String, hue: Color, index: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, sub: sub, symbol: symbol, hue: hue, index: index, accessory: { EmptyView() }, content: content)
    }
}

/// A section's action: an icon and a word.
public struct SectionAction: View {
    let title: String
    let symbol: String
    let danger: Bool
    let action: () -> Void
    public init(_ title: String, symbol: String, danger: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.danger = danger
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
            }
        }
        .buttonStyle(CoreButtonStyle(danger ? .danger : .secondary))
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
            VStack(alignment: .leading, spacing: 0) {
                Text(name.capitalized).font(.system(size: MacTextSize.body, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: MacTextSize.title))
                .foregroundStyle(on ? hue : GlassInk.track).contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? hue.opacity(0.16) : GlassInk.well, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(on ? hue.opacity(0.5) : GlassInk.wellEdge, lineWidth: 1) }
        .opacity(on ? 1 : 0.75)
        .animation(Motion.out(Motion.ui), value: on)
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
                (reduce ? Motion.out(Motion.hover) : Motion.out(Motion.move))
                    .delay(Double(min(index, 10)) * Motion.stagger),
                value: shown)
    }
}

/// A scroll view with a glass scroll bar: a thin white thumb at the very right edge that fades in while scrolling and
/// brightens under the pointer, instead of the grey system bar (Ahmed, 2026-11-05). macOS 15 and later; below that the
/// system bar stays.
public struct GlassScroll<Content: View>: View {
    let content: Content
    @State private var metrics = ScrollMetrics()
    @State private var active = false
    @State private var hovering = false
    @State private var fade: Task<Void, Never>?
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        if #available(macOS 15, iOS 18, *) {
            ScrollView { content }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: ScrollMetrics.self) { g in
                    ScrollMetrics(
                        offset: g.contentOffset.y, content: g.contentSize.height, visible: g.containerSize.height)
                } action: { _, new in
                    metrics = new
                    wake()
                }
                .overlay(alignment: .topTrailing) { thumb }
        } else {
            ScrollView { content }
        }
    }

    @ViewBuilder private var thumb: some View {
        if metrics.content > metrics.visible + 1 {
            let ratio = metrics.visible / metrics.content
            let height = max(36, metrics.visible * ratio)
            let travel = metrics.visible - height
            let progress = min(max(metrics.offset / (metrics.content - metrics.visible), 0), 1)
            coreShape(2)
                .fill(.white.opacity(hovering ? 0.55 : 0.38))
                .overlay { coreShape(2).strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .frame(width: 6, height: height)
                .offset(y: travel * progress)
                .padding(.trailing, 3)
                .opacity(active || hovering ? 1 : 0)
                .animation(Motion.out(Motion.ui), value: active)
                .animation(Motion.out(Motion.ui), value: hovering)
                .frame(width: 16, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .accessibilityHidden(true)
        }
    }

    private func wake() {
        active = true
        fade?.cancel()
        fade = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { active = false }
        }
    }
}

struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var visible: CGFloat = 0
}
