import CoreUI
import SwiftUI

/// Settings, Apps, Brain, Options (E2-4): the three plain choices of the mockup. "Learn in the background" and "How often to
/// ask me questions" are the Core's AI suggestions switch and strength (`semantic.enabled`, `semantic.strength`); "Remember
/// for" is what a new room keeps its sources for (the room's retention, set right after the room is made).
@MainActor enum BrainOptions {
    static var options: AppOptions { .shared("brain") }
    static let remember = "remember"

    /// The choices and the retention in days each one sets (0 keeps everything).
    static let remembers: [(id: String, title: String, days: Int)] = [
        ("month", "A month", 30), ("year", "A year", 365), ("forever", "Forever", 0),
    ]

    static func days(_ id: String) -> Int { remembers.first { $0.id == id }?.days ?? 0 }

    /// How often Brain asks, as the Core's suggestion strength: fewer, normal, more.
    static let asks: [CoreSegment<Int>] = [
        CoreSegment(0, "Rarely"), CoreSegment(1, "Sometimes"), CoreSegment(2, "Often"),
    ]

    /// Retention for a new room, or nil when it keeps everything (nothing to set).
    static func newRoomRetention(_ id: String) -> Int? {
        let d = days(id)
        return d > 0 ? d : nil
    }
}

struct BrainLearningSection: View {
    @Environment(\.coreAccent) private var paneAccent
    let settings: AISettings
    let options = BrainOptions.options

    var body: some View {
        GlassSection(
            "Learning", sub: "How Brain looks after your notes", symbol: "sparkles", hue: GlassInk.accent(paneAccent)
        ) {
            VStack(spacing: Space.s2) {
                if settings.load == .ready {
                    OptionSwitchRow(
                        "Learn in the background", sub: "Brain tidies notes while you work", symbol: "wand.and.stars",
                        isOn: Binding(
                            get: { settings.enabled },
                            set: { v in Task { await settings.set("semantic.enabled", v ? 1 : 0) } }))
                    OptionSegmentRow(
                        "How often to ask me questions", symbol: "questionmark.bubble",
                        selection: Binding(
                            get: { settings.strength },
                            set: { v in Task { await settings.set("semantic.strength", v) } }),
                        segments: BrainOptions.asks
                    )
                    .disabled(!settings.enabled)
                } else {
                    Text(
                        settings.load == .loading
                            ? "Reading the Core…" : "This Core has no local AI to learn with."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                OptionSelectRow(
                    "Remember for", sub: "How long a new room keeps its sources. Older ones lose their text",
                    symbol: "clock.arrow.circlepath",
                    selection: options.text(BrainOptions.remember, "forever"),
                    options: BrainOptions.remembers.map { CoreSelectOption($0.id, $0.title) })
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await settings.reload() }
    }
}
