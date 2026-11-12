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
    /// Use Settings, Appearance's content background (the default) instead of the app's own.
    var followLook: Bool { didSet { save() } }

    private let d = UserDefaults.standard
    private init() {
        style = AppSurfaceStyle(rawValue: d.string(forKey: "accounts.surface") ?? "") ?? .tinted
        blur = d.object(forKey: "accounts.blur") as? Bool ?? true
        opacity = d.object(forKey: "accounts.opacity") as? Double ?? 0.6
        followLook = d.object(forKey: "accounts.followLook") as? Bool ?? true
    }
    private func save() {
        d.set(style.rawValue, forKey: "accounts.surface")
        d.set(blur, forKey: "accounts.blur")
        d.set(opacity, forKey: "accounts.opacity")
        d.set(followLook, forKey: "accounts.followLook")
    }
}

extension AccountsPrefs {
    /// The app's own Look, or nil to follow Settings, Appearance.
    var look: CoreLook? { followLook ? nil : CoreLook(mode: modeChoice, opacity: opacity) }
    var modeChoice: SurfaceMode {
        get { SurfaceMode(style: style, blur: blur) }
        set {
            style = newValue.style
            blur = newValue.blur
        }
    }
}

/// Each provider in its own colour and mark, so its accounts tell apart at a glance.
enum ProviderLook {
    static func hue(_ provider: String) -> Color {
        switch provider {
        case "anthropic", "claude-sub": GlassInk.blue
        case "openai": GlassInk.blue
        case "google", "gemini": GlassInk.blue
        default: GlassInk.blue
        }
    }
    /// The brand on a choice card; how it signs in is the line under it.
    static func short(_ provider: String, _ name: String) -> String {
        switch provider {
        case "anthropic", "claude-sub": "Claude"
        case "openai": "OpenAI"
        case "google", "gemini": "Gemini"
        default: name
        }
    }
    /// Choice order: Claude's two ways side by side, then the rest as Core lists them.
    static func ordered(_ ps: [ProviderItem]) -> [ProviderItem] {
        let rank = ["anthropic": 0, "claude-sub": 1]
        return ps.enumerated().sorted {
            (rank[$0.element.id] ?? 2 + $0.offset) < (rank[$1.element.id] ?? 2 + $1.offset)
        }
        .map(\.element)
    }
    static func symbol(_ provider: String) -> String {
        switch provider {
        case "anthropic": "sparkles"
        case "claude-sub": "person.crop.circle.badge.checkmark"
        case "openai": "chevron.left.forwardslash.chevron.right"
        case "google", "gemini": "diamond"
        default: "key.fill"
        }
    }
}
