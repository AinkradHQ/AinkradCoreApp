import CoreUI
import Observation
import SwiftUI

/// Settings, Apps, Brain: the Core's local AI tunables. The Core owns the values; this reads them and writes one at a
/// time. A change applies from the next re-sort of a review.
@MainActor @Observable
final class AISettings {
    enum Load: Equatable { case loading, ready, missing }
    /// Asked each time, so a Core that reconnects is the one written to.
    private let source: @MainActor () -> BrainRoutes?
    private var routes: BrainRoutes? { source() }
    private(set) var load: Load = .loading
    private(set) var values: [String: Int] = [:]
    var notice: String?

    init(routes: @escaping @MainActor () -> BrainRoutes?) { source = routes }

    var enabled: Bool { (values["semantic.enabled"] ?? 1) == 1 }
    /// 0 fewer (few, sure hints), 1 normal, 2 more (looser hints).
    var strength: Int { values["semantic.strength"] ?? 1 }
    var threads: Int { values["semantic.threads"] ?? 1 }
    /// 128 reads the start of each item; 256 reads more.
    var maxTokens: Int { (values["semantic.max_tokens"] ?? 128) > 128 ? 256 : 128 }

    func reload() async {
        guard let routes else {
            load = .missing
            return
        }
        do {
            let all = try await routes.settings()
            values = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.value) })
            load = values["semantic.enabled"] == nil ? .missing : .ready
        } catch { load = .missing }
    }

    func set(_ name: String, _ value: Int) async {
        guard let routes, values[name] != value else { return }
        let before = values[name]
        values[name] = value
        notice = nil
        do { values[name] = try await routes.setSetting(name, value).value } catch {
            values[name] = before
            notice = BrainWords.failure(error)
        }
    }
}

struct BrainAISection: View {
    let settings: AISettings

    var body: some View {
        GlassSection(
            "AI suggestions", sub: "Runs on your Core. Nothing leaves your server.", symbol: "sparkles",
            hue: GlassInk.blue, index: 2
        ) {
            if settings.load == .ready {
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { settings.enabled },
                        set: { v in Task { await settings.set("semantic.enabled", v ? 1 : 0) } })
                )
                .accessibilityLabel("AI suggestions")
            }
        } content: {
            switch settings.load {
            case .loading:
                Text("Reading the Core…").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            case .missing:
                Text("This Core has no local AI to switch on.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            case .ready:
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let n = settings.notice {
                        Text(n).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.red)
                    }
                    Text(
                        settings.enabled
                            ? "While you review an import, it suggests rooms for what has none, copies to skip, and rooms to merge. You accept each one."
                            : "Off. Reviews show no suggestions."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    if settings.enabled {
                        row(
                            "Strength", "Fewer shows only the sure ones. More also shows looser matches.",
                            "semantic.strength",
                            settings.strength,
                            [CoreSegment(0, "Fewer"), CoreSegment(1, "Normal"), CoreSegment(2, "More")])
                        row(
                            "Speed", "Gentle uses 1 core and keeps the Core calm. Faster uses 2.", "semantic.threads",
                            settings.threads, [CoreSegment(1, "Gentle"), CoreSegment(2, "Faster")])
                        row(
                            "Text read per item", "Short reads the start of each item and is about twice as fast.",
                            "semantic.max_tokens", settings.maxTokens,
                            [CoreSegment(128, "Short"), CoreSegment(256, "Long")])
                        Text("A change applies the next time you re-sort a review.").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
            }
        }
        .task { await settings.reload() }
        .accessibilityIdentifier("brain-ai-settings")
    }

    private func row(_ title: String, _ help: String, _ name: String, _ value: Int, _ segments: [CoreSegment<Int>])
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                Spacer(minLength: Space.s3)
                CoreSegmented(
                    title, segments: segments,
                    selection: Binding(get: { value }, set: { v in Task { await settings.set(name, v) } }))
            }
            Text(help).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }
}
