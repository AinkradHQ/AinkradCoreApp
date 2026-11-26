import AppKit
import CoreUI
import SwiftUI

/// The inspector's compact parts, Figma-style: a section head with its actions at the right, number fields with their
/// label inside ("X 40"), icon choices, and a colour row (swatch with the system colour picker, hex, opacity).

/// A section: its title and, at the right, small icon actions (add, show, …); then its rows.
struct InspectorBlock<Actions: View, Content: View>: View {
    let title: String
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.title = title
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                actions
            }
            .frame(minHeight: MacSize.controlMd)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s3)
        .overlay(alignment: .top) { coreShape(0).fill(GlassInk.secondary.opacity(0.12)).frame(height: 1) }
    }
}

extension InspectorBlock where Actions == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, actions: { EmptyView() }, content: content)
    }
}

/// A number with its label inside the field. Return or leaving the field writes it; empty writes nil (clears) when
/// `clearable`, else puts the value back. `scale` shows a fraction as a percentage (opacity).
struct InlineNumber: View {
    let label: String
    let value: Double?
    var suffix: String?
    var scale: Double = 1
    var clearable = false
    let commit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            Text(label).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
                .lineLimit(1).fixedSize()
            TextField("", text: $text, prompt: Text(clearable ? "–" : "0").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).monospacedDigit().focused($focused)
                .onSubmit(write)
            if let suffix { Text(suffix).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
        }
        .padding(.horizontal, Space.s2)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
        .coreFieldSurface(focused: focused)
        .onAppear { text = Self.words(value, scale) }
        .onChange(of: value) { _, v in if !focused { text = Self.words(v, scale) } }
        .onChange(of: focused) { _, on in if !on { write() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private func write() {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty {
            if clearable { commit(nil) } else { text = Self.words(value, scale) }
            return
        }
        guard let v = Double(t), v.isFinite else {
            text = Self.words(value, scale)
            return
        }
        if v / scale != value { commit(v / scale) }
    }

    static func words(_ v: Double?, _ scale: Double = 1) -> String {
        guard let v else { return "" }
        let s = v * scale
        return s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)
    }
}

/// A row of icon choices (one lit), like Figma's layout direction or text align.
struct IconChoices: View {
    let choices: [(value: String, symbol: String, label: String)]
    let current: String?
    let pick: (String) -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.value) { c in
                Button {
                    pick(c.value)
                } label: {
                    Image(systemName: c.symbol).coreFont(size: MacTextSize.body)
                        .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
                        .background(
                            current == c.value ? palette.btnPrimary.opacity(0.28) : .clear,
                            in: coreShape(Radius.control)
                        )
                        .contentShape(coreShape(Radius.control))
                }
                .buttonStyle(.plain)
                .help(c.label)
                .accessibilityLabel(c.label)
                .accessibilityAddTraits(current == c.value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
    }
}

/// A small icon button for a section head or a row's end (add, remove, show).
struct InspectorIcon: View {
    let symbol: String
    let label: String
    let run: () -> Void
    var body: some View { CoreIconButton(symbol: symbol, label: label, action: run) }
}

/// A colour: the swatch opens the system colour picker (changes are written once it settles), the hex is typed.
struct ColorField: View {
    let hex: String?
    let commit: (String) -> Void
    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var picked: Binding<Color> {
        Binding(
            get: { FrameSketch.color(hex, fallback: .gray) },
            set: { c in
                guard let h = Self.hex(c) else { return }
                text = h
                // The picker sends a value per mouse move: write once it rests (one undo step, not hundreds).
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { commit(h) }
                }
            })
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            ColorPicker("", selection: picked, supportsOpacity: true).labelsHidden().fixedSize()
            TextField("", text: $text, prompt: Text("#rrggbb").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).monospaced().focused($focused)
                .onSubmit(write)
        }
        .padding(.leading, Space.s1).padding(.trailing, Space.s2)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
        .coreFieldSurface(focused: focused)
        .onAppear { text = (hex ?? "").uppercased() }
        .onChange(of: hex) { _, v in if !focused { text = (v ?? "").uppercased() } }
        .onChange(of: focused) { _, on in if !on { write() } }
    }

    private func write() {
        var t = text.trimmingCharacters(in: .whitespaces)
        if !t.hasPrefix("#") { t = "#" + t }
        guard ColorRow.valid(t) else {
            text = (hex ?? "").uppercased()
            return
        }
        if t.lowercased() != hex?.lowercased() { commit(t.lowercased()) }
    }

    /// `#rrggbb`, or `#rrggbbaa` when not opaque.
    static func hex(_ c: Color) -> String? {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return nil }
        func b(_ v: CGFloat) -> String { String(format: "%02x", Int((min(max(v, 0), 1) * 255).rounded())) }
        let rgb = "#" + b(n.redComponent) + b(n.greenComponent) + b(n.blueComponent)
        return n.alphaComponent < 0.999 ? rgb + b(n.alphaComponent) : rgb
    }
}

/// A compact menu of words (blend, case, sizing), Figma-style: the value and a chevron.
struct InlineMenu: View {
    let label: String
    let value: String
    let choices: [String]
    let pick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { c in
                Button {
                    pick(c)
                } label: {
                    if c == value {
                        Label(c.capitalizedFirst, systemImage: "checkmark")
                    } else {
                        Text(c.capitalizedFirst)
                    }
                }
            }
        } label: {
            HStack(spacing: Space.s1) {
                Text(label).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
                Text(value.capitalizedFirst).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .padding(.horizontal, Space.s2)
            .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(label)
    }
}
