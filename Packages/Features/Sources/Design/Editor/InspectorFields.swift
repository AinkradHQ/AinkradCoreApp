import CoreUI
import SwiftUI

/// A titled group of inspector rows.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A number in a field: Return writes it, a bad entry says so under the field and writes nothing. Empty removes the value
/// when `clearable`.
struct NumberRow: View {
    let label: String
    let value: Double?
    var suffix: String?
    var clearable = false
    let commit: (Double?) -> Void
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        CoreTextField(label, placeholder: clearable ? "None" : "0", text: $text, error: error, suffix: suffix) {
            let t = text.trimmingCharacters(in: .whitespaces)
            if t.isEmpty, clearable {
                error = nil
                return commit(nil)
            }
            guard let v = Double(t), v.isFinite else {
                error = "Enter a number."
                return
            }
            error = nil
            commit(v)
        }
        .onAppear { text = Self.words(value) }
        .onChange(of: value) { _, v in text = Self.words(v) }
    }

    static func words(_ v: Double?) -> String {
        guard let v else { return "" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}

/// A `#rrggbb` colour in a field with its swatch; Return writes it.
struct ColorRow: View {
    let label: String
    let hex: String?
    let commit: (String) -> Void
    @State private var text = ""
    @State private var error: String?

    static func valid(_ s: String) -> Bool {
        guard s.hasPrefix("#"), [7, 9].contains(s.count) else { return false }
        return s.dropFirst().allSatisfy(\.isHexDigit)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            CoreTextField(label, placeholder: "#rrggbb", text: $text, error: error, mono: true) {
                let t = text.trimmingCharacters(in: .whitespaces)
                guard Self.valid(t) else {
                    error = "Use #rrggbb or #rrggbbaa."
                    return
                }
                error = nil
                commit(t.lowercased())
            }
            if let hex, Swatch.color(hex) != nil {
                Swatch(hex: hex).frame(width: MacSize.controlLg, height: MacSize.controlLg)
                    .accessibilityLabel("Current colour \(hex)")
            }
        }
        .onAppear { text = hex ?? "" }
        .onChange(of: hex) { _, v in text = v ?? "" }
    }
}

/// Picks a token of one kind, or none (the value is then a literal the rows beside it edit). `current` is the prop's value.
/// Shown only when the system has tokens of that kind, or the prop already names one.
struct TokenSelect: View {
    let label: String
    let kind: String
    let current: DJSON?
    let tokens: [DesignToken]
    /// A token name, or nil for "use a value": the caller writes its literal.
    let pick: (String?) -> Void

    var body: some View {
        let mine = tokens.filter { $0.kind == kind }
        let named = current?.tokenName
        if !mine.isEmpty || named != nil {
            CoreSelect(
                label,
                selection: Binding(get: { named ?? "" }, set: { pick($0.isEmpty ? nil : $0) }),
                options: [CoreSelectOption("", "Value")]
                    + mine.map { CoreSelectOption($0.name, $0.name, symbol: "swatchpalette") }
                    + extra(named, mine))
        }
    }

    private func extra(_ named: String?, _ mine: [DesignToken]) -> [CoreSelectOption<String>] {
        guard let named, !mine.contains(where: { $0.name == named }) else { return [] }
        return [CoreSelectOption(named, named, note: "not in the system")]
    }
}

/// A small fixed list as a select.
struct ChoiceRow: View {
    let label: String
    let value: String?
    let choices: [String]
    let pick: (String) -> Void
    var body: some View {
        CoreSelect(
            label, selection: Binding(get: { value ?? "" }, set: { if !$0.isEmpty { pick($0) } }),
            options: (value == nil ? [CoreSelectOption("", "Not set")] : [])
                + choices.map { CoreSelectOption($0, $0.capitalizedFirst) })
    }
}
