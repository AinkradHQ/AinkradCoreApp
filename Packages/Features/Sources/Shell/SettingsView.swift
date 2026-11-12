import CoreUI
import Observation
import SwiftUI

public enum SettingsGroup: String, CaseIterable, Sendable {
    case mac = "Mac"
    /// One page per app (Ahmed, 2026-11-05): its look and its defaults.
    case apps = "Apps"
    case core = "Core"
    case security = "Security"
    case notifications = "Notifications"

    /// Each group has its colour on the nav tiles, so the list reads at a glance.
    var hue: Color {
        switch self {
        case .mac: GlassInk.slate
        case .apps: GlassInk.blue
        case .core: GlassInk.blue
        case .security: GlassInk.amber
        case .notifications: GlassInk.blue
        }
    }
}

/// `Mac.settings.section({ id, group, title, icon, order, mount })`.
public struct SettingsSection: Identifiable {
    public let id: String
    public let group: SettingsGroup
    public let title: String
    /// One line under the title: what the section is for.
    public let sub: String?
    public let symbol: String
    public let order: Int
    public let content: AnyView
    public init<V: View>(
        id: String, group: SettingsGroup, title: String, sub: String? = nil, symbol: String, order: Int = 0,
        @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.group = group
        self.sub = sub
        self.title = title
        self.symbol = symbol
        self.order = order
        self.content = AnyView(content())
    }
}

public struct SettingsBack {
    public let title: String
    /// The page's own header (icon, name, badges, lines). When set, the title bar shows it instead of the section's icon,
    /// title and sub-title. Built again on each redraw, so it follows what the page's model says.
    public let header: (@MainActor () -> AnyView)?
    public let run: @MainActor () -> Void
    public init(
        title: String, header: (@MainActor () -> AnyView)? = nil, run: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.header = header
        self.run = run
    }
}

@MainActor @Observable
public final class SettingsRegistry {
    public private(set) var sections: [SettingsSection] = []
    /// Sections this device may not use (no `admin` scope): out of the nav until it can.
    public var hidden: Set<String> = []
    public var selected = "appearance" {
        didSet {
            let ids = grouped().flatMap { $0.1.map(\.id) }
            direction = (ids.firstIndex(of: selected) ?? 0) >= (ids.firstIndex(of: oldValue) ?? 0) ? 1 : -1
        }
    }
    /// Which way the last section change travelled: the content slides a little that way (+1 down the nav, -1 up).
    private(set) var direction: CGFloat = 1
    /// When a setting last changed: the header says "Saved 14:32" for a moment.
    public private(set) var savedAt: Date?
    /// A page inside a section (one device) puts its way back here: the title bar shows it beside the section's icon.
    public var back: SettingsBack?
    /// One-shot arguments for the page being opened (Audit's filter): the page takes them when it shows.
    public var handoff: [String: String] = [:]
    public init() {}
    /// Selects a page and leaves it arguments, for a link that lands on a filtered view.
    public func open(_ id: String, handoff: [String: String]) {
        self.handoff = handoff
        selected = id
    }
    public func saved() { savedAt = Date() }
    public func section(_ s: SettingsSection) {
        sections.removeAll { $0.id == s.id }
        sections.append(s)
    }
    func grouped() -> [(SettingsGroup, [SettingsSection])] {
        SettingsGroup.allCases.compactMap { g in
            let list = sections.filter { $0.group == g && !hidden.contains($0.id) }.sorted { $0.order < $1.order }
            return list.isEmpty ? nil : (g, list)
        }
    }
}

