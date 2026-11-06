import AppKit
import CoreUI
import SwiftUI

/// Settings, Mac, Appearance (Ahmed, 2026-11-05: visual, plain words, keyboard driven): the four themes as big sky tiles,
/// what is showing right now, and one line about motion. ← → choose a theme.
struct AppearanceSection: View {
    @Bindable var shell: ShellModel
    @Bindable private var look = LookPrefs.shared
    /// Advanced: each part's own Look. Open by default once a part has one.
    @State private var advanced = !LookPrefs.shared.custom.isEmpty
    @FocusState private var focus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Theme", sub: "The desktop sky and the glass follow it.", symbol: "circle.lefthalf.filled",
                hue: GlassInk.blue
            ) {
                Text(now).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.secondary)
                    .contentTransition(.opacity)
            } content: {
                HStack(alignment: .top, spacing: Space.s3) {
                    ForEach(ThemeChoice.allCases, id: \.self) { c in
                        ThemeTile(choice: c, selected: shell.theme == c) { pick(c) }
                    }
                }
            }
            GlassSection(
                "Content background", sub: "Inside every pane, dialog, pop-up and menu. An app can set its own.",
                symbol: "square.on.square", hue: GlassInk.blue, index: 1
            ) {
                SurfaceModeTabs(mode: $look.mode)
            } content: {
                GlassSlider(value: $look.opacity, in: 0.05...1, low: "See-through", high: "Solid")
            }
            GlassSection(
                "Advanced", sub: "Give one kind of surface its own background.", symbol: "slider.horizontal.3",
                hue: GlassInk.slate, index: 2
            ) {
                AppActionTile(
                    title: advanced ? "Hide" : "Show", symbol: advanced ? "chevron.up" : "chevron.down", key: "",
                    hue: GlassInk.slate
                ) { withAnimation(Motion.out(Motion.ui)) { advanced.toggle() } }
            } content: {
                if advanced {
                    VStack(spacing: Space.s2) {
                        ForEach(LookPart.allCases, id: \.self) { part in LookPartRow(part: part, prefs: look) }
                    }
                    .transition(.opacity)
                }
            }
            HStack(spacing: Space.s3) {
                IconTile(reduce ? "figure.walk" : "figure.run", hue: GlassInk.slate, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reduce ? "Reduce Motion is on" : "Motion is full")
                        .font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(
                        reduce
                            ? "Your Mac asks for less movement, so Ainkrad keeps every change and drops the travel."
                            : "Turn on Reduce Motion in your Mac's settings to keep every change and drop the travel."
                    )
                    .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                AppActionTile(title: "Open Mac settings", symbol: "arrow.up.right.square", key: "", hue: GlassInk.slate)
                {
                    if let u = URL(
                        string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")
                    {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
            .padding(Space.s3)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        }
        .foregroundStyle(GlassInk.primary)
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onAppear { focus = true }
    }

    /// What the chosen theme shows right now.
    private var now: String {
        let dark: Bool =
            switch shell.theme {
            case .night: true
            case .day: false
            case .sun: !(7..<18).contains(Calendar.current.component(.hour, from: Date()))
            case .system: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            }
        return "Showing \(dark ? "night" : "day") now"
    }

    private func pick(_ c: ThemeChoice) {
        withAnimation(Motion.out(Motion.ui)) { shell.theme = c }
        shell.settings.saved()
    }

    private func step(_ d: Int) -> KeyPress.Result {
        let all = ThemeChoice.allCases
        let i = all.firstIndex(of: shell.theme) ?? 0
        pick(all[min(max(i + d, 0), all.count - 1)])
        return .handled
    }
}

/// One theme as a sky tile with its name and a line under it; the chosen one carries a blue edge and a check.
private struct ThemeTile: View {
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                thumb
                    .frame(maxWidth: .infinity).frame(height: 120)
                    .clipShape(coreShape(Radius.cardMac))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                                .white
                            )
                            .frame(width: 24, height: 24).background(GlassInk.blue, in: coreShape(Radius.chip))
                            .padding(Space.s2).transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay {
                        coreShape(Radius.cardMac).strokeBorder(
                            selected ? GlassInk.blue : GlassInk.wellEdge, lineWidth: selected ? 2 : 1)
                    }
                Text(choice.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(line).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s2)
            .background(hovering ? GlassInk.wellHover : .clear, in: coreShape(Radius.cardMac + 4))
            .contentShape(coreShape(Radius.cardMac + 4))
        }
        .buttonStyle(.plain).focusable(false)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.ui), value: selected)
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var line: String {
        switch choice {
        case .night: "Always the night sky."
        case .day: "Always the day sky."
        case .sun: "Day from 7:00 to 18:00, night after."
        case .system: "Light or dark, as your Mac is set."
        }
    }

    @ViewBuilder private var thumb: some View {
        switch choice {
        case .night: sky("HomeSky")
        case .day: sky("HomeSkyDay")
        case .sun:
            GeometryReader { g in
                HStack(spacing: 0) {
                    sky("HomeSky").frame(width: g.size.width / 2).clipped()
                    sky("HomeSkyDay").frame(width: g.size.width / 2).clipped()
                }
            }
        case .system:
            ZStack {
                sky("HomeSkyDay")
                sky("HomeSky").mask(
                    LinearGradient(colors: [.black, .clear], startPoint: .bottomLeading, endPoint: .topTrailing))
                Image(systemName: "laptopcomputer").font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
            }
        }
    }

    private func sky(_ name: String) -> some View {
        Image(name, bundle: .main).resizable().scaledToFill()
    }
}

/// One part in Appearance, Advanced: its name, Same (follows the content background) or its own look, and a slider when
/// it has its own.
private struct LookPartRow: View {
    let part: LookPart
    @Bindable var prefs: LookPrefs

    var body: some View {
        let own = prefs.custom[part]
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                IconTile(part.symbol, hue: own == nil ? GlassInk.slate : GlassInk.blue, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(part.title).font(.system(size: MacTextSize.body, weight: .semibold))
                    Text(part.sub).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                AppLookTabs(follow: follow, mode: mode, followTitle: "Same")
            }
            if own != nil {
                GlassSlider(value: opacity, in: 0.05...1, low: "See-through", high: "Solid")
            }
        }
        .padding(Space.s3)
        .coreWell()
        .animation(Motion.out(Motion.ui), value: own == nil)
        .help("Same follows the content background above")
    }

    private var follow: Binding<Bool> {
        Binding(
            get: { prefs.custom[part] == nil },
            set: { prefs.setCustom(part, $0 ? nil : prefs.look) })
    }
    private var mode: Binding<SurfaceMode> {
        Binding(
            get: { prefs.custom[part]?.mode ?? prefs.mode },
            set: { prefs.setCustom(part, CoreLook(mode: $0, opacity: prefs.custom[part]?.opacity ?? prefs.opacity)) })
    }
    private var opacity: Binding<Double> {
        Binding(
            get: { prefs.custom[part]?.opacity ?? prefs.opacity },
            set: { prefs.setCustom(part, CoreLook(mode: prefs.custom[part]?.mode ?? prefs.mode, opacity: $0)) })
    }
}
