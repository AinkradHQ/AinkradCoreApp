import AppKit
import CoreUI
import Observation
import SwiftTerm
import SwiftUI

/// How terminals look on this Mac: font, size, theme, cursor, background (Settings, Terminal). Kept in UserDefaults; every
/// open terminal follows a change at once.
@MainActor @Observable
final class TerminalPrefs {
    static let shared = TerminalPrefs()

    var fontName: String { didSet { save() } }
    var fontSize: Double { didSet { save() } }
    var themeID: String { didSet { save() } }
    var cursor: CursorShape { didSet { save() } }
    var blink: Bool { didSet { save() } }
    /// How solid the terminal's background is, 0.4 (see-through glass) to 1 (opaque).
    var opacity: Double { didSet { save() } }
    /// Frosts what shows through a see-through terminal, so text stays readable over a busy sky.
    var blur: Bool { didSet { save() } }

    /// The Terminals app's own surface (the list): glass clear or frosted, the theme's colour, or a solid dark.
    enum Surface: String, CaseIterable { case clear, frosted, theme, solid }
    var surface: Surface { didSet { save() } }
    var surfaceBlur: Bool { didSet { save() } }
    /// The terminal screen's own style (the same four as the surface).
    var screen: Surface { didSet { save() } }
    /// How solid that surface is, 0 (see-through) to 1.
    var surfaceOpacity: Double { didSet { save() } }

    /// Defaults for the quick New terminal and for what opening one does.
    var defaultRunner: String { didSet { save() } }  // "" = the best ready runner
    var defaultShell: String { didSet { save() } }  // "" = the runner's login shell
    var openFullPane: Bool { didSet { save() } }
    var confirmEnd: Bool { didSet { save() } }

    enum CursorShape: String, CaseIterable { case block, underline, bar }

    private let defaults = UserDefaults.standard
    private init() {
        fontName = defaults.string(forKey: "terminal.font") ?? TerminalPrefs.systemMono
        fontSize = defaults.object(forKey: "terminal.size") as? Double ?? 12
        themeID = defaults.string(forKey: "terminal.theme") ?? TermTheme.all[0].id
        cursor = CursorShape(rawValue: defaults.string(forKey: "terminal.cursor") ?? "") ?? .block
        blink = defaults.object(forKey: "terminal.blink") as? Bool ?? true
        opacity = defaults.object(forKey: "terminal.opacity") as? Double ?? 0.78
        blur = defaults.object(forKey: "terminal.blur") as? Bool ?? true
        surface =
            Surface(rawValue: defaults.string(forKey: "terminal.surface") ?? "").map { $0 == .frosted ? .clear : $0 }
            ?? .theme
        surfaceOpacity = defaults.object(forKey: "terminal.surfaceOpacity") as? Double ?? 0.78
        surfaceBlur = defaults.object(forKey: "terminal.surfaceBlur") as? Bool ?? true
        screen =
            Surface(rawValue: defaults.string(forKey: "terminal.screen") ?? "").map { $0 == .frosted ? .clear : $0 }
            ?? .theme
        defaultRunner = defaults.string(forKey: "terminal.defaultRunner") ?? ""
        defaultShell = defaults.string(forKey: "terminal.defaultShell") ?? ""
        openFullPane = defaults.object(forKey: "terminal.openFull") as? Bool ?? false
        confirmEnd = defaults.object(forKey: "terminal.confirmEnd") as? Bool ?? true
    }

    static let systemMono = "SF Mono"
    static let changed = Notification.Name("ainkrad.terminal.prefs")

    var theme: TermTheme { TermTheme.all.first { $0.id == themeID } ?? TermTheme.all[0] }

    /// The three-choice look of the screen and of the app surface.
    var screenMode: Binding<SurfaceMode> {
        Binding(
            get: { SurfaceMode(style: Self.app(self.screen), blur: self.blur) },
            set: {
                self.screen = Self.term($0.style)
                self.blur = $0.blur
            })
    }
    var surfaceMode: Binding<SurfaceMode> {
        Binding(
            get: { SurfaceMode(style: Self.app(self.surface), blur: self.surfaceBlur) },
            set: {
                self.surface = Self.term($0.style)
                self.surfaceBlur = $0.blur
            })
    }

    /// The style as the shared surface type (theme ↔ tinted).
    static func app(_ s: Surface) -> AppSurfaceStyle {
        s == .theme ? .tinted : AppSurfaceStyle(rawValue: s.rawValue) ?? .frosted
    }
    static func term(_ s: AppSurfaceStyle) -> Surface {
        s == .tinted ? .theme : Surface(rawValue: s.rawValue) ?? .theme
    }