/// The Settings overlay: section nav on the left (groups from the registry), the selected section on the right.
struct SettingsView: View {
    @Bindable var shell: ShellModel
    @Namespace private var glide
    @State private var closeHover = false
    @State private var showSaved = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let current =
            shell.settings.sections.first { $0.id == shell.settings.selected && !shell.settings.hidden.contains($0.id) }
            ?? shell.settings.sections.first { !shell.settings.hidden.contains($0.id) }
        let dir = shell.settings.direction
        HStack(alignment: .top, spacing: 0) {
            GlassScroll {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                            .accessibilityHidden(true)
                        Text("Settings").coreFont(size: MacTextSize.title, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.bottom, Space.s3)
                    ForEach(shell.settings.grouped(), id: \.0) { group, list in
                        Text(group.rawValue).coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(GlassInk.secondary).padding(.top, Space.s3).accessibilityAddTraits(
                                .isHeader)
                        ForEach(list) { s in
                            Button {
                                shell.settings.selected = s.id
                            } label: {
                                navRow(s, selected: s.id == current?.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(s.id == current?.id ? .isSelected : [])
                        }
                    }
                }
                .padding(Space.s5)
                .animation(Motion.calm(Motion.out(0.26), reduce), value: shell.settings.selected)
            }
            .frame(width: Space.s8 * 8)
            .background(GlassInk.adaptive(.black.opacity(0.12), day: .white.opacity(0.25)))
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s4) {
                    if let back = shell.settings.back {
                        SettingsBackTile(back: back).transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    if let header = shell.settings.back?.header {
                        header().transition(.opacity.combined(with: .offset(y: reduce ? 0 : 6 * dir)))
                    } else {
                        if let current {
                            // The section's own icon, large, bouncing in each time the section changes.
                            Image(systemName: current.symbol).font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .coreBounce(current.id)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [current.group.hue, current.group.hue.opacity(0.6)], startPoint: .top,
                                        endPoint: .bottom),
                                    in: coreShape(Radius.control + 4)
                                )
                                .overlay {
                                    coreShape(Radius.control + 4).strokeBorder(.white.opacity(0.25), lineWidth: 1)
                                }
                                .shadow(color: current.group.hue.opacity(0.5), radius: 12)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: Space.s1 / 2) {
                            Text(current?.title ?? "").coreFont(size: MacTextSize.large + 6, weight: .bold)
                                .accessibilityAddTraits(.isHeader)
                            if let sub = current?.sub {
                                Text(sub).foregroundStyle(GlassInk.secondary)
                            }
                        }
                        .id("title-\(current?.id ?? "")")
                        .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 6 * dir)))
                    }
                    Spacer()
                    if showSaved, let at = shell.settings.savedAt {
                        Text("Saved \(at.formatted(date: .omitted, time: .shortened))")
                            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                            .transition(.opacity).accessibilityLabel("Saved")
                    }
                    // The close button turns a quarter on hover (Reduce Motion: no turn).
                    CoreIconButton(symbol: "xmark", label: "Close Settings") { shell.overlay = nil }
                        .rotationEffect(.degrees(closeHover && !reduce ? 90 : 0))
                        .animation(Motion.out(Motion.ui), value: closeHover)
                        .onHover { closeHover = $0 }
                }
                .padding(.trailing, Space.s6)
                // The scroll view runs to the panel's right edge, so its glass bar sits at the edge, not over the cards.
                GlassScroll {
                    current?.content.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, Space.s6)
                        .id("body-\(current?.id ?? "")")
                        .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 10 * dir)))
                }
            }
            .padding([.leading, .top, .bottom], Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Motion.out(reduce ? 0.16 : 0.34), value: current?.id)
            .clipped()
        }
        // Most of the screen (Ahmed, 2026-11-05: larger), in the one frame: a glass rim around the Look's background.
        .foregroundStyle(GlassInk.primary)
        .containerRelativeFrame([.horizontal, .vertical]) { length, _ in length * 0.86 }
        .coreFrame(radius: Radius.panel + Space.s1, part: .settings)
        .shadow(color: GlassInk.shade(0.3), radius: 40, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.95)))
        .task(id: shell.settings.savedAt) {
            guard shell.settings.savedAt != nil else { return }
            withAnimation(Motion.out(Motion.ui)) { showSaved = true }
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(Motion.out(Motion.ui)) { showSaved = false }
        }
    }

    private func navRow(_ s: SettingsSection, selected: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: s.symbol).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(.white)
                .coreBounce(selected)
                .frame(width: MacSize.controlMd + 2, height: MacSize.controlMd + 2)
                .background(
                    LinearGradient(
                        colors: [s.group.hue, s.group.hue.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                    in: coreShape(Radius.control)
                )
                .accessibilityHidden(true)
            // Two lines at large text sizes instead of "Agents and ch…".
            Text(s.title).coreFont(size: MacTextSize.headline, weight: selected ? .semibold : .regular)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(.horizontal, Space.s2)
        .frame(minHeight: MacSize.controlLg + Space.s1)
        // One selection that glides between rows (`s-glide`), not a background swapped per row.
        .background {
            if selected {
                coreShape(Radius.control).fill(GlassInk.lift(0.18))
                    .overlay { coreShape(Radius.control).strokeBorder(GlassInk.rim(0.3), lineWidth: 1) }
                    .matchedGeometryEffect(id: "nav", in: glide)
            }
        }
        .contentShape(coreShape(Radius.control))
    }
}

