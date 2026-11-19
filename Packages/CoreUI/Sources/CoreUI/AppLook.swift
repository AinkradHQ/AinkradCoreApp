import Observation
import SwiftUI

/// One app's Look (E2-5): it follows Settings, Appearance until "Same as Appearance" is switched off, then the app keeps its own
/// theme (Night or Day) and accent. Stored per app in UserDefaults under `applook.<app>.*`.
@MainActor @Observable
public final class AppLookPrefs {
    private static var all: [String: AppLookPrefs] = [:]
    /// The one instance for an app id ("design", "projects", "lore", "leyline"), so Settings and the pane share state.
    public static func shared(_ app: String) -> AppLookPrefs {
        if let p = all[app] { return p }
        let p = AppLookPrefs(app: app)
        all[app] = p
        return p
    }

    /// Own theme: false is Night, true is Day.
    public var day: Bool { didSet { d.set(day, forKey: key("day")); Self.notify() } }
    public var accent: CoreAccent { didSet { d.set(accent.rawValue, forKey: key("accent")); Self.notify() } }
    /// True while the app uses its own theme and accent instead of Appearance's (the default is false: it follows).
    public var own: Bool { didSet { d.set(own, forKey: key("own")); Self.notify() } }
    /// Own surface (E2-6): Blurred, Clear or Solid, how solid it is (0.05 to 1) and how soft the glass is (0 to 1).
    /// They start at Appearance's values. Used while `own` is on.
    public var mode: SurfaceMode { didSet { d.set(mode.rawValue, forKey: key("mode")); Self.notify() } }
    public var opacity: Double { didSet { d.set(opacity, forKey: key("opacity")); Self.notify() } }
    public var blur: Double { didSet { d.set(blur, forKey: key("blur")); Self.notify() } }

    /// Posted on every change, for surfaces drawn outside SwiftUI (the terminal screen).
    public static let changed = Notification.Name("ainkrad.applook")
    private static func notify() { NotificationCenter.default.post(name: changed, object: nil) }

    private let app: String
    @ObservationIgnored private let d: UserDefaults
    private func key(_ k: String) -> String { "applook.\(app).\(k)" }

    public init(app: String, defaults: UserDefaults = .standard) {
        self.app = app
        d = defaults
        let p = "applook.\(app)."
        own = defaults.object(forKey: p + "own") as? Bool ?? false
        day = defaults.object(forKey: p + "day") as? Bool ?? false
        accent = CoreAccent(rawValue: defaults.string(forKey: p + "accent") ?? "") ?? .graphite
        mode = SurfaceMode(rawValue: defaults.string(forKey: p + "mode") ?? "") ?? LookPrefs.shared.mode
        opacity = defaults.object(forKey: p + "opacity") as? Double ?? LookPrefs.shared.opacity
        blur = defaults.object(forKey: p + "blur") as? Double ?? LookPrefs.shared.blur
        if defaults.object(forKey: p + "own") == nil, let old = Self.legacy[app] { adopt(old) }
    }

    /// Where Terminal, AI Sessions, Brain and Accounts kept their own surface before E2-6: `<prefix>.followLook`,
    /// `<prefix>.<surface>`, `<prefix>.blur` (a Bool) and `<prefix>.opacity`.
    struct Legacy: Sendable {
        let prefix: String
        let surface: String
    }
    static let legacy: [String: Legacy] = [
        "terminal": Legacy(prefix: "terminal", surface: "screen"),
        "agents": Legacy(prefix: "agents", surface: "surface"),
        "brain": Legacy(prefix: "brain", surface: "surface"),
        "accounts": Legacy(prefix: "accounts", surface: "surface"),
    ]

    /// Read the old keys once, so nobody loses a setting; the new keys are written, so this never runs twice.
    private func adopt(_ old: Legacy) {
        let k = old.prefix + "."
        guard let follow = d.object(forKey: k + "followLook") as? Bool else { return }
        let solid = d.string(forKey: k + old.surface) == "solid"
        let blurs = d.object(forKey: k + "blur") as? Bool ?? true
        own = !follow
        mode = solid ? .solid : blurs ? .blurred : .clear
        if let o = d.object(forKey: k + "opacity") as? Double { opacity = o }
        // didSet does not run inside init, so store what was adopted.
        d.set(own, forKey: key("own"))
        d.set(mode.rawValue, forKey: key("mode"))
        d.set(opacity, forKey: key("opacity"))
    }

