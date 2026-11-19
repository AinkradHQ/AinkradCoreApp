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
    @Environment(\.corePalette) private var palette
    @Bindable private var textSize = TextSizePrefs.shared
    @Bindable private var accent = AccentPrefs.shared
    @Bindable private var wallpaper = WallpaperPrefs.shared
    /// The wallpaper tab shown; it opens on the one the chosen wallpaper is in.
    @State private var group = WallpaperPrefs.shared.choice.group
    private static let scales: [Double] = [0.8, 0.9, 1, 1.1, 1.25, 1.5]

    /// The Appearance page has tabs (Look, Wallpaper); Clock is its own view.
    enum Part { case look, wallpaper }
    var part: Part = .look

    var body: some View {
        switch part {
        case .look: lookPage
        case .wallpaper: wallpaperPage
        }
    }

    private var wallpaperPage: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                CoreSegmented(
                    "Wallpaper kind", segments: WallpaperGroup.allCases.map { CoreSegment($0, $0.title) },
                    selection: $group)
                Spacer(minLength: Space.s3)
                Text(groupNote).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if group == .picture {
                picturePage
            } else {
                GlassSection(
                    group.title, sub: "Behind every window. Each one has a night and a day version.", symbol: "photo",
                    hue: GlassInk.blue, index: 2
                ) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3, alignment: .top), count: 4),
                        alignment: .leading, spacing: Space.s3
                    ) {
                        ForEach(CoreWallpaper.presets(in: group), id: \.self) { w in
                            WallpaperTile(choice: w, selected: wallpaper.choice == w, hasPicture: wallpaper.picture != nil) {
                                withAnimation(Motion.out(Motion.ui)) { wallpaper.choice = w }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }

    private var groupNote: String {
        switch group {
        case .photos: "\(CoreWallpaper.presets(in: .photos).count) photos"
        case .generated: "\(CoreWallpaper.presets(in: .generated).count) made for Ainkrad"
        case .picture: "Stays on this Mac"
        }
    }

    /// Your picture: the one chosen (when there is one) and a place to drop another. A night and a day version are made by
    /// the app from the one picture.
    private var picturePage: some View {
        GlassSection(
            "Your picture", sub: "Drop a picture here, or choose one from your Mac.", symbol: "photo", hue: GlassInk.blue,
            index: 2
        ) {
            AppActionTile(
                title: wallpaper.picture == nil ? "Choose picture…" : "Change picture…", symbol: "photo", key: "",
                hue: GlassInk.slate, prominent: wallpaper.picture == nil
            ) { wallpaper.choosePicture() }
        } content: {
            HStack(spacing: Space.s4) {
                if wallpaper.picture != nil {
                    WallpaperTile(choice: .picture, selected: wallpaper.choice == .picture, hasPicture: true) {
                        withAnimation(Motion.out(Motion.ui)) { wallpaper.choice = .picture }
                    }
                    .frame(width: Space.s8 * 6)
                }
                Text("It stays on this Mac. Ainkrad dims it for night and lightens it for day.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .leading)
            .coreWell()
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                wallpaper.adoptPicture(at: url)
                return true
            }
        }
    }

    private var lookPage: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Theme", sub: "Night or day for every window.", symbol: "circle.lefthalf.filled",
                hue: GlassInk.blue
            ) {
                Text(now).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    .contentTransition(.opacity)
            } content: {
                HStack(alignment: .top, spacing: Space.s3) {
                    ForEach(ThemeChoice.allCases, id: \.self) { c in
                        ThemeTile(choice: c, selected: shell.theme == c) { pick(c) }
                    }
                }
            }
            GlassSection(
                "Accent", sub: "Selection, the main button and switches. Status colours stay as they are.",
                symbol: "paintbrush", hue: GlassInk.blue, index: 1
            ) {
                Text(accent.accent.title).coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(GlassInk.secondary).contentTransition(.opacity)
            } content: {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: Space.s3, alignment: .top)],
                    alignment: .leading, spacing: Space.s3
                ) {
                    ForEach(CoreAccent.allCases, id: \.self) { a in
                        AccentTile(accent: a, selected: accent.accent == a) {
                            withAnimation(Motion.out(Motion.ui)) { accent.accent = a }
                        }
                    }
                }
            }
            GlassSection(
                "Text size", sub: "How large the words are in every window. 100% is the usual size.",
                symbol: "textformat.size", hue: GlassInk.blue, index: 3
            ) {
                Text(textSize.scale.formatted(.percent.precision(.fractionLength(0))))
                    .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            } content: {
                CoreSegmented(
                    "Text size",
                    segments: Self.scales.map { CoreSegment($0, $0.formatted(.percent.precision(.fractionLength(0)))) },
                    selection: $textSize.scale, fill: true)
            }
            GlassSection(
                "Content background", sub: "Inside every pane, dialog, pop-up and menu. An app can set its own.",
                symbol: "square.on.square", hue: GlassInk.blue, index: 4
            ) {
                SurfaceModeTabs(mode: $look.mode)
            } content: {
                VStack(alignment: .leading, spacing: Space.s3) {
                    GlassSlider(value: $look.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                    if look.mode == .blurred {
                        GlassSlider(value: $look.blur, in: 0...1, low: "Sharp", high: "Soft")
                    }
                }
            }
            GlassSection(
                "Advanced", sub: "Give one kind of surface its own background.", symbol: "slider.horizontal.3",
                hue: GlassInk.slate, index: 5
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
                        .coreFont(size: MacTextSize.headline, weight: .semibold)
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
            .coreWell()
        }
        .foregroundStyle(GlassInk.primary)
        .focusable().focused($focus).focusEffectDisabled()
        .coreSideKeys { step($0) }
        .onAppear { focus = true }
    }

    /// What the window shows right now: read from the palette the window really uses, so it never disagrees with it.
    private var now: String { Self.caption(chosen: shell.theme, isDay: palette.isDay) }

    static func caption(chosen: ThemeChoice, isDay: Bool) -> String {
        chosen == .system
            ? "Following your Mac: showing \(isDay ? "day" : "night") now" : "Showing \(isDay ? "day" : "night") now"
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

/// One wallpaper as a small picture with its name; "Your picture" asks for one the first time.
private struct WallpaperTile: View {
    let choice: CoreWallpaper
    let selected: Bool
    let hasPicture: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Group {
                    if choice == .picture && !hasPicture {
                        GlassInk.well.overlay {
                            Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                                .foregroundStyle(GlassInk.secondary)
                        }
                    } else {
                        WallpaperView(choice, thumb: true)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 72)
                .clipShape(coreShape(Radius.cardMac))
                .overlay {
                    coreShape(Radius.cardMac).strokeBorder(
                        GlassInk.primary.opacity(selected ? 0.6 : hovering ? 0.3 : 0.1), lineWidth: selected ? 1.5 : 1)
                }
                Text(choice == .picture && !hasPicture ? "Choose a picture…" : choice.title)
                    .coreFont(size: MacTextSize.meta, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? GlassInk.primary : GlassInk.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(choice.title) wallpaper")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One accent as a rounded swatch with its name; the chosen one carries a check.
private struct AccentTile: View {
    let accent: CoreAccent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s2) {
                coreShape(Radius.control).fill(accent.fill)
                    .frame(width: 56, height: 32)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        coreShape(Radius.control).strokeBorder(
                            GlassInk.primary.opacity(selected ? 0.6 : hovering ? 0.3 : 0), lineWidth: 1.5
                        ).padding(-3)
                    }
                Text(accent.title).coreFont(size: MacTextSize.meta, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? GlassInk.primary : GlassInk.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(accent.title) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One theme as a sky tile with its name and a line under it; the chosen one carries a blue edge and a check.
private struct ThemeTile: View {
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
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
                Text(choice.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s2)
            .background(
                selected ? palette.navActive : hovering ? GlassInk.wellHover : .clear, in: coreShape(Radius.pane)
            )
            .contentShape(coreShape(Radius.pane))
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
        case .night: "Always night."
        case .day: "Always day."
        case .sun: "Day from 7:00 to 18:00, night after."
        case .system: "Light or dark, as your Mac is set."
        }
    }

    @ViewBuilder private var thumb: some View {
        switch choice {
        case .night: sky(day: false)
        case .day: sky(day: true)
        case .sun:
            GeometryReader { g in
                HStack(spacing: 0) {
                    sky(day: false).frame(width: g.size.width / 2).clipped()
                    sky(day: true).frame(width: g.size.width / 2).clipped()
                }
            }
        case .system:
            ZStack {
                sky(day: true)
                sky(day: false).mask(
                    LinearGradient(colors: [.black, .clear], startPoint: .bottomLeading, endPoint: .topTrailing))
                Image(systemName: "laptopcomputer").font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
            }
        }
    }

    /// The chosen wallpaper as this theme shows it.
    private func sky(day: Bool) -> some View { WallpaperView(day: day, thumb: true) }
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
                    Text(part.title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(part.sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
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
