import AppKit
import CoreUI
import Observation
import SwiftUI

/// How the Agents app looks and what the quick New session (⌘N) uses (Settings, Agents; the Appearance popover).
@MainActor @Observable
final class AgentPrefs {
    static let shared = AgentPrefs()

    var harness: String { didSet { save() } }
    var mode: String { didSet { save() } }
    var runner: String { didSet { save() } }  // "" = the best ready runner
    var model: String { didSet { save() } }  // "" = the harness default
    /// The conversation's own text size, on top of the app's Text size (Ahmed, 2026-11-15): 0.9 to 1.5.
    var textScale: Double { didSet { save() } }
    /// The conversation's typeface: system, rounded, serif or mono. Code stays monospaced whatever is chosen.
    var font: String { didSet { save() } }
    /// How long ended sessions stay in the list before they move to the Archive: `week`, `month` or `forever`.
    var keep: String { didSet { save() } }

    private let d = UserDefaults.standard
    private init() {
        harness = Self.harness(d.string(forKey: "agents.harness"))
        mode = d.string(forKey: "agents.mode") ?? "ask"
        runner = d.string(forKey: "agents.runner") ?? ""
        model = d.string(forKey: "agents.model") ?? ""
        textScale = d.object(forKey: "agents.textScale") as? Double ?? 1
        font = d.string(forKey: "agents.font") ?? "system"
        keep = d.string(forKey: "agents.keep") ?? "month"
    }

    /// A saved tool the app no longer offers (agy) falls back to Claude Code, so ⌘N never starts it.
    static func harness(_ saved: String?) -> String {
        saved.flatMap { NewSessionSheet.tools.contains($0) ? $0 : nil } ?? "claude"
    }

    private func save() {
        d.set(harness, forKey: "agents.harness")
        d.set(mode, forKey: "agents.mode")
        d.set(runner, forKey: "agents.runner")
        d.set(model, forKey: "agents.model")
        d.set(textScale, forKey: "agents.textScale")
        d.set(font, forKey: "agents.font")
        d.set(keep, forKey: "agents.keep")
    }
}

extension AgentPrefs {
    static let keeps: [(id: String, title: String, days: Int)] = [
        ("week", "A week", 7), ("month", "A month", 30), ("forever", "Forever", Int.max),
    ]
    /// The days an ended session stays in the list for a choice.
    static func keepDays(_ id: String) -> Int { keeps.first { $0.id == id }?.days ?? 30 }
    var keepDays: Int { Self.keepDays(keep) }

    /// "Ask before running commands": on keeps the Asks first mode (or the one chosen), off starts sessions in the sandbox,
    /// which asks for nothing because it cannot reach beyond its box.
    var asksFirst: Bool {
        get { mode != "sandboxed" }
        set { mode = newValue ? (mode == "sandboxed" ? "ask" : mode) : "sandboxed" }
    }

    static let textScales: [Double] = [0.9, 1, 1.1, 1.25, 1.5]
    static let fonts: [(id: String, title: String)] = [
        ("system", "System"), ("rounded", "Rounded"), ("serif", "Serif"), ("mono", "Mono"),
    ]
    /// The typeface as a SwiftUI design.
    var fontDesign: Font.Design {
        switch font {
        case "rounded": .rounded
        case "serif": .serif
        case "mono": .monospaced
        default: .default
        }
    }
    /// The same typeface for the composer's AppKit text view, at `size` points.
    func nsFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let design: NSFontDescriptor.SystemDesign? =
            switch font {
            case "rounded": .rounded
            case "serif": .serif
            case "mono": .monospaced
            default: nil
            }
        guard let design, let d = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }

    /// The app's Look (E2-6): `AppLookPrefs.shared("agents")`, the same controls as every app.
    var appLook: AppLookPrefs { AppLookPrefs.shared("agents") }
    /// The app's own surface, or nil to follow Settings, Appearance.
    var look: CoreLook? { appLook.look }
}