    /// The app's own surface, or nil to follow Settings, Appearance.
    public var look: CoreLook? { own ? CoreLook(mode: mode, opacity: opacity, blur: blur) : nil }

    /// The accent this app shows: its own while "Same as Appearance" is off, else nil (the global accent).
    public var ownAccent: CoreAccent? { own ? accent : nil }

    /// The palette the app forces, or nil to follow Appearance.
    public var palette: Palette? { own ? (day ? .day : .night) : nil }
}

extension View {
    /// An app pane that draws no background of its own, with the app's Look applied: Appearance's by default, the app's own
    /// theme once "Same as Appearance" is off. Replaces `.paneLook(nil, own: true)`.
    public func appLook(_ prefs: AppLookPrefs) -> some View {
        modifier(AppLookModifier(prefs: prefs))
    }
}

private struct AppLookModifier: ViewModifier {
    let prefs: AppLookPrefs
    func body(content: Content) -> some View {
        content.appLookTheme(prefs).paneLook(nil, own: true)
    }
}

extension View {
    /// Only the app's own theme (when "Same as Appearance" is off), for a pane that keeps the background the shell gives it.
    public func appLookTheme(_ prefs: AppLookPrefs) -> some View {
        modifier(AppLookThemeModifier(prefs: prefs))
    }
}

private struct AppLookThemeModifier: ViewModifier {
    let prefs: AppLookPrefs
    @Environment(\.corePalette) private var inherited
    @Environment(\.coreLook) private var inheritedLook
    func body(content: Content) -> some View {
        // The accent rides on the palette (`btnPrimary`, `primary`) and on `coreAccent` (switches, selections, tints).
        let accent = prefs.ownAccent
        var palette = prefs.palette ?? inherited
        palette.accent = accent
        return themed(content, prefs.palette)
            .environment(\.coreAccent, accent)
            .environment(\.corePalette, palette)
            .environment(\.coreLook, prefs.look ?? inheritedLook)
            .tint(GlassInk.accent(accent))
    }

    @ViewBuilder private func themed(_ content: Content, _ own: Palette?) -> some View {
        if let own {
            content.environment(\.colorScheme, own.isDay ? .light : .dark).foregroundStyle(own.text)
        } else {
            content
        }
    }
}

/// The "Look" group of an app's settings page: a "Same as Appearance" switch, and when it is off a Theme control and the accents.
public struct AppLookSection: View {
    let appName: String
    @Bindable var prefs: AppLookPrefs

    public init(appName: String, prefs: AppLookPrefs) {
        self.appName = appName
        self.prefs = prefs
    }

    public var body: some View {
        GlassSection("Look", symbol: "circle.lefthalf.filled", hue: GlassInk.blue) {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreRow(
                    "Same as Appearance", subtitle: "\(appName) uses your theme, accent and wallpaper", symbol: "sparkles"
                ) {
                    CoreSwitch(isOn: Binding(get: { !prefs.own }, set: { prefs.own = !$0 }))
                }
                if prefs.own {
                    CoreRow("Theme") {
                        CoreSegmented(
                            "Theme", segments: [CoreSegment(false, "Night"), CoreSegment(true, "Day")],
                            selection: $prefs.day)
                    }
                    CoreRow("Surface") {
                        SurfaceModeTabs(mode: $prefs.mode)
                    }
                    if prefs.mode != .solid {
                        GlassSlider(value: $prefs.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                    }
                    if prefs.mode == .blurred {
                        GlassSlider(value: $prefs.blur, in: 0...1, low: "Sharp", high: "Soft")
                    }
                    HStack(spacing: Space.s3) {
                        ForEach(CoreAccent.allCases, id: \.self) { a in
                            Button {
                                prefs.accent = a
                            } label: {
                                coreShape(Radius.control).fill(a.fill).frame(width: 40, height: 28)
                                    .overlay {
                                        if prefs.accent == a {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(a.title)
                            .accessibilityAddTraits(prefs.accent == a ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}
