import Observation
import SwiftUI

/// What sits inside every glass rim (Ahmed, 2026-11-06): the content background of every pane, card, dialog, pop-up and
/// menu. Settings, Appearance holds the one for the whole app; an app's own settings may replace it for that app.
public struct CoreLook: Equatable, Sendable {
    public var mode: SurfaceMode
    /// 0.05 (almost clear) to 1 (solid).
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

/// The kinds of framed surface, each of which may set its own Look in Settings, Appearance, Advanced.
public enum LookPart: String, CaseIterable, Sendable {
    case panes, launcher, dialogs, popups, dropdowns, settings
    public var title: String {
        switch self {
        case .panes: "Panes"
        case .launcher: "Launcher"
        case .dialogs: "Dialogs"
        case .popups: "Pop-ups"
        case .dropdowns: "Menus"
        case .settings: "Settings"
        }
    }
    public var symbol: String {
        switch self {
        case .panes: "rectangle.split.2x1"
        case .launcher: "magnifyingglass"
        case .dialogs: "rectangle.portrait.on.rectangle.portrait"
        case .popups: "bell"
        case .dropdowns: "filemenu.and.selection"
        case .settings: "gearshape"
        }
    }
    public var sub: String {
        switch self {
        case .panes: "Every app's pane"
        case .launcher: "⌘K and the app switcher"
        case .dialogs: "Confirmations, sheets and forms"
        case .popups: "Notifications, admin unlock, overview"
        case .dropdowns: "A pane's tab menu"
        case .settings: "This window"
        }
    }
}

/// Settings, Appearance, Content background: the Look every surface uses unless its app replaces it.
@MainActor @Observable
public final class LookPrefs {
    public static let shared = LookPrefs()
    public var mode: SurfaceMode { didSet { save() } }
    public var opacity: Double { didSet { save() } }
    /// Advanced: a part's own Look; a part that is missing follows the content background.
    public private(set) var custom: [LookPart: CoreLook]
    /// Posted on every change, for surfaces drawn outside SwiftUI (the terminal screen).
    public static let changed = Notification.Name("ainkrad.look")

    private let d = UserDefaults.standard
    private init() {
        mode = SurfaceMode(rawValue: d.string(forKey: "look.mode") ?? "") ?? CoreLook.standard.mode
        opacity = d.object(forKey: "look.opacity") as? Double ?? CoreLook.standard.opacity
        var c: [LookPart: CoreLook] = [:]
        for part in LookPart.allCases {
            if let m = SurfaceMode(rawValue: d.string(forKey: "look.\(part.rawValue).mode") ?? "") {
                c[part] = CoreLook(
                    mode: m, opacity: d.object(forKey: "look.\(part.rawValue).opacity") as? Double ?? 0.6)
            }
        }
        custom = c
    }
    private func save() {
        d.set(mode.rawValue, forKey: "look.mode")
        d.set(opacity, forKey: "look.opacity")
        for part in LookPart.allCases {
            d.set(custom[part]?.mode.rawValue, forKey: "look.\(part.rawValue).mode")
            d.set(custom[part]?.opacity, forKey: "look.\(part.rawValue).opacity")
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    public var look: CoreLook { CoreLook(mode: mode, opacity: opacity) }
    /// The Look a part draws with: its own, or the content background.
    public func look(for part: LookPart) -> CoreLook { custom[part] ?? look }
    /// Give a part its own Look, or nil to follow the content background again.
    public func setCustom(_ part: LookPart, _ look: CoreLook?) {
        custom[part] = look
        save()
    }
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
    /// `part` lets Settings, Appearance, Advanced give this kind of surface its own Look; nil uses the Look in force.
    public func coreFrame(
        radius: CGFloat = Radius.pane, rim: CGFloat = Space.s2, active: Bool = false, part: LookPart? = nil
    ) -> some View {
        modifier(FrameModifier(radius: radius, rim: rim, active: active, part: part, fill: true))
    }

    /// The frame without its background, for content that draws its own (the terminal screen). Same structure as
    /// `coreFrame`, so switching between the two never rebuilds the content.
    func coreFrame(radius: CGFloat, rim: CGFloat, active: Bool, fill: Bool) -> some View {
        modifier(FrameModifier(radius: radius, rim: rim, active: active, part: nil, fill: fill))
    }
}

private struct FrameModifier: ViewModifier {
    let radius: CGFloat
    let rim: CGFloat
    let active: Bool
    let part: LookPart?
    let fill: Bool
    @Environment(\.coreLook) private var inForce
    @Environment(\.corePalette) private var palette
    func body(content: Content) -> some View {
        let prefs = LookPrefs.shared
        // The rim is clear glass; over the night sky (and a dimmed scrim) it went dark and vanished, so it gets a light
        // lift and a brighter edge at night (the screenshot review, 2026-11-06).
        let lift = palette.isDay ? 0.04 : 0.1
        let edge = active ? 0.34 : palette.isDay ? 0.14 : 0.22
        let look = part.flatMap { prefs.custom[$0] } ?? inForce
        content
            .foregroundStyle(GlassInk.primary)
            .background { if fill { AppSurfaceFill(look, radius: max(radius - rim, Radius.chip)) } }
            .clipShape(coreShape(max(radius - rim, Radius.chip)))
            .padding(rim)
            // The lift lights the rim only: under the content it washed the blurred background out to grey (Ahmed,
            // 2026-11-06: "darker and gray", compared side by side with the build before the frame).
            .background { coreShape(radius).strokeBorder(Color.white.opacity(lift), lineWidth: rim) }
            .coreGlass(radius: radius, interactive: false, tinted: false)
            .overlay { coreShape(radius).strokeBorder(.white.opacity(edge), lineWidth: 1) }
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
    let followTitle: String
    private enum Choice: Hashable {
        case appearance
        case own(SurfaceMode)
    }
    public init(follow: Binding<Bool>, mode: Binding<SurfaceMode>, followTitle: String = "Appearance") {
        self._follow = follow
        self._mode = mode
        self.followTitle = followTitle
    }
    public var body: some View {
        CoreSegmented(
            "Look",
            segments: [
                CoreSegment(Choice.appearance, followTitle, symbol: "paintpalette"),
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
