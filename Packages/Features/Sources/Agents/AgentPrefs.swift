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
    var harness: String { didSet { save() } }
    var mode: String { didSet { save() } }
    var runner: String { didSet { save() } }  // "" = the best ready runner
    var model: String { didSet { save() } }  // "" = the harness default

    private let d = UserDefaults.standard
    private init() {
        surface = Surface(rawValue: d.string(forKey: "agents.surface") ?? "") ?? .frosted
        opacity = d.object(forKey: "agents.opacity") as? Double ?? 0.55
        harness = d.string(forKey: "agents.harness") ?? "claude"
        mode = d.string(forKey: "agents.mode") ?? "ask"
        runner = d.string(forKey: "agents.runner") ?? ""
        model = d.string(forKey: "agents.model") ?? ""
    }

    private func save() {
        d.set(surface.rawValue, forKey: "agents.surface")
        d.set(opacity, forKey: "agents.opacity")
        d.set(harness, forKey: "agents.harness")
        d.set(mode, forKey: "agents.mode")
        d.set(runner, forKey: "agents.runner")
        d.set(model, forKey: "agents.model")
    }
}

/// The Agents app's surface inside the pane's glass rim.
struct AgentSurface: View {
    @Bindable var prefs = AgentPrefs.shared
    var body: some View {
        let shape = coreShape(Radius.cardMac)
        let deep = Color(red: 0.04, green: 0.05, blue: 0.11)
        Group {
            switch prefs.surface {
            case .clear: shape.fill(deep.opacity(prefs.opacity * 0.6))
            case .frosted: shape.fill(.ultraThinMaterial).overlay { shape.fill(deep.opacity(prefs.opacity)) }
            case .tinted:
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(GlassInk.violet.opacity(0.12 + prefs.opacity * 0.25)) }
                    .overlay { shape.fill(deep.opacity(prefs.opacity * 0.6)) }
            case .solid: shape.fill(deep.opacity(0.6 + prefs.opacity * 0.4))
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: prefs.surface)
        .animation(.easeOut(duration: 0.25), value: prefs.opacity)
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
                "App surface", sub: "The Agents app's background.", symbol: "square.on.square", hue: GlassInk.violet
            ) {
                Picker("Surface", selection: $prefs.surface) {
                    Text("Clear").tag(AgentPrefs.Surface.clear)
                    Text("Frosted").tag(AgentPrefs.Surface.frosted)
                    Text("Tinted").tag(AgentPrefs.Surface.tinted)
                    Text("Solid").tag(AgentPrefs.Surface.solid)
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: Space.s3) {
                    Text("Clear").foregroundStyle(GlassInk.secondary)
                    Slider(value: $prefs.opacity, in: 0...1)
                    Text("Solid").foregroundStyle(GlassInk.secondary)
                    Text("\(Int((prefs.opacity * 100).rounded()))%").monospacedDigit().frame(
                        width: 44, alignment: .trailing)
                }
            }
            GlassSection(
                "Defaults", sub: "What New session (⌘N) starts with.", symbol: "gearshape", hue: GlassInk.green,
                index: 1
            ) {
                Picker("Harness", selection: $prefs.harness) {
                    ForEach(["claude", "codex", "opencode", "agy"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Mode", selection: $prefs.mode) {
                    Text("Asks first").tag("ask")
                    Text("Accepts edits").tag("accept_edits")
                    Text("Sandboxed").tag("sandboxed")
                }
                Picker("Runner", selection: $prefs.runner) {
                    Text("Best ready runner").tag("")
                    ForEach(model?.runners ?? []) { r in Text(r.name).tag(r.id) }
                }
                LabeledContent("Model") {
                    TextField("the harness default", text: $prefs.model).textFieldStyle(.roundedBorder).frame(
                        width: 220)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