// MARK: built-in sections

struct SettingsPage<Content: View>: View {
    let intro: String
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(intro).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            content
        }
    }
}

/// The app's own look: Night, Day, Follow the sun (day from 07:00 to 18:00, as the prototype), or follow the Mac's appearance.
public enum ThemeChoice: String, CaseIterable, Sendable {
    case night, day, sun, system
    static let key = "core.theme"
    var title: String {
        switch self {
        case .night: "Night"
        case .day: "Day"
        case .sun: "Follow the sun"
        case .system: "Follow the Mac"
        }
    }
    public var appearance: NSAppearance? { appearance(hour: Calendar.current.component(.hour, from: Date())) }
    func appearance(hour: Int) -> NSAppearance? {
        switch self {
        case .system: nil
        case .day: NSAppearance(named: .aqua)
        case .night: NSAppearance(named: .darkAqua)
        case .sun: NSAppearance(named: (7..<18).contains(hour) ? .aqua : .darkAqua)
        }
    }
    /// The choice that flips what is on the screen: dark now gives Day, light now gives Night. Reads the look shown, not the stored
    /// choice, so "Follow the Mac" on a dark Mac switches on the first push (N10).
    func toggled(isDark: Bool) -> ThemeChoice { isDark ? .day : .night }
    public static func stored(_ defaults: UserDefaults = .standard) -> ThemeChoice {
        #if DEBUG
        // Shot runs: the theme they ask for holds for the whole run (FullScreen re-applies this after the walks set it).
        switch ProcessInfo.processInfo.environment["CORE_THEME"] {
        case "light", "day": return .day
        case "dark", "night": return .night
        default: break
        }
        #endif
        return defaults.string(forKey: key).flatMap(ThemeChoice.init) ?? .system
    }
}

/// A section whose feature module has not landed yet.
struct PlaceholderSection: View {
    let what: String
    var body: some View {
        SettingsPage(intro: "\(what) arrives with its feature module. Nothing to show yet.") { EmptyView() }
    }
}

extension ShellModel {
    func installBuiltInSettings() {
        func later(_ id: String, _ g: SettingsGroup, _ title: String, _ symbol: String, _ order: Int, _ what: String) {
            settings.section(
                SettingsSection(id: id, group: g, title: title, symbol: symbol, order: order) {
                    PlaceholderSection(what: what)
                })
        }
        later("core", .core, "Core settings", "gearshape", 0, "Core settings")
        later("devices", .core, "Devices", "iphone", 1, "Devices")
        later("lockouts", .security, "Lockouts", "lock", 0, "Lockouts")
        later("secrets", .security, "Secrets", "key", 1, "Secrets")
        later("audit", .security, "Audit", "doc.text", 2, "The audit log")
        later("notifications", .notifications, "Notifications", "bell", 0, "Notification settings")
        settings.section(
            SettingsSection(
                id: "you", group: .mac, title: "You", sub: "The name Home greets you with", symbol: "person",
                order: 1
            ) { YouSection(profile: profile) })
        settings.section(
            SettingsSection(
                id: "appearance", group: .mac, title: "Appearance", sub: "Night, day, or with the sun",
                symbol: "circle.lefthalf.filled"
            ) { AppearanceSection(shell: self) })
        settings.section(
            SettingsSection(
                id: "clocks", group: .mac, title: "Clocks", sub: "The second hand and seconds on Home", symbol: "clock",
                order: 2
            ) { ClockSettings() })
    }
}

/// Back from a page to its list, in the title bar beside the section's icon: a glass tile whose arrow slides left and
/// bounces on hover. ⌘← does the same.
private struct SettingsBackTile: View {
    let back: SettingsBack
    @Environment(\.layoutDirection) private var direction
    @State private var hovering = false
    var body: some View {
        Button {
            back.run()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.backward").font(.system(size: 18, weight: .semibold))
                    .offset(x: hovering ? (direction == .rightToLeft ? 3 : -3) : 0)
                    .coreBounce(hovering)
                Text(back.title).coreFont(size: 10, weight: .medium).lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(width: 72, height: 56)
            .background(GlassInk.lift(hovering ? 0.16 : 0.1), in: coreShape(Radius.control + 4))
            .overlay { coreShape(Radius.control + 4).strokeBorder(GlassInk.rim(0.18), lineWidth: 1) }
            .contentShape(coreShape(Radius.control + 4))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .coreScaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("Back to \(back.title)")
    }
}
