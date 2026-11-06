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
    public let run: @MainActor () -> Void
    public init(title: String, run: @escaping @MainActor () -> Void) {
        self.title = title
        self.run = run
    }
}

@MainActor @Observable
public final class SettingsRegistry {
    public private(set) var sections: [SettingsSection] = []
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
    public init() {}
    public func saved() { savedAt = Date() }
    public func section(_ s: SettingsSection) {
        sections.removeAll { $0.id == s.id }
        sections.append(s)
    }
    func grouped() -> [(SettingsGroup, [SettingsSection])] {
        SettingsGroup.allCases.compactMap { g in
            let list = sections.filter { $0.group == g }.sorted { $0.order < $1.order }
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
    @FocusState private var navFocused: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let current =
            shell.settings.sections.first { $0.id == shell.settings.selected } ?? shell.settings.sections.first
        let dir = shell.settings.direction
        HStack(alignment: .top, spacing: 0) {
            GlassScroll {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                            .accessibilityHidden(true)
                        Text("Settings").font(.system(size: MacTextSize.title, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.bottom, Space.s3)
                    ForEach(shell.settings.grouped(), id: \.0) { group, list in
                        Text(group.rawValue).font(.system(size: MacTextSize.body, weight: .semibold))
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
                .animation(Motion.out(reduce ? Motion.hover : Motion.ui), value: shell.settings.selected)
                .focusable().focused($navFocused).focusEffectDisabled()
                .onKeyPress(.upArrow) { moveSection(-1) }
                .onKeyPress(.downArrow) { moveSection(1) }
            }
            .frame(width: Space.s8 * 8)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s4) {
                    if let back = shell.settings.back {
                        SettingsBackTile(back: back).transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    if let current {
                        // The section's own icon, large, bouncing in each time the section changes.
                        Image(systemName: current.symbol).font(.system(size: MacTextSize.large, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: current.id)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: [GlassInk.blue, GlassInk.blue.opacity(0.6)], startPoint: .top,
                                    endPoint: .bottom),
                                in: coreShape(Radius.cardMac)
                            )
                            .overlay { coreShape(Radius.cardMac).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                        Text(current?.title ?? "").font(.system(size: MacTextSize.large, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        if let sub = current?.sub {
                            Text(sub).foregroundStyle(GlassInk.secondary)
                        }
                    }
                    .id("title-\(current?.id ?? "")")
                    .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 6 * dir)))
                    Spacer()
                    if showSaved, let at = shell.settings.savedAt {
                        Text("Saved \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
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
            .animation(Motion.out(reduce ? Motion.hover : Motion.move), value: current?.id)
            .clipped()
        }
        // Most of the screen (Ahmed, 2026-11-05: larger), on the launcher's glass: darker than a widget, frosted at
        // night, clear by day, with white ink.
        .foregroundStyle(GlassInk.primary)
        .containerRelativeFrame([.horizontal, .vertical]) { length, _ in length * 0.86 }
        .background(Color.black.opacity(palette.isDay ? 0.4 : 0.32), in: coreShape(Radius.panel + Space.s1))
        .clipShape(coreShape(Radius.panel + Space.s1))
        .coreGlass(radius: Radius.panel + Space.s1, interactive: false, tinted: false, frosted: !palette.isDay)
        .shadow(color: .black.opacity(0.3), radius: 40, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.95)))
        .onAppear { navFocused = true }
        .task(id: shell.settings.savedAt) {
            guard shell.settings.savedAt != nil else { return }
            withAnimation(Motion.out(Motion.ui)) { showSaved = true }
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(Motion.out(Motion.ui)) { showSaved = false }
        }
    }

    /// ↑ ↓ walk the sections in the order the nav lists them.
    private func moveSection(_ step: Int) -> KeyPress.Result {
        let ids = shell.settings.grouped().flatMap { $0.1.map(\.id) }
        guard let i = ids.firstIndex(of: shell.settings.selected) else { return .ignored }
        shell.settings.selected = ids[min(max(i + step, 0), ids.count - 1)]
        return .handled
    }

    private func navRow(_ s: SettingsSection, selected: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: s.symbol).font(.system(size: MacTextSize.body, weight: .semibold)).foregroundStyle(.white)
                .symbolEffect(.bounce, value: selected)
                .frame(width: MacSize.controlMd + 2, height: MacSize.controlMd + 2)
                .background(
                    LinearGradient(
                        colors: [
                            selected ? GlassInk.blue : GlassInk.slate,
                            (selected ? GlassInk.blue : GlassInk.slate).opacity(0.6),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    in: coreShape(Radius.control)
                )
                .accessibilityHidden(true)
            Text(s.title).font(.system(size: MacTextSize.headline, weight: selected ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(.horizontal, Space.s2)
        .frame(height: MacSize.controlLg + Space.s1)
        // One selection that glides between rows (`s-glide`), not a background swapped per row.
        .background {
            if selected {
                coreShape(Radius.control).fill(.white.opacity(0.18))
                    .overlay { coreShape(Radius.control).strokeBorder(.white.opacity(0.3), lineWidth: 1) }
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
    public static func stored(_ defaults: UserDefaults = .standard) -> ThemeChoice {
        defaults.string(forKey: key).flatMap(ThemeChoice.init) ?? .system
    }
}

/// A section whose feature module has not landed yet.
struct PlaceholderSection: View {
    let what: String
    var body: some View {
        SettingsPage(intro: "Not available yet") { EmptyView() }.help(what)
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
                id: "appearance", group: .mac, title: "Appearance", sub: "Night, day, or with the sun",
                symbol: "circle.lefthalf.filled"
            ) { AppearanceSection(shell: self) })
    }
}

/// Back from a page to its list, in the title bar beside the section's icon: a glass tile whose arrow slides left and
/// nudges on hover. ⌘← does the same.
private struct SettingsBackTile: View {
    let back: SettingsBack
    @State private var hovering = false
    var body: some View {
        Button {
            back.run()
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "chevron.left").font(.system(size: MacTextSize.large, weight: .semibold))
                    .offset(x: hovering ? -3 : 0)
                Text(back.title).font(.system(size: MacTextSize.meta, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            .frame(width: 72, height: 56)
            .background(.white.opacity(hovering ? 0.16 : 0.1), in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel("Back to \(back.title)")
    }
}
