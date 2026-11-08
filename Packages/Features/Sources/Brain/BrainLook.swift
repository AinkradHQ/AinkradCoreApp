import CoreUI
import Observation
import SwiftUI

/// How the Brain looks, like every other app's Look (Settings, Apps): follow Appearance or its own style, blur and opacity.
/// The pane draws it with the shared surface fill and tint, so the same settings look the same in every Core app.
@MainActor @Observable
final class BrainPrefs {
    static let shared = BrainPrefs()
    var style: AppSurfaceStyle { didSet { save() } }
    var blur: Bool { didSet { save() } }
    var opacity: Double { didSet { save() } }
    /// Use Settings, Appearance's content background (the default) instead of the app's own.
    var followLook: Bool { didSet { save() } }

    private let d = UserDefaults.standard
    private init() {
        style = AppSurfaceStyle(rawValue: d.string(forKey: "brain.surface") ?? "") ?? .tinted
        blur = d.object(forKey: "brain.blur") as? Bool ?? true
        opacity = d.object(forKey: "brain.opacity") as? Double ?? 0.6
        followLook = d.object(forKey: "brain.followLook") as? Bool ?? true
    }
    private func save() {
        d.set(style.rawValue, forKey: "brain.surface")
        d.set(blur, forKey: "brain.blur")
        d.set(opacity, forKey: "brain.opacity")
        d.set(followLook, forKey: "brain.followLook")
    }

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

/// Settings, Apps, Brain: the Look and a way in.
struct BrainLookSection: View {
    let model: BrainModel
    @Bindable private var prefs = BrainPrefs.shared
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Look", sub: "The Brain's content background.", symbol: "circle.lefthalf.filled", hue: GlassInk.blue
            ) {
                AppLookTabs(follow: $prefs.followLook, mode: $prefs.modeChoice)
            } content: {
                if prefs.followLook {
                    Text("Same as Settings, Appearance.").font(.system(size: MacTextSize.meta))
                        .foregroundStyle(GlassInk.secondary)
                } else {
                    GlassSlider(value: $prefs.opacity, in: 0.05...1, low: "See-through", high: "Solid")
                }
            }
            GlassSection(
                "The Brain", sub: "Rooms of memory, kept sealed apart.", symbol: "brain", hue: GlassInk.blue, index: 1
            ) {
                AppActionTile(
                    title: "Open", symbol: "arrow.up.forward.app", key: "", hue: GlassInk.blue, prominent: true
                ) {
                    model.host.shell.overlay = nil
                    model.show(.overview)
                }
            } content: {
                EmptyView()
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
