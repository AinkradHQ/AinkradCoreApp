import CoreUI
import SwiftUI

/// Settings, Terminal: a live preview on top, then theme, font, cursor and background. Changes apply to every open
/// terminal at once.
struct TerminalSettingsView: View {
    @Bindable var prefs = TerminalPrefs.shared
    /// Read live: the section is built once, before the runners arrive.
    weak var model: TerminalsModel?
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
                GlassSlider(value: $prefs.fontSize, in: 9...24, low: "Small", high: "Large", unit: " pt", step: 1) {
                    _ in
                    Int(prefs.fontSize.rounded())
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
                "Transparency", sub: "How much of the sky shows through the terminal.",
                symbol: "circle.lefthalf.filled",
                hue: GlassInk.slate, index: 4
            ) {
                CoreSegmented(
                    "Behind the terminal",
                    segments: [
                        CoreSegment(true, "Blurred", symbol: "drop.halffull"),
                        CoreSegment(false, "Sharp", symbol: "drop"),
                    ],
                    selection: $prefs.blur)
            } content: {
                GlassSlider(
                    value: Binding(get: { 1 - prefs.opacity }, set: { prefs.opacity = 1 - $0 }), in: 0...0.6,
                    low: "Solid", high: "See-through")
            }
            GlassSection(
                "App surface", sub: "The Terminals app's own background.", symbol: "square.on.square",
                hue: GlassInk.blue, index: 5
            ) {
                CoreSegmented(
                    "Surface",
                    segments: [
                        CoreSegment(TerminalPrefs.Surface.clear, "Clear", symbol: "square.dashed"),
                        CoreSegment(.frosted, "Frosted", symbol: "drop.halffull"),
                        CoreSegment(.theme, "Theme", symbol: "paintpalette"),
                        CoreSegment(.solid, "Solid", symbol: "square.fill"),
                    ], selection: $prefs.surface)
            } content: {
                GlassSlider(value: $prefs.surfaceOpacity, low: "Clear", high: "Solid")
            }
            GlassSection(
                "Defaults", sub: "What New terminal (⌘T) uses, and what opening and ending do.", symbol: "gearshape",
                hue: GlassInk.green, index: 6
            ) {
                Picker("Runner", selection: $prefs.defaultRunner) {
                    Text("Best ready runner").tag("")
                    ForEach(model?.runners ?? []) { r in Text(r.name).tag(r.id) }
                }
                Picker("Shell", selection: $prefs.defaultShell) {
                    Text("Login shell").tag("")
                    Text("zsh").tag("zsh")
                    Text("bash").tag("bash")
                    Text("sh").tag("sh")
                }
                Toggle("Open new terminals full pane", isOn: $prefs.openFullPane).toggleStyle(.switch)
                Toggle("Ask before ending a terminal", isOn: $prefs.confirmEnd).toggleStyle(.switch)
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
        .background {
            if prefs.blur { coreShape(Radius.cardMac).fill(.ultraThinMaterial) }
        }
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .animation(.easeOut(duration: 0.2), value: prefs.fontSize)
        .animation(.easeOut(duration: 0.2), value: prefs.opacity)
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
