import CoreUI
import Observation
import SwiftUI

public enum SettingsGroup: String, CaseIterable, Sendable {
    case mac = "Mac"
    case core = "Core"
    case security = "Security"
    case notifications = "Notifications"
    case appearance = "Appearance"
}

/// `Mac.settings.section({ id, group, title, icon, order, mount })`.
public struct SettingsSection: Identifiable {
    public let id: String
    public let group: SettingsGroup
    public let title: String
    public let symbol: String
    public let order: Int
    public let content: AnyView
    public init<V: View>(
        id: String, group: SettingsGroup, title: String, symbol: String, order: Int = 0, @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.symbol = symbol
        self.order = order
        self.content = AnyView(content())
    }
}

@MainActor @Observable
public final class SettingsRegistry {
    public private(set) var sections: [SettingsSection] = []
    public var selected = "appearance"
    public init() {}
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
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let current =
            shell.settings.sections.first { $0.id == shell.settings.selected } ?? shell.settings.sections.first
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
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
                            .foregroundStyle(palette.text2).padding(.top, Space.s3).accessibilityAddTraits(.isHeader)
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
            }
            .frame(width: Space.s8 * 8)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top) {
                    Text(current?.title ?? "").font(.system(size: MacTextSize.large, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    CoreIconButton(symbol: "xmark", label: "Close Settings") { shell.overlay = nil }
                }
                ScrollView { current?.content.frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: ShellMetrics.settingsSize.width, height: ShellMetrics.settingsSize.height)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
        .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
    }

    private func navRow(_ s: SettingsSection, selected: Bool) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: s.symbol).frame(width: MacSize.controlMd).accessibilityHidden(true)
            Text(s.title).font(.system(size: MacTextSize.headline))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2)
        .frame(height: MacSize.controlLg)
        .background(selected ? palette.navActive : .clear, in: coreShape(Radius.control))
        .overlay { if selected { coreShape(Radius.control).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
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

struct SettingsValueRow: View {
    let title: String
    let detail: String
    let value: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Text(value).font(.system(size: MacTextSize.body, weight: .medium))
        }
        .padding(Space.s3)
        .frame(maxWidth: Space.s8 * 16)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .accessibilityElement(children: .combine)
    }
}

/// The app's own Day/Night choice. It sets the app's appearance, so it overrides System Settings; "System" follows the Mac again.
public enum ThemeChoice: String, CaseIterable, Sendable {
    case system, day, night
    static let key = "core.theme"
    var title: String { rawValue.capitalized }
    public var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .day: NSAppearance(named: .aqua)
        case .night: NSAppearance(named: .darkAqua)
        }
    }
    public static func stored(_ defaults: UserDefaults = .standard) -> ThemeChoice {
        defaults.string(forKey: key).flatMap(ThemeChoice.init) ?? .system
    }
}

struct AppearanceSection: View {
    @Bindable var shell: ShellModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        SettingsPage(intro: "Pick Day or Night, or let Ainkrad Core follow your Mac. Your choice is remembered.") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Theme").font(.system(size: MacTextSize.headline, weight: .semibold))
                CoreSegmented(
                    "Theme", segments: ThemeChoice.allCases.map { CoreSegment($0, $0.title) },
                    selection: $shell.theme
                )
                .frame(maxWidth: Space.s8 * 8)
                Text(shell.theme == .system ? "Following System Settings → Appearance." : "Overrides System Settings.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(.secondary)
            }
            SettingsValueRow(
                title: "Reduce Motion",
                detail: "Set in System Settings → Accessibility → Display. Shown here, not changed.",
                value: reduce ? "On" : "Off")
        }
    }
}

struct WindowSection: View {
    var body: some View {
        SettingsPage(intro: "Ainkrad Core always runs full screen, in its own Space. It cannot be resized or windowed.")
        {
            SettingsValueRow(title: "Window", detail: "One window, full screen.", value: "Full screen")
        }
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
        settings.section(
            SettingsSection(id: "window", group: .mac, title: "Window", symbol: "rectangle.inset.filled") {
                WindowSection()
            })
        later("core", .core, "Core settings", "gearshape", 0, "Core settings")
        later("devices", .core, "Devices", "iphone", 1, "Devices")
        later("lockouts", .security, "Lockouts", "lock", 0, "Lockouts")
        later("secrets", .security, "Secrets", "key", 1, "Secrets")
        later("audit", .security, "Audit", "doc.text", 2, "The audit log")
        later("notifications", .notifications, "Notifications", "bell", 0, "Notification settings")
        settings.section(
            SettingsSection(id: "appearance", group: .appearance, title: "Appearance", symbol: "circle.lefthalf.filled")
            { AppearanceSection(shell: self) })
    }
}
