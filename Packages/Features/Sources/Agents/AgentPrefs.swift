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
    var harness: String { didSet { save() } }
    var mode: String { didSet { save() } }
    var runner: String { didSet { save() } }  // "" = the best ready runner
    var model: String { didSet { save() } }  // "" = the harness default

    private let d = UserDefaults.standard
    private init() {
        surface = Surface(rawValue: d.string(forKey: "agents.surface") ?? "") ?? .frosted
        opacity = d.object(forKey: "agents.opacity") as? Double ?? 0.55
        blur = d.object(forKey: "agents.blur") as? Bool ?? true
        harness = d.string(forKey: "agents.harness") ?? "claude"
        mode = d.string(forKey: "agents.mode") ?? "ask"
        runner = d.string(forKey: "agents.runner") ?? ""
        model = d.string(forKey: "agents.model") ?? ""
    }

    private func save() {
        d.set(surface.rawValue, forKey: "agents.surface")
        d.set(opacity, forKey: "agents.opacity")
        d.set(blur, forKey: "agents.blur")
        d.set(harness, forKey: "agents.harness")
        d.set(mode, forKey: "agents.mode")
        d.set(runner, forKey: "agents.runner")
        d.set(model, forKey: "agents.model")
    }
}

/// The Agents app's surface inside the pane's glass rim: the same fill as the Terminals app (tinted uses violet).
struct AgentSurface: View {
    @Bindable var prefs = AgentPrefs.shared
    var body: some View {
        AppSurfaceFill(
            style: AppSurfaceStyle(rawValue: prefs.surface.rawValue) ?? .frosted, opacity: prefs.opacity,
            tint: Color(red: 0.1, green: 0.06, blue: 0.22), blur: prefs.blur)
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
                SurfaceStyleTabs(
                    style: Binding(
                        get: { AppSurfaceStyle(rawValue: prefs.surface.rawValue) ?? .frosted },
                        set: { prefs.surface = AgentPrefs.Surface(rawValue: $0.rawValue) ?? .frosted }),
                    tintTitle: "Tinted")
            } content: {
                SurfaceControls(blur: $prefs.blur, opacity: $prefs.opacity)
            }
            GlassSection(
                "Defaults", sub: "What New session (⌘N) starts with.", symbol: "gearshape", hue: GlassInk.green,
                index: 1
            ) {
                CoreSegmented(
                    "Harness", segments: ["claude", "codex", "opencode", "agy"].map { CoreSegment($0, $0) },
                    selection: $prefs.harness, fill: true)
                CoreSegmented(
                    "Mode",
                    segments: [
                        CoreSegment("ask", "Asks first"), CoreSegment("accept_edits", "Accepts edits"),
                        CoreSegment("sandboxed", "Sandboxed"),
                    ], selection: $prefs.mode, fill: true)
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
