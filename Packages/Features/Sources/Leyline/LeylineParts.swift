import CoreUI
import SwiftUI

// Small pieces the Leyline page, the host panel and the host view share. Built from CoreUI parts only.

/// A row of tabs where each shows the key that picks it ("Terminal ⌘1", "Map ⌘M"): the picked one sits on a well, the others
/// are plain. Hover lifts each like any Core button.
struct KeyTabs<ID: Hashable>: View {
    struct Tab: Identifiable {
        let id: ID
        let title: String
        let symbol: String?
        let key: String
    }
    let label: String
    let tabs: [Tab]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(tabs) { t in
                Button {
                    selection = t.id
                } label: {
                    if let s = t.symbol { Label(t.title, systemImage: s) } else { Text(t.title) }
                }
                .buttonStyle(CoreButtonStyle(t.id == selection ? .secondary : .plain, size: .medium))
                .environment(\.coreKeycap, t.key)
                .accessibilityAddTraits(t.id == selection ? .isSelected : [])
                .accessibilityIdentifier("tab-\(t.title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A host's light: a small rounded square. Green answers, amber is slow, grey is offline or not checked yet. Always beside words.
struct StatusLight: View {
    let light: HostLight
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(2).fill(fill).frame(width: 7, height: 7).accessibilityHidden(true)
    }
    private var fill: Color {
        switch light {
        case .ok: palette.success
        case .slow: palette.warning
        case .off, .unknown: GlassInk.secondary.opacity(0.5)
        }
    }
}

/// The icon tile of a host card or row.
struct HostTile: View {
    let symbol: String
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol).coreFont(size: size * 0.46, weight: .medium)
            .frame(width: size, height: size)
            .background(GlassInk.well, in: coreShape(size > 40 ? Radius.cardMac : Radius.control))
            .accessibilityHidden(true)
    }
}

/// The Core's emblem on an accent-soft tile.
struct CoreEmblemTile: View {
    var size: CGFloat = 44
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(size > 40 ? Radius.cardMac : Radius.control)
            .fill(palette.btnPrimary.opacity(0.22))
            .frame(width: size, height: size)
            .overlay { Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: size * 0.5) }
            .accessibilityHidden(true)
    }
}

/// A load as a thin bar, 0...100: blue, amber over 70, red over 85. The number is always said somewhere beside it.
struct LoadBar: View {
    let percent: Double
    var height: CGFloat = 3
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(height / 2).fill(palette.track)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    coreShape(height / 2).fill(Self.tone(percent, palette))
                        .frame(width: g.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
    static func tone(_ p: Double, _ palette: Palette) -> Color {
        p > 85 ? palette.error : p > 70 ? palette.warning : palette.primary
    }
}

/// "Type to find a host" with ⌘K on it. The page focuses it with ⌘K; Esc clears it, then gives focus back.
struct FindField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text("Type to find a host").foregroundStyle(GlassInk.secondary))
                .textFieldStyle(.plain).focused(focus).onSubmit(onSubmit)
                .accessibilityLabel("Find a host")
                .accessibilityIdentifier("leyline-find")
            if text.isEmpty {
                CoreKeycap("⌘K")
            } else {
                CoreIconButton(symbol: "xmark", label: "Clear") { text = "" }
            }
        }
        .padding(.horizontal, Space.s3).frame(width: Space.s8 * 10 + Space.s5, height: MacSize.controlLg)
        .coreFieldSurface(focused: focus.wrappedValue)
        .onExitCommand {
            if text.isEmpty { focus.wrappedValue = false } else { text = "" }
        }
    }
}

/// The keys of the page, quietly along the bottom.
struct KeyHints: View {
    let hints: [(String, String)]
    var body: some View {
        HStack(spacing: Space.s4) {
            ForEach(hints, id: \.0) { k, word in
                HStack(spacing: Space.s1 + 2) {
                    CoreKeycap(k)
                    Text(word).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: Space.s8 + Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keys: " + hints.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
    }
}

/// The selected fill of a card or row (no outline): the accent, softly.
struct SelectedFill: ViewModifier {
    let selected: Bool
    let hover: Bool
    let radius: CGFloat
    @Environment(\.corePalette) private var palette
    func body(content: Content) -> some View {
        content.background(
            selected ? palette.btnPrimary.opacity(0.22) : hover ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(radius))
    }
}
