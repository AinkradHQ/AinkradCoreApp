import CoreUI
import Observation
import SwiftUI

/// How the Core (Accounts) app looks, like every other app's Look (Settings, Apps): one style, blur and opacity.
@MainActor @Observable
final class AccountsPrefs {
    static let shared = AccountsPrefs()
    var style: AppSurfaceStyle { didSet { save() } }
    var blur: Bool { didSet { save() } }
    var opacity: Double { didSet { save() } }

    private let d = UserDefaults.standard
    private init() {
        style = AppSurfaceStyle(rawValue: d.string(forKey: "accounts.surface") ?? "") ?? .tinted
        blur = d.object(forKey: "accounts.blur") as? Bool ?? true
        opacity = d.object(forKey: "accounts.opacity") as? Double ?? 0.6
    }
    private func save() {
        d.set(style.rawValue, forKey: "accounts.surface")
        d.set(blur, forKey: "accounts.blur")
        d.set(opacity, forKey: "accounts.opacity")
    }

    var mode: Binding<SurfaceMode> {
        Binding(
            get: { SurfaceMode(style: self.style, blur: self.blur) },
            set: {
                self.style = $0.style
                self.blur = $0.blur
            })
    }
}

/// The app's surface inside the pane's glass rim, tinted teal.
struct AccountsSurface: View {
    @Bindable var prefs = AccountsPrefs.shared
    var body: some View {
        AppSurfaceFill(
            style: prefs.style, opacity: prefs.opacity, tint: Color(red: 0.03, green: 0.13, blue: 0.15),
            blur: prefs.blur)
    }
}

/// Each provider in its own colour and mark, so its accounts tell apart at a glance.
enum ProviderLook {
    static func hue(_ provider: String) -> Color {
        switch provider {
        case "anthropic": GlassInk.orange
        case "openai": GlassInk.green
        case "google", "gemini": GlassInk.blue
        default: GlassInk.violet
        }
    }
    static func symbol(_ provider: String) -> String {
        switch provider {
        case "anthropic": "sparkles"
        case "openai": "chevron.left.forwardslash.chevron.right"
        case "google", "gemini": "diamond"
        default: "key.fill"
        }
    }
}