    /// The terminal screen's background colour for its style, at its transparency.
    var screenColor: NSColor {
        let a = CGFloat(opacity)
        switch screen {
        case .clear: return NSColor.black.withAlphaComponent(a * 0.6)
        case .frosted: return NSColor(white: 0.06, alpha: a * 0.6)
        case .theme: return theme.background.withAlphaComponent(a)
        case .solid: return NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 0.5 + a * 0.5)
        }
    }

    var font: NSFont {
        let size = CGFloat(fontSize)
        if fontName != Self.systemMono, let f = NSFont(name: fontName, size: size) { return f }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func cursorStyle(reduceMotion: Bool) -> CursorStyle {
        let blinks = blink && !reduceMotion
        switch cursor {
        case .block: return blinks ? .blinkBlock : .steadyBlock
        case .underline: return blinks ? .blinkUnderline : .steadyUnderline
        case .bar: return blinks ? .blinkBar : .steadyBar
        }
    }

    /// The monospaced families on this Mac, SF Mono first.
    static let families: [String] = {
        let mono = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let f = NSFont(name: family, size: 12) else { return false }
            return f.isFixedPitch || f.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        return [systemMono] + mono.filter { $0 != systemMono }.sorted()
    }()

    private func save() {
        defaults.set(fontName, forKey: "terminal.font")
        defaults.set(fontSize, forKey: "terminal.size")
        defaults.set(themeID, forKey: "terminal.theme")
        defaults.set(cursor.rawValue, forKey: "terminal.cursor")
        defaults.set(blink, forKey: "terminal.blink")
        defaults.set(opacity, forKey: "terminal.opacity")
        defaults.set(blur, forKey: "terminal.blur")
        defaults.set(surface.rawValue, forKey: "terminal.surface")
        defaults.set(surfaceOpacity, forKey: "terminal.surfaceOpacity")
        defaults.set(surfaceBlur, forKey: "terminal.surfaceBlur")
        defaults.set(screen.rawValue, forKey: "terminal.screen")
        defaults.set(defaultRunner, forKey: "terminal.defaultRunner")
        defaults.set(defaultShell, forKey: "terminal.defaultShell")
        defaults.set(openFullPane, forKey: "terminal.openFull")
        defaults.set(confirmEnd, forKey: "terminal.confirmEnd")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// A terminal colour theme: background, text, cursor, and the 16 ANSI colours programs use.
struct TermTheme: Identifiable, Equatable {
    let id: String
    let title: String
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let ansi: [NSColor]

    private static func c(_ hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    private static func palette(_ hexes: [UInt32]) -> [NSColor] { hexes.map(c) }

    /// Ainkrad's own themes (no copies of other apps' themes).
    static let all: [TermTheme] = [
        TermTheme(
            id: "deep-blue", title: "Deep Blue", background: c(0x030810), foreground: c(0xCFE0F5), caret: c(0x7FB8FF),
            ansi: palette([
                0x1B2433, 0xFF6B6B, 0x4CD787, 0xFFC857, 0x5AA9FF, 0xB98CFF, 0x4FD1E0, 0xCFE0F5,
                0x4A5A73, 0xFF8E8E, 0x7BE6A6, 0xFFDA85, 0x8CC4FF, 0xCFADFF, 0x86E3EE, 0xFFFFFF,
            ])),
        TermTheme(
            id: "midnight", title: "Midnight", background: c(0x05050A), foreground: c(0xE6E6F0), caret: c(0xB98CFF),
            ansi: palette([
                0x1A1A24, 0xF2647A, 0x5BD69B, 0xF5C76B, 0x7A9CFF, 0xC792FF, 0x5ED4D4, 0xE6E6F0,
                0x4B4B5E, 0xFF8FA0, 0x86E8B7, 0xFFDB94, 0xA3BBFF, 0xDCB6FF, 0x8CE8E8, 0xFFFFFF,
            ])),
        TermTheme(
            id: "graphite", title: "Graphite", background: c(0x1C1D21), foreground: c(0xD8D9DD), caret: c(0xFFFFFF),
            ansi: palette([
                0x2C2D33, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xD8D9DD,
                0x5C5E66, 0xEF8A93, 0xB2D69A, 0xF0D39C, 0x8CC6F5, 0xD9A0E8, 0x84CDD6, 0xFFFFFF,
            ])),
        TermTheme(
            id: "aurora", title: "Aurora", background: c(0x07141A), foreground: c(0xC8F2E8), caret: c(0x4CE0B3),
            ansi: palette([
                0x14262E, 0xFF7A85, 0x4CE0B3, 0xF9D56E, 0x6AB8FF, 0xB59CFF, 0x5EE0E8, 0xC8F2E8,
                0x3D5A66, 0xFF9DA5, 0x7DEBC9, 0xFBE39C, 0x99CFFF, 0xCDBEFF, 0x8DEBF0, 0xFFFFFF,
            ])),
        TermTheme(
            id: "paper", title: "Paper", background: c(0xF6F4EE), foreground: c(0x23262E), caret: c(0x2F6FEB),
            ansi: palette([
                0x23262E, 0xC9384A, 0x2E8B57, 0xA86B00, 0x2F6FEB, 0x8A4FD1, 0x0E8A96, 0xD8D5CC,
                0x5D6270, 0xE0566A, 0x3FA56C, 0xC48A1A, 0x5A8EF2, 0xA674E0, 0x2BA7B3, 0xFFFFFF,
            ])),
    ]
}
