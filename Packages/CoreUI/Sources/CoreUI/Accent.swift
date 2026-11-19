import Observation
import SwiftUI

/// The app's accent (Ahmed, 2026-11-15): Settings, Appearance. Graphite by default. It colours selection, the main button,
/// switches and icon tiles; the status hues (green, amber, red) never follow it.
public enum CoreAccent: String, CaseIterable, Sendable {
    case graphite, violet, blue, teal, copper
    case sky, indigo, green, mint, rose, pink, orange, red

    public var title: String { rawValue.capitalized }
    /// Fills: buttons, tiles, switches, selection. White text reads on every one.
    public var fill: Color { Self.fills[self] ?? .gray }
    /// The same hue as text and small glyphs: lighter at night, darker by day.
    public var ink: Color { Self.inks[self] ?? .gray }

    /// (night ink, night fill, day ink, day fill).
    private var hex: (UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .graphite: (0xD6D9DF, 0x555A64, 0x23272E, 0x2B2F36)
        case .violet: (0xADA3F2, 0x6455C9, 0x4A3BBE, 0x5546C8)
        case .blue: (0x85C2FF, 0x4099FF, 0x1A5CC6, 0x1F6BE0)
        case .teal: (0x6CC9B9, 0x1E8475, 0x0E6F61, 0x0F7A6B)
        case .copper: (0xE2A57E, 0xA8633E, 0x9A522A, 0xA65A2E)
        case .sky: (0x8ED3F5, 0x1676AD, 0x0A5F96, 0x0F6FA8)
        case .indigo: (0xA5B1FF, 0x4A56D8, 0x3340B8, 0x3D4AC4)
        case .green: (0x7FD48B, 0x2A8038, 0x1B6A2B, 0x237A33)
        case .mint: (0x7BE0C4, 0x13836B, 0x0A6A55, 0x0E7660)
        case .rose: (0xF5A3B8, 0xC23A63, 0xA82A52, 0xB5325C)
        case .pink: (0xF5A0D8, 0xBE3A96, 0xA02A7C, 0xAE3288)
        case .orange: (0xFFB070, 0xB4520F, 0xA24705, 0xB04F0A)
        case .red: (0xFF9A92, 0xC83A33, 0xB02620, 0xBE2D27)
        }
    }
    private static func rgb(_ h: UInt32) -> Color {
        Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255)
    }
    // Built once per accent so `GlassInk.blue == hue` comparisons keep working (same instance every read).
    private static let fills = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, GlassInk.adaptive(rgb($0.hex.1), day: rgb($0.hex.3))) })
    private static let inks = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, GlassInk.adaptive(rgb($0.hex.0), day: rgb($0.hex.2))) })
}

/// The chosen accent. Views that read a colour from it redraw when it changes (Observation tracks the read).
@Observable
public final class AccentPrefs: @unchecked Sendable {
    // ponytail: written only from Settings on the main actor, read from anywhere; a lock if writes ever leave main.
    public static let shared = AccentPrefs()
    public var accent: CoreAccent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "look.accent") } }
    private init() {
        accent = CoreAccent(rawValue: UserDefaults.standard.string(forKey: "look.accent") ?? "") ?? .graphite
    }
}

extension EnvironmentValues {
    /// The accent of the app pane in view (set by `.appLook`), or nil to use the global one from Settings, Appearance.
    @Entry public var coreAccent: CoreAccent? = nil
}

extension GlassInk {
    /// The accent fill for a view: its pane's own accent, else the global one. Components read `coreAccent` and call this.
    public static func accent(_ own: CoreAccent?) -> Color { (own ?? AccentPrefs.shared.accent).fill }
    /// The accent as text and small glyphs.
    public static func accentInk(_ own: CoreAccent?) -> Color { (own ?? AccentPrefs.shared.accent).ink }
}
