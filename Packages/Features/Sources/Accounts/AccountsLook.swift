import CoreUI
import Observation
import SwiftUI

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
