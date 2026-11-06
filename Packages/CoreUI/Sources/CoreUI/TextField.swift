import SwiftUI

/// The caption above a field: meta size, semibold, secondary ink.
public struct CoreFieldLabel: View {
    let text: String
    @Environment(\.corePalette) private var palette
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
    }
}

/// The error under a field: a warning symbol and the words, in the fail tone (never colour alone).
public struct CoreFieldError: View {
    let text: String
    @Environment(\.corePalette) private var palette
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.tone(.fail).ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A one-line text field in a rounded-rect well, with its label above and an error below.
/// States: rest, focus (the one ring), error, disabled.
public struct CoreTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let mono: Bool
    let big: Bool
    let suffix: String?
    let autofocus: Bool
    let onSubmit: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool

    public init(
        _ label: String, placeholder: String, text: Binding<String>, error: String? = nil, mono: Bool = false,
        big: Bool = false, suffix: String? = nil, autofocus: Bool = false, onSubmit: @escaping () -> Void = {}
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.mono = mono
        self.big = big
        self.suffix = suffix
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreFieldLabel(label)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(
                    mono
                        ? .system(size: big ? MacTextSize.large : MacTextSize.title, design: .monospaced)
                        : .system(size: MacTextSize.body)
                )
                .multilineTextAlignment(big ? .center : .leading)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: big ? MacSize.controlLg + Space.s3 : MacSize.controlLg)
                .overlay(alignment: .trailing) {
                    if let suffix {
                        Text(suffix).font(.system(size: MacTextSize.meta, design: .monospaced))
                            .foregroundStyle(palette.text2).padding(.trailing, Space.s3).allowsHitTesting(false)
                    }
                }
                .coreFieldSurface(focused: focused || forced == .focused, error: error != nil)
                .coreDimWhenDisabled(enabled)
                .accessibilityLabel(label)
                .onAppear { if autofocus { focused = true } }
            if let error { CoreFieldError(error) }
        }
    }
}

extension View {
    /// The one surface every form field sits on (Ahmed, 2026-11-06): a plain well at night, a light glass piece by day.
    /// Hover lightens it, focus lightens it more and lifts the edge; an error turns the edge the fail tone. No focus ring.
    public func coreFieldSurface(focused: Bool = false, error: Bool = false, radius: CGFloat = Radius.control)
        -> some View
    {
        modifier(FieldSurface(focused: focused, error: error, radius: radius))
    }
}

private struct FieldSurface: ViewModifier {
    let focused: Bool
    let error: Bool
    let radius: CGFloat
    @Environment(\.corePalette) private var palette
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    func body(content: Content) -> some View {
        let lit = hovering || forced == .hover
        content
            .background { fill(lit: lit) }
            .overlay { coreShape(radius).strokeBorder(edge, lineWidth: 1) }
            .shadow(
                color: palette.isDay
                    ? Color(red: 40 / 255, green: 80 / 255, blue: 140 / 255).opacity(focused ? 0.16 : 0.1)
                    : .clear,
                radius: focused ? 6 : 2, y: focused ? 3 : 1
            )
            .onHover { hovering = $0 }
            .coreAnimation(Motion.out(Motion.hover), value: lit)
            .coreAnimation(Motion.out(Motion.hover), value: focused)
    }

    @ViewBuilder private func fill(lit: Bool) -> some View {
        if palette.isDay {
            // Day: a white sheen, brighter at the top, like the glass controls.
            let top = focused ? 1.0 : lit ? 0.86 : 0.72
            let mid = focused ? 0.78 : lit ? 0.6 : 0.46
            coreShape(radius).fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(top), location: 0),
                        .init(color: .white.opacity(mid), location: 0.55),
                        .init(color: .white.opacity((top + mid) / 2), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
        } else {
            coreShape(radius).fill(focused || lit ? GlassInk.wellHover : GlassInk.well)
        }
    }

    private var edge: AnyShapeStyle {
        if error { return AnyShapeStyle(palette.tone(.fail).ink) }
        if palette.isDay {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.white.opacity(focused ? 1 : 0.95), .white.opacity(focused ? 0.9 : 0.5)],
                    startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(focused ? Color.white.opacity(0.3) : GlassInk.wellEdge)
    }
}
