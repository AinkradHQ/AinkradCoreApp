import CoreUI
import Observation
import SwiftUI

/// How the Agents app looks and what the quick New session (⌘N) uses (Settings, Agents; the Appearance popover).
@MainActor @Observable
final class AgentPrefs {
    static let shared = AgentPrefs()

    enum Surface: String, CaseIterable { case clear, frosted, tinted, solid }
    var surface: Surface { didSet { save() } }
    /// How solid the surface is, 0 (see-through) to 1.
    var opacity: Double { didSet { save() } }
    var blur: Bool { didSet { save() } }
    /// Use Settings, Appearance's content background (the default) instead of the app's own.
    var followLook: Bool { didSet { save() } }
    var harness: String { didSet { save() } }
    var mode: String { didSet { save() } }
    var runner: String { didSet { save() } }  // "" = the best ready runner
    var model: String { didSet { save() } }  // "" = the harness default

    private let d = UserDefaults.standard
    private init() {
        surface =
            Surface(rawValue: d.string(forKey: "agents.surface") ?? "").map { $0 == .frosted ? .clear : $0 } ?? .clear
        opacity = d.object(forKey: "agents.opacity") as? Double ?? 0.55
        blur = d.object(forKey: "agents.blur") as? Bool ?? true
        followLook = d.object(forKey: "agents.followLook") as? Bool ?? true
        harness = d.string(forKey: "agents.harness") ?? "claude"
        mode = d.string(forKey: "agents.mode") ?? "ask"
        runner = d.string(forKey: "agents.runner") ?? ""
        model = d.string(forKey: "agents.model") ?? ""
    }

    private func save() {
        d.set(surface.rawValue, forKey: "agents.surface")
        d.set(opacity, forKey: "agents.opacity")
        d.set(blur, forKey: "agents.blur")
        d.set(followLook, forKey: "agents.followLook")
        d.set(harness, forKey: "agents.harness")
        d.set(mode, forKey: "agents.mode")
        d.set(runner, forKey: "agents.runner")
        d.set(model, forKey: "agents.model")
    }
}

extension AgentPrefs {
    /// The app's own Look, or nil to follow Settings, Appearance.
    var look: CoreLook? { followLook ? nil : CoreLook(mode: modeChoice, opacity: opacity) }
    var modeChoice: SurfaceMode {
        get { SurfaceMode(style: AppSurfaceStyle(rawValue: surface.rawValue) ?? .tinted, blur: blur) }
        set {
            surface = Surface(rawValue: newValue.style.rawValue) ?? .tinted
            blur = newValue.blur
        }
    }
}

/// The Agents settings: surface and defaults. Used in Settings and in the Appearance popover.
struct AgentSettingsView: View {
    @Bindable var prefs = AgentPrefs.shared
    weak var model: AgentsModel?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s3 : Space.s4) {
            GlassSection(
                "Look", sub: "The AI Sessions app and its sessions, as one.", symbol: "square.on.square",
                hue: GlassInk.violet
            ) {
                AppLookTabs(follow: $prefs.followLook, mode: $prefs.modeChoice)
            } content: {
                if prefs.followLook {
                    Text("Same as Settings, Appearance.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                } else {
                    GlassSlider(value: $prefs.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                }
            }
            GlassSection(
                "Defaults", sub: "What New session (⌘N) starts with.", symbol: "gearshape", hue: GlassInk.green,
                index: 1
            ) {
                SettingRow("Harness", symbol: "cpu") {
                    CoreSegmented(
                        "Harness",
                        segments: [
                            CoreSegment("claude", "claude", symbol: "sparkles"),
                            CoreSegment("codex", "codex", symbol: "chevron.left.forwardslash.chevron.right"),
                            CoreSegment("opencode", "opencode", symbol: "curlybraces"),
                            CoreSegment("agy", "agy", symbol: "atom"),
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
        .foregroundStyle(GlassInk.primary)
    }
}

/// The model name as a glass field: a sparkle that bounces while typing, a clear tile once something is set.
private struct ModelField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: text.isEmpty ? "sparkles" : "brain.head.profile")
                .foregroundStyle(text.isEmpty ? GlassInk.secondary : GlassInk.violet)
                .contentTransition(.symbolEffect(.replace)).coreBounce(text.count)
            TextField("The harness default", text: $text).textFieldStyle(.plain).focused($focused)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark").coreFont(size: 10, weight: .bold).frame(width: 22, height: 22)
                        .background(GlassInk.well, in: coreShape(6))
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
