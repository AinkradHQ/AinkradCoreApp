import SwiftUI

/// A text field of several lines: the same surface, label and error as `CoreTextField`. It grows with the text from
/// `minHeight` up to `maxHeight`, then scrolls. `label: nil` when the form names the field elsewhere.
public struct CoreTextArea: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    let error: String?
    let size: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let autofocus: Bool
    let focus: FocusState<Bool>.Binding?
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced
    @FocusState private var focused: Bool

    public init(
        _ label: String?, placeholder: String, text: Binding<String>, error: String? = nil,
        size: CGFloat = MacTextSize.body, minHeight: CGFloat = Space.s8 * 2, maxHeight: CGFloat = Space.s8 * 5,
        autofocus: Bool = false, focus: FocusState<Bool>.Binding? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.size = size
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.autofocus = autofocus
        self.focus = focus
    }

    /// The caller's focus when it moves focus itself (e.g. after a sheet's entrance), else this field's own.
    private var isFocused: Bool { focus?.wrappedValue ?? focused }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if let label { CoreFieldLabel(label) }
            TextEditor(text: $text)
                .coreFont(size: size).scrollContentBackground(.hidden)
                .focused(focus ?? $focused).focusEffectDisabled()
                .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        // TextEditor has no placeholder; drawn where its first line sits.
                        Text(placeholder).coreFont(size: size).foregroundStyle(palette.text2)
                            .padding(.horizontal, Space.s2 + 5).padding(.vertical, Space.s2)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .coreFieldSurface(focused: isFocused || forced == .focused, error: error != nil)
                .coreDimWhenDisabled(enabled)
                .accessibilityLabel(label ?? placeholder)
                .onAppear { if autofocus { (focus ?? $focused).wrappedValue = true } }
            if let error { CoreFieldError(error) }
        }
    }
}
