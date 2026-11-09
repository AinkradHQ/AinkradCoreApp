import SwiftUI

/// One choice of a `CoreSelect`.
public struct CoreSelectOption<Value: Hashable>: Identifiable {
    public var id: Value { value }
    public let value: Value
    public let title: String
    public let symbol: String?
    /// Quiet words at the right of the menu row, e.g. "default".
    public let note: String?
    public init(_ value: Value, _ title: String, symbol: String? = nil, note: String? = nil) {
        self.value = value
        self.title = title
        self.symbol = symbol
        self.note = note
    }
}

/// Pick one of a few values (Ahmed, 2026-11-06, variant A): the value and quiet up/down chevrons on the field surface,
/// opening the glass dropdown with a check on the current value. Same label and error as `CoreTextField`.
public struct CoreSelect<Value: Hashable>: View {
    let label: String?
    @Binding var selection: Value
    let options: [CoreSelectOption<Value>]
    let error: String?
    @State private var open = false
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.coreForcedInteraction) private var forced

    public init(
        _ label: String?, selection: Binding<Value>, options: [CoreSelectOption<Value>], error: String? = nil
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if let label { CoreFieldLabel(label) }
            CoreDropdown(items: items, isPresented: $open) { field }
                .coreDimWhenDisabled(enabled)
                .accessibilityLabel(label ?? "Choose")
                .accessibilityValue(current?.title ?? "")
            if let error { CoreFieldError(error) }
        }
    }

    private var current: CoreSelectOption<Value>? { options.first { $0.value == selection } }

    private var items: [CoreDropdownItem] {
        options.map { o in
            CoreDropdownItem(o.title, symbol: o.symbol, checked: o.value == selection, note: o.note) {
                selection = o.value
            }
        }
    }

    private var field: some View {
        HStack(spacing: Space.s2) {
            if let symbol = current?.symbol {
                Image(systemName: symbol).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    .accessibilityHidden(true)
            }
            Text(current?.title ?? "Choose").coreFont(size: MacTextSize.body).lineLimit(1)
                .truncationMode(.tail).foregroundStyle(current == nil ? palette.text2 : palette.text)
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.up.chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(palette.text2).accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlLg)
        .contentShape(coreShape(Radius.control))
        .coreFieldSurface(focused: open || forced == .focused, error: error != nil)
    }
}