/// The Agents settings: surface and defaults. Used in Settings and in the Appearance popover.
struct AgentSettingsView: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var prefs = AgentPrefs.shared
    weak var model: AgentsModel?
    var compact = false
    var part: SettingsPart = .all

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s3 : Space.s4) {
            if part.showsLook {
                AppLookSection(appName: "AI Sessions", prefs: prefs.appLook)
                GlassSection(
                    "Text", sub: "The conversation and the message field. Code stays monospaced.", symbol: "textformat",
                    hue: GlassInk.accent(paneAccent), index: 1
                ) {
                    SettingRow("Size", symbol: "textformat.size") {
                        CoreSegmented(
                            "Text size",
                            segments: AgentPrefs.textScales.map {
                                CoreSegment($0, $0.formatted(.percent.precision(.fractionLength(0))))
                            }, selection: $prefs.textScale, fill: true)
                    }
                    SettingRow("Typeface", symbol: "textformat") {
                        CoreSegmented(
                            "Typeface", segments: AgentPrefs.fonts.map { CoreSegment($0.id, $0.title) },
                            selection: $prefs.font, fill: true)
                    }
                    // What the conversation will look like.
                    Text("Two handlers still return 500 instead of 409 on a conflict. Fixing them.")
                        .coreFont(size: MacTextSize.body)
                        .environment(\.coreTextScale, prefs.textScale)
                        .environment(\.coreFontDesign, prefs.fontDesign)
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                }
            }
            if part.showsOptions {
                GlassSection(
                    "Safety", sub: "What new sessions may do, and how long they stay", symbol: "hand.raised",
                    hue: GlassInk.accent(paneAccent), index: 2
                ) {
                    VStack(spacing: Space.s2) {
                        OptionSwitchRow(
                            "Ask before running commands", sub: "Shows what it plans to do first. Off uses the sandbox",
                            symbol: "hand.raised", isOn: $prefs.asksFirst)
                        OptionSelectRow(
                            "Keep sessions for", sub: "Older ended sessions move to the Archive", symbol: "archivebox",
                            selection: $prefs.keep,
                            options: AgentPrefs.keeps.map { CoreSelectOption($0.id, $0.title) })
                    }
                }
                GlassSection(
                    "Defaults", sub: "What New session (⌘N) starts with.", symbol: "gearshape",
                    hue: GlassInk.accent(paneAccent),
                    index: 2
                ) {
                    SettingRow("Harness", symbol: "cpu") {
                        CoreSegmented(
                            "Harness",
                            segments: [
                                CoreSegment("claude", "claude", symbol: "sparkles"),
                                CoreSegment("codex", "codex", symbol: "chevron.left.forwardslash.chevron.right"),
                                CoreSegment("opencode", "opencode", symbol: "curlybraces"),
                                CoreSegment("agy", "agy", symbol: "terminal"),
                            ], selection: $prefs.harness, fill: true)
                    }
                    SettingRow("Mode", symbol: "hand.raised") {
                        CoreSegmented(
                            "Mode",
                            segments: [
                                CoreSegment("ask", "Asks first", symbol: "questionmark.bubble"),
                                CoreSegment("accept_edits", "Accepts edits", symbol: "pencil.and.list.clipboard"),
                                CoreSegment("sandboxed", "Sandboxed", symbol: "shippingbox"),
                            ], selection: $prefs.mode, fill: true)
                    }
                    SettingRow("Runner", symbol: "server.rack") {
                        CoreSegmented(
                            "Runner",
                            segments: [CoreSegment("", "Best ready", symbol: "wand.and.stars")]
                                + (model?.runners ?? []).map { CoreSegment($0.id, $0.name, symbol: "server.rack") },
                            selection: $prefs.runner, fill: true)
                    }
                    SettingRow("Model", symbol: "brain") {
                        ModelField(text: $prefs.model)
                    }
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}

/// The model name as a glass field: a sparkle that bounces while typing, a clear tile once something is set.
private struct ModelField: View {
    @Environment(\.coreAccent) private var paneAccent
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: text.isEmpty ? "sparkles" : "brain.head.profile")
                .foregroundStyle(text.isEmpty ? GlassInk.secondary : GlassInk.accent(paneAccent))
                .contentTransition(.symbolEffect(.replace)).coreBounce(text.count)
            TextField("The harness default", text: $text).textFieldStyle(.plain).focused($focused)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark").coreFont(size: 10, weight: .bold).frame(width: 22, height: 22)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                }
                .buttonStyle(.plain).help("Use the harness default").transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 4)
        .coreFieldSurface(focused: focused)
        .focusEffectDisabled()
        .animation(Motion.out(Motion.ui), value: text.isEmpty)
    }
}
