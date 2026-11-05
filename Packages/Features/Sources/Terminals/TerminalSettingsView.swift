import CoreUI
import SwiftUI

/// Settings, Terminal: a live preview on top, then theme, font, cursor and background. Changes apply to every open
/// terminal at once.
struct TerminalSettingsView: View {
    @Bindable var prefs = TerminalPrefs.shared
    @Namespace private var pick

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            TerminalPreview(prefs: prefs).coreRise(true, 0)
            GlassSection(
                "Theme", sub: "The terminal's colours.", symbol: "paintpalette", hue: GlassInk.violet, index: 1
            ) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Space.s2)], spacing: Space.s2) {
                    ForEach(TermTheme.all) { t in
                        ThemeTile(theme: t, on: prefs.themeID == t.id, lens: pick) { prefs.themeID = t.id }
                    }
                }
            }
            GlassSection("Font", sub: "Family and size.", symbol: "textformat", hue: GlassInk.blue, index: 2) {
                HStack(spacing: Space.s3) {
                    Picker("Family", selection: $prefs.fontName) {
                        ForEach(TerminalPrefs.families, id: \.self) { f in Text(f).tag(f) }
                    }
                    .pickerStyle(.menu).frame(maxWidth: 260)
                    Spacer()
                    Text("\(Int(prefs.fontSize)) pt").font(.system(size: MacTextSize.body, weight: .semibold))
                        .monospacedDigit().contentTransition(.numericText())
                }
                HStack(spacing: Space.s3) {
                    Image(systemName: "textformat.size.smaller").foregroundStyle(GlassInk.secondary)
                    Slider(value: $prefs.fontSize, in: 9...24, step: 1)
                    Image(systemName: "textformat.size.larger").foregroundStyle(GlassInk.secondary)
                }
            }
            GlassSection(
                "Cursor", sub: "Its shape, and whether it blinks.", symbol: "cursorarrow.rays", hue: GlassInk.green,
                index: 3
            ) {
                HStack(spacing: Space.s2) {
                    ForEach(TerminalPrefs.CursorShape.allCases, id: \.self) { c in
                        CursorTile(shape: c, on: prefs.cursor == c, blink: prefs.blink) { prefs.cursor = c }
                    }
                }
                Toggle("Blink", isOn: $prefs.blink).toggleStyle(.switch)
            }
            GlassSection(
                "Background", sub: "How much of the glass shows through.", symbol: "circle.lefthalf.filled",
                hue: GlassInk.slate, index: 4
            ) {
                HStack(spacing: Space.s3) {
                    Text("Clear").foregroundStyle(GlassInk.secondary)
                    Slider(value: $prefs.opacity, in: 0.4...1)
                    Text("Solid").foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: prefs.themeID)
    }
}

/// A few lines of a terminal in the chosen font, theme, cursor and background.
private struct TerminalPreview: View {
    let prefs: TerminalPrefs
    var body: some View {
        let t = prefs.theme
        let font = Font(prefs.font)
        VStack(alignment: .leading, spacing: 4) {
            Text("~/AinkradCore $ cargo test -p citadel").foregroundStyle(Color(nsColor: t.foreground))
            Text("test result: ok. 412 passed; 0 failed").foregroundStyle(Color(nsColor: t.ansi[2]))
            Text("warning: 2 unused imports").foregroundStyle(Color(nsColor: t.ansi[3]))
            HStack(spacing: 0) {
                Text("~/AinkradCore $ ").foregroundStyle(Color(nsColor: t.foreground))
                PreviewCursor(
                    shape: prefs.cursor, blink: prefs.blink, color: Color(nsColor: t.caret), size: prefs.fontSize)
            }
        }
        .font(font)
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: t.background).opacity(prefs.opacity), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .animation(.easeOut(duration: 0.2), value: prefs.fontSize)
        .accessibilityLabel("Preview of the terminal")
    }
}

private struct ThemeTile: View {
    let theme: TermTheme
    let on: Bool
    let lens: Namespace.ID
    let pick: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("$ ls").foregroundStyle(Color(nsColor: theme.foreground))
                    HStack(spacing: 3) {
                        ForEach(1..<7, id: \.self) { i in
                            coreShape(2).fill(Color(nsColor: theme.ansi[i])).frame(width: 12, height: 8)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: theme.background), in: coreShape(Radius.control))
                HStack {
                    Text(theme.title).font(.system(size: MacTextSize.body, weight: .semibold))
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? GlassInk.blue : GlassInk.track).contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(Space.s2)
            .background {
                if on {
                    coreShape(Radius.cardMac).fill(GlassInk.blue.opacity(0.16))
                        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.blue.opacity(0.5), lineWidth: 1) }
                        .matchedGeometryEffect(id: "theme", in: lens)
                } else {
                    coreShape(Radius.cardMac).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct CursorTile: View {
    let shape: TerminalPrefs.CursorShape
    let on: Bool
    let blink: Bool
    let pick: () -> Void
    var body: some View {
        Button(action: pick) {
            VStack(spacing: Space.s2) {
                PreviewCursor(shape: shape, blink: blink && on, color: on ? GlassInk.blue : GlassInk.primary, size: 18)
                    .frame(height: 24)
                Text(shape.rawValue.capitalized).font(.system(size: MacTextSize.meta, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(on ? GlassInk.blue.opacity(0.18) : GlassInk.well, in: coreShape(Radius.row))
            .overlay {
                coreShape(Radius.row).strokeBorder(on ? GlassInk.blue.opacity(0.5) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(shape.rawValue) cursor")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A cursor of the chosen shape; it blinks by opacity, so it stays under Reduce Motion as a gentle fade.
private struct PreviewCursor: View {
    let shape: TerminalPrefs.CursorShape
    let blink: Bool
    let color: Color
    let size: Double
    @State private var dim = false
    var body: some View {
        let h = size * 1.25
        let w = size * 0.6
        Group {
            switch shape {
            case .block: Rectangle().frame(width: w, height: h)
            case .underline: Rectangle().frame(width: w, height: 2).frame(height: h, alignment: .bottom)
            case .bar: Rectangle().frame(width: 2, height: h).frame(width: w, alignment: .leading)
            }
        }
        .foregroundStyle(color)
        .opacity(blink && dim ? 0.15 : 1)
        .animation(blink ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default, value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}
