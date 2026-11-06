import Observation
import SwiftUI

/// What sits inside every glass rim (Ahmed, 2026-11-06): the content background of every pane, card, dialog, pop-up and
/// menu. Settings, Appearance holds the one for the whole app; an app's own settings may replace it for that app.
public struct CoreLook: Equatable, Sendable {
    public var mode: SurfaceMode
    /// 0.4 (see-through) to 1 (solid).
    public var opacity: Double
    public init(mode: SurfaceMode, opacity: Double) {
        self.mode = mode
        self.opacity = opacity
    }
    public static let standard = CoreLook(mode: .blurred, opacity: 0.6)
}

extension EnvironmentValues {
    /// The Look in force here: Appearance's, or the app's own where the app replaces it.
    @Entry public var coreLook: CoreLook = .standard
}

/// Settings, Appearance, Content background: the Look every surface uses unless its app replaces it.
@MainActor @Observable
public final class LookPrefs {
    public static let shared = LookPrefs()
    public var mode: SurfaceMode { didSet { save() } }
    public var opacity: Double { didSet { save() } }
    /// Posted on every change, for surfaces drawn outside SwiftUI (the terminal screen).
    public static let changed = Notification.Name("ainkrad.look")

    private let d = UserDefaults.standard
    private init() {
        mode = SurfaceMode(rawValue: d.string(forKey: "look.mode") ?? "") ?? CoreLook.standard.mode
        opacity = d.object(forKey: "look.opacity") as? Double ?? CoreLook.standard.opacity
    }
    private func save() {
        d.set(mode.rawValue, forKey: "look.mode")
        d.set(opacity, forKey: "look.opacity")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    public var look: CoreLook { CoreLook(mode: mode, opacity: opacity) }
}

/// The content background for the Look in force.
public struct LookFill: View {
    let radius: CGFloat
    @Environment(\.coreLook) private var look
    public init(radius: CGFloat) { self.radius = radius }
    public var body: some View { AppSurfaceFill(look, radius: radius) }
}

extension View {
    /// The one surface style (Ahmed, 2026-11-06, from the terminal pane): a clear Liquid Glass rim, rounded, holding the
    /// content on the Look's background. Panes, dialogs and pop-ups take the wide rim (`Space.s2`); cards and menus the
    /// narrow one (`Space.s1`). The inner corner is the outer one less the rim, so the two curves stay parallel.
    public func coreFrame(radius: CGFloat = Radius.pane, rim: CGFloat = Space.s2, active: Bool = false) -> some View {
        modifier(FrameModifier(radius: radius, rim: rim, active: active))
    }
}

private struct FrameModifier: ViewModifier {
    let radius: CGFloat
    let rim: CGFloat
    let active: Bool
    func body(content: Content) -> some View {
        content
            .foregroundStyle(GlassInk.primary)
            .background { LookFill(radius: max(radius - rim, Radius.chip)) }
            .clipShape(coreShape(max(radius - rim, Radius.chip)))
            .padding(rim)
            .coreGlass(radius: radius, interactive: false, tinted: false)
            .overlay { coreShape(radius).strokeBorder(.white.opacity(active ? 0.3 : 0.12), lineWidth: 1) }
    }
}

/// What a pane's content asks of the pane's background: Appearance's Look, its app's own, or nothing because it draws its
/// own (the terminal screen, which carries its theme's colour).
public enum PaneLook: Equatable, Sendable {
    case inherit
    case look(CoreLook)
    case own
}

public struct PaneLookKey: PreferenceKey {
    public static let defaultValue: PaneLook = .inherit
    public static func reduce(value: inout PaneLook, nextValue: () -> PaneLook) {
        let next = nextValue()
        if next != .inherit { value = next }
    }
}

extension View {
    /// An app's pane content: replace Appearance's Look in this pane (nil keeps it), or `own: true` to draw its own.
    public func paneLook(_ look: CoreLook?, own: Bool = false) -> some View {
        preference(key: PaneLookKey.self, value: own ? .own : look.map(PaneLook.look) ?? .inherit)
    }
}

/// An app's own Look choice (its settings' Look section, top right): Appearance (follow Settings, Appearance) or its own
/// Blurred, Clear or Solid. The slider under it shows only for its own.
public struct AppLookTabs: View {
    @Binding var follow: Bool
    @Binding var mode: SurfaceMode
    private enum Choice: Hashable {
        case appearance
        case own(SurfaceMode)
    }
    public init(follow: Binding<Bool>, mode: Binding<SurfaceMode>) {
        self._follow = follow
        self._mode = mode
    }
    public var body: some View {
        CoreSegmented(
            "Look",
            segments: [
                CoreSegment(Choice.appearance, "Appearance", symbol: "paintpalette"),
                CoreSegment(.own(.blurred), "Blurred", symbol: "drop.halffull"),
                CoreSegment(.own(.clear), "Clear", symbol: "square.dashed"),
                CoreSegment(.own(.solid), "Solid", symbol: "square.fill"),
            ],
            selection: Binding(
                get: { follow ? .appearance : .own(mode) },
                set: {
                    switch $0 {
                    case .appearance: follow = true
                    case .own(let m):
                        mode = m
                        follow = false
                    }
                })
        )
        .help("Appearance uses the content background from Settings, Appearance")
    }
}

extension View {
    /// A card or component inside content (Ahmed, 2026-11-06: the glass frame is only for panes, dialogs, pop-ups and
    /// menus, never for what sits inside them): a plain well with a hairline edge, lit when active.
    public func coreWell(radius: CGFloat = Radius.cardMac, active: Bool = false) -> some View {
        background(active ? GlassInk.wellHover : GlassInk.well, in: coreShape(radius))
            .overlay {
                coreShape(radius).strokeBorder(active ? Color.white.opacity(0.28) : GlassInk.wellEdge, lineWidth: 1)
            }
    }
}
