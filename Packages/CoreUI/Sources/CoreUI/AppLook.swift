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
    public var day: Bool { didSet { d.set(day, forKey: key("day")) } }
    public var accent: CoreAccent { didSet { d.set(accent.rawValue, forKey: key("accent")) } }
    /// True while the app uses its own theme and accent instead of Appearance's (the default is false: it follows).
    public var own: Bool { didSet { d.set(own, forKey: key("own")) } }

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
    }

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
        Group {
            if let palette = prefs.palette {
                content
                    .environment(\.corePalette, palette)
                    .environment(\.colorScheme, palette.isDay ? .light : .dark)
                    .foregroundStyle(palette.text)
            } else {
                content
            }
        }
        .paneLook(nil, own: true)
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
