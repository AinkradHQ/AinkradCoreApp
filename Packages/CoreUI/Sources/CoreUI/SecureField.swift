import SwiftUI

/// A one-line field for a value that goes in and never comes back: dots while typing, no show, no copy. Same well, label, focus
/// ring and error line as `CoreTextField`. The text lives only in the binding the caller gives it.
public struct CoreSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let autofocus: Bool
    let onSubmit: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private var textScale: Double { TextSizePrefs.shared.scale }
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool

    public init(
        _ label: String, placeholder: String, text: Binding<String>, error: String? = nil, autofocus: Bool = false,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreFieldLabel(label)
            SecureField(palette.isDay ? "" : placeholder, text: $text)
                .textFieldStyle(.plain)
                .coreFont(size: MacTextSize.body)
                .coreDayPlaceholder(
                    placeholder, empty: text.isEmpty, font: .core(size: MacTextSize.body, scale: textScale)
                )
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: MacSize.controlLg)
                .coreFieldSurface(focused: focused || forced == .focused, error: error != nil)
                .coreDimWhenDisabled(enabled)
                .accessibilityLabel(label)
                .onAppear { if autofocus { focused = true } }
            if let error { CoreFieldError(error) }
        }
    }
}
