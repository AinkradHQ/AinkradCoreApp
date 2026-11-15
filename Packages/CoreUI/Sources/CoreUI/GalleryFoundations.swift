#if DEBUG
import SwiftUI

extension CoreUIGallery {
    @ViewBuilder var foundations: some View {
        GSpec(
            "CoreAccent",
            "The one accent: selection, the main button, switches. Settings, Appearance; graphite by default."
        ) {
            HStack(spacing: Space.s4) {
                ForEach(CoreAccent.allCases, id: \.self) { a in
                    GVariant(a.title + (accent.accent == a ? " (in use)" : "")) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            coreShape(Radius.control).fill(a.fill).frame(width: 72, height: 36)
                                .overlay { Text("Fill").coreFont(size: MacTextSize.meta).foregroundStyle(.white) }
                            Text("Ink Aa").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(a.ink)
                        }
                    }
                }
            }
        }
        GSpec(
            "GlassInk status hues",
            "Status only, always with a word: green ok, amber needs you, red error, slate quiet."
        ) {
            HStack(spacing: Space.s4) {
                ForEach(
                    [
                        ("Ok", GlassInk.green), ("Needs you", GlassInk.amber), ("Error", GlassInk.red),
                        ("Quiet", GlassInk.slate),
                    ],
                    id: \.0
                ) { name, hue in
                    GVariant(name) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            coreShape(Radius.control).fill(hue).frame(width: 72, height: 36)
                            Text("Ink Aa").coreFont(size: MacTextSize.body, weight: .semibold)
                                .foregroundStyle(GlassInk.ink(hue))
                        }
                    }
                }
            }
        }
        GSpec("GlassInk neutrals", "Ink and the wells content sits in.") {
            HStack(spacing: Space.s4) {
                ForEach(
                    [
                        ("primary", GlassInk.primary), ("secondary", GlassInk.secondary), ("track", GlassInk.track),
                        ("well", GlassInk.well), ("wellHover", GlassInk.wellHover), ("wellEdge", GlassInk.wellEdge),
                    ], id: \.0
                ) { name, c in
                    GVariant(name) { coreShape(Radius.control).fill(c).frame(width: 72, height: 36) }
                }
            }
        }
        GSpec("MacTextSize", "The type scale. coreFont scales it with Settings, Appearance, Text size.") {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(
                    [
                        ("large 20", MacTextSize.large, Font.Weight.semibold),
                        ("title 15", MacTextSize.title, .semibold),
                        ("headline 13", MacTextSize.headline, .semibold), ("body 13", MacTextSize.body, .regular),
                        ("meta 11", MacTextSize.meta, .regular),
                    ], id: \.0
                ) { name, size, weight in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                        Text(name).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(GlassInk.secondary).frame(width: 96, alignment: .leading)
                        Text("Two AI sessions are running").coreFont(size: size, weight: weight)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text("figure 28").coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(GlassInk.secondary).frame(width: 96, alignment: .leading)
                    Text("$142.40").coreFont(size: 28, weight: .bold).monospacedDigit()
                }
            }
        }
        GSpec("Space", "The spacing scale: every gap and padding is one of these.") {
            HStack(alignment: .bottom, spacing: Space.s4) {
                ForEach(
                    [
                        ("s1", Space.s1), ("s2", Space.s2), ("s3", Space.s3), ("s4", Space.s4), ("s5", Space.s5),
                        ("s6", Space.s6), ("s8", Space.s8),
                    ], id: \.0
                ) { name, v in
                    GVariant("\(name) \(Int(v))") {
                        coreShape(2).fill(GlassInk.blue).frame(width: v, height: v)
                    }
                }
            }
        }
        GSpec(
            "Radius",
            "Four radii, one job each: chips, controls, cards and rows, panes and dialogs. Bars under 6 pt keep a small radius."
        ) {
            HStack(alignment: .bottom, spacing: Space.s4) {
                ForEach(
                    [
                        ("chip", Radius.chip), ("control", Radius.control), ("cardMac", Radius.cardMac),
                        ("pane", Radius.pane), ("panel", Radius.pane), ("window", Radius.window),
                    ], id: \.0
                ) { name, r in
                    GVariant("\(name) \(Int(r))") {
                        coreShape(r).fill(GlassInk.wellHover).frame(width: 88, height: 56)
                    }
                }
            }
        }
        GSpec("Motion", "Durations and curves. Transform and opacity only; Reduce Motion keeps a fade.") {
            HStack(spacing: Space.s5) {
                ForEach(
                    [
                        ("press", Motion.press), ("hover", Motion.hover), ("ui", Motion.ui), ("move", Motion.move),
                        ("reveal", Motion.reveal),
                    ], id: \.0
                ) { name, d in
                    GVariant(name) {
                        Text("\(Int(d * 1000)) ms").coreFont(size: MacTextSize.title, weight: .semibold)
                            .monospacedDigit()
                    }
                }
            }
        }
        GSpec(
            "CoreWallpaper", "Twelve wallpapers plus Sky and Plain, each with a night (left) and a day (right) version."
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3, alignment: .top), count: 4),
                alignment: .leading, spacing: Space.s3
            ) {
                ForEach(CoreWallpaper.presets, id: \.self) { w in
                    GVariant(w.title + (wallpaper.choice == w ? " (in use)" : "")) {
                        HStack(spacing: 2) {
                            WallpaperView(w, day: false, thumb: true)
                            WallpaperView(w, day: true, thumb: true)
                        }
                        .frame(height: 64)
                        .clipShape(coreShape(Radius.control))
                    }
                }
            }
        }
    }
}
#endif
