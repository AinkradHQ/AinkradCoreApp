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
                .coreGlassField(fallback: palette.glassCard)
                .overlay {
                    coreShape(Radius.control).strokeBorder(
                        error == nil ? palette.glassCardEdge : palette.tone(.fail).ink, lineWidth: 1)
                }
                .coreFocusRing(focused || forced == .focused, radius: Radius.control, palette: palette)
                .coreDimWhenDisabled(enabled)
                .accessibilityLabel(label)
                .onAppear { if autofocus { focused = true } }
            if let error { CoreFieldError(error) }
        }
    }
}
