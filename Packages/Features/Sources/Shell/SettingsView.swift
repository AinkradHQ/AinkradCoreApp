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
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let current =
            shell.settings.sections.first { $0.id == shell.settings.selected } ?? shell.settings.sections.first
        let dir = shell.settings.direction
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
                .animation(reduce ? nil : Motion.out(0.26), value: shell.settings.selected)
            }
            .frame(width: Space.s8 * 8)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                        Text(current?.title ?? "").font(.system(size: MacTextSize.large, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        if let sub = current?.sub {
                            Text(sub).foregroundStyle(palette.text2)
                        }
                    }
                    .id("title-\(current?.id ?? "")")
                    .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 6 * dir)))
                    Spacer()
                    if showSaved, let at = shell.settings.savedAt {
                        Text("Saved \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                            .transition(.opacity).accessibilityLabel("Saved")
                    }
                    // The close button turns a quarter on hover (Reduce Motion: no turn).
                    CoreIconButton(symbol: "xmark", label: "Close Settings") { shell.overlay = nil }
                        .rotationEffect(.degrees(closeHover && !reduce ? 90 : 0))
                        .animation(Motion.out(Motion.ui), value: closeHover)
                        .onHover { closeHover = $0 }
                }
                ScrollView {
                    current?.content.frame(maxWidth: .infinity, alignment: .leading)
                        .id("body-\(current?.id ?? "")")
                        .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 10 * dir)))
                }
            }
            .padding(Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Motion.out(reduce ? 0.16 : 0.34), value: current?.id)
            .clipped()
        }
        .frame(width: ShellMetrics.settingsSize.width, height: ShellMetrics.settingsSize.height)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
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
        HStack(spacing: Space.s2) {
            Image(systemName: s.symbol).frame(width: MacSize.controlMd).accessibilityHidden(true)
            Text(s.title).font(.system(size: MacTextSize.headline))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2)
        .frame(height: MacSize.controlLg)
        // One selection that glides between rows (`s-glide`), not a background swapped per row.
        .background {
            if selected {
                coreShape(Radius.control).fill(palette.navActive)
                    .overlay { coreShape(Radius.control).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
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

/// A setting with a switch: title, one line of what it does, the switch on the right.
struct SettingsSwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var locked = false
    var identifier: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            // The switch keeps its own accessibility element (labelled with the title), so it can be found and pressed.
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).disabled(locked)
                .accessibilityLabel(title).accessibilityIdentifier(identifier ?? "switch-\(title)")
        }
        .padding(Space.s3)
        .frame(maxWidth: Space.s8 * 16)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .opacity(locked ? 0.7 : 1)
        .accessibilityElement(children: .contain)
    }
}

/// A titled block: heading and one line, then the controls.
struct SettingsBlock<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            content
        }
    }
}

struct AppearanceSection: View {
    @Bindable var shell: ShellModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SettingsBlock(title: "Theme", detail: "The desktop sky and the glass follow it.") {
                HStack(alignment: .top, spacing: Space.s3) {
                    ForEach(ThemeChoice.allCases, id: \.self) { choice in
                        ThemeCard(choice: choice, selected: shell.theme == choice) {
                            shell.theme = choice
                            shell.settings.saved()
                        }
                    }
                }
            }
            SettingsBlock(title: "Motion", detail: "Reduce Motion keeps every state change and drops the travel.") {
                SettingsValueRow(
                    title: "Reduce Motion",
                    detail: "Set in System Settings → Accessibility → Display. Shown here, not changed.",
                    value: reduce ? "On" : "Off")
            }
            SettingsBlock(title: "Live sky", detail: "The desktop sky moves slowly on its own.") {
                SettingsValueRow(
                    title: "Live sky", detail: "Not built yet. The sky is a still picture for now.", value: "Off")
            }
        }
    }
}

/// A 150 × 94 thumbnail of a theme, its name under it. The chosen one has a ring; a hover lifts it.
private struct ThemeCard: View {
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s2) {
                thumb.frame(width: 150, height: 94).clipShape(coreShape(Radius.cardMac))
                    .overlay {
                        coreShape(Radius.cardMac).strokeBorder(
                            selected ? palette.primary : palette.glassCardEdge, lineWidth: selected ? 2 : 1)
                    }
                Text(choice.title).font(.system(size: MacTextSize.body, weight: selected ? .semibold : .regular))
            }
            .offset(y: hovering && !reduce ? -2 : 0)
            .animation(Motion.out(Motion.hover), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var thumb: some View {
        switch choice {
        case .night: sky("HomeSky")
        case .day: sky("HomeSkyDay")
        case .sun:
            HStack(spacing: 0) {
                sky("HomeSky").frame(width: 75, alignment: .leading).clipped()
                sky("HomeSkyDay").frame(width: 75, alignment: .trailing).clipped()
            }
        case .system:
            ZStack {
                palette.glassCard
                Image(systemName: "laptopcomputer").font(.system(size: 28)).foregroundStyle(palette.text2)
            }
        }
    }

    private func sky(_ name: String) -> some View {
        Image(name, bundle: .main).resizable().scaledToFill().frame(width: 150, height: 94)
    }
}

/// Where activity shows. The bell is always there; the status bar chip is optional.
struct ActivitySection: View {
    @Bindable var shell: ShellModel
    var body: some View {
        SettingsBlock(
            title: "Where activity shows",
            detail: "What is running and what needs you. The bell is always there; turn on the rest as you like."
        ) {
            SettingsSwitchRow(
                title: "Bell", detail: "Summary, what waits on you, runners and recent events",
                isOn: .constant(true), locked: true)
            SettingsSwitchRow(
                title: "Status bar chip", detail: "“2 running · 1 waiting” next to the bell",
                isOn: Binding(
                    get: { shell.showActivityChip },
                    set: {
                        shell.showActivityChip = $0
                        shell.settings.saved()
                    }))
        }
    }
}

struct WindowSection: View {
    var body: some View {
        SettingsPage(intro: "Ainkrad always runs full screen, in its own Space. It cannot be resized or windowed.") {
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
            SettingsSection(
                id: "activity", group: .notifications, title: "Activity",
                sub: "The bell always shows it · other places are optional", symbol: "waveform.path.ecg", order: 90
            ) { ActivitySection(shell: self) })
        settings.section(
            SettingsSection(
                id: "appearance", group: .appearance, title: "Appearance", sub: "Theme and motion",
                symbol: "circle.lefthalf.filled"
            ) { AppearanceSection(shell: self) })
    }
}
