import AppKit
import CoreUI
import Observation
import SwiftUI

/// What the pane head shows to the right of the title.
public struct PaneChip: Sendable, Hashable {
    public let label: String
    public let tone: Tone
    public let symbol: String
    public init(_ label: String, tone: Tone, symbol: String) {
        self.label = label
        self.tone = tone
        self.symbol = symbol
    }
}

/// A pane a feature module opens: `shell.openPane(...)`, mirroring the prototype's `Mac.openPane`.
public struct PaneSpec: Identifiable {
    public let id: String
    public var title: String
    public var sub: String?
    /// The tab's name when it should not follow `sub`: an app is called by one name wherever it shows (Agents, Accounts, Brain...).
    public var tab: String?
    public var symbol: String
    public var chip: PaneChip?
    /// Panes with their own sidebar (Citadel, Core, admin) ask for more room than a list or terminal.
    public var minWidth: CGFloat
    public let content: AnyView
    /// What ⌘N does while this pane is the active one; nil leaves ⌘N to start an agent session.
    public var onNew: (@MainActor () -> Void)?

    public init<V: View>(
        id: String, title: String, sub: String? = nil, symbol: String, chip: PaneChip? = nil,
        minWidth: CGFloat? = nil, @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.chip = chip
        self.minWidth = max(minWidth ?? 0, ShellMetrics.paneMinWidth)
        self.content = AnyView(content())
    }
}

/// One action in a pane's tab menu (the pane itself has no head or footer).
public struct PaneMenuItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let symbol: String
    public let destructive: Bool
    public let enabled: Bool
    /// Items in a submenu (Send signal ▸ INT, TERM…); empty for a plain action.
    public let children: [PaneMenuItem]
    public let run: @MainActor () -> Void
    public init(
        _ title: String, symbol: String, destructive: Bool = false, enabled: Bool = true,
        children: [PaneMenuItem] = [], run: @escaping @MainActor () -> Void = {}
    ) {
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.enabled = enabled
        self.children = children
        self.run = run
    }
}

public struct ShellSheetAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let primary: Bool
    /// Drawn with the danger button: the action cannot be taken back.
    public let destructive: Bool
    public let run: @MainActor () -> Void
    public init(
        _ label: String, primary: Bool = false, destructive: Bool = false, run: @escaping @MainActor () -> Void = {}
    ) {
        self.label = label
        self.primary = primary
        self.destructive = destructive
        self.run = run
    }
}

/// `Mac.sheet({ title, body, actions })`.
public struct ShellSheet: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let actions: [ShellSheetAction]
    public var symbol: String?
}

public enum ShellSurface: Sendable { case home, workspace }

/// How this Mac stands with its Core: what the "Home Core" button and the connection banner show.
public enum CoreLink: Sendable, Equatable {
    case none, connecting, live, reconnecting, offline
}

/// What the connection banner says on top of `CoreLink`.
public enum LinkNotice: Sendable, Equatable {
    case rateLimited(until: Date?)
    case renewing
    case restarted
}

/// A dialog over everything the shell shows (add device, scopes, revoke, Touch ID). `topDialog` sits above `dialog`.
public struct ShellDialog: Identifiable {
    public let id: String
    public let content: AnyView
    /// Esc: false keeps the dialog open (a Touch ID prompt that cannot be taken back).
    public let dismissible: Bool
    public let onClose: @MainActor () -> Void
    public init<V: View>(
        id: String, dismissible: Bool = true, onClose: @escaping @MainActor () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.dismissible = dismissible
        self.onClose = onClose
        self.content = AnyView(content())
    }
}
public enum ShellOverlay: Hashable, Sendable { case settings, shortcuts }

/// The shell's one state holder. Feature modules talk to it only through `openPane`, `launcher`, `bell`, `settings`, `toast` and `sheet`.
@MainActor @Observable
public final class ShellModel {
    public var surface: ShellSurface = .home
    /// The open panes, in reading order of the tiling tree.
    public private(set) var panes: [PaneSpec] = []
    /// How the open panes are tiled (`tiles.js`): an N-ary split tree, equal columns until a seam is dragged or a pane is dropped.
    private(set) var tree = TileTree()
    /// Panes closed from the head, the menu or the keyboard, newest last (⇧⌘T brings the last one back). They keep running.
    public private(set) var closedPanes: [PaneSpec] = []
    /// Focus mode shows this one pane full size.
    public var focusedPane: String?
    /// The pane the keyboard acts on (⌃⌥← / →, ⌘W).
    public var activePane: String?
    public var launcherOpen = false
    /// ⇧⌘A: the launcher holding the active pane's actions instead of apps.
    public var actionsOpen = false
    /// ⇧⌘O: every open app as a card to pick from.
    public var overviewOpen = false
    /// Names the person gave tabs, by pane id; the tab being renamed in place.
    /// Kept on this Mac across launches (pane ids are stable: terminal-<id>, agents, runners…).
    public var tabNames: [String: String] = [:] {
        didSet { defaults.set(tabNames, forKey: Self.tabNamesKey) }
    }
    static let tabNamesKey = "ainkrad.core.tab.names"
    public var renamingTab: String?
    public var bellOpen = false
    public var overlay: ShellOverlay?
    public var toast: ToastItem?
    public var sheet: ShellSheet?
    public var home = HomeSnapshot.empty
    public private(set) var widgets: WidgetLayout
    public let profile: UserProfile
    private let defaults: UserDefaults
    static let layoutKey = "ainkrad.core.home.widgets"
    public var editingWidgets = false
    public var addingWidget = false
    /// What the launcher starts with when it opens (a hand-off from a command that opens it with a search; cleared on use).
    public var launcherQuery = ""
    #if DEBUG
    /// Snapshots only: draws the second Quick actions tile in its hover state.
    public var debugForceQuickHover = false
    /// Snapshots only: drops a pane on the edge of another, as a drag would.
    public func debugDrop(_ id: String, on target: String, edge: String) {
        let e: TileEdge = edge == "left" ? .left : edge == "right" ? .right : edge == "top" ? .top : .bottom
        dropPane(id, on: target, edge: e)
    }
    #endif
    public var coreLink: CoreLink = .none {
        didSet { if oldValue == .live && coreLink != .live { lastLiveAt = Date() } }
    }
    /// When the Core was last reachable: what the "resuming" banner says the screen is current to.
    public private(set) var lastLiveAt: Date?
    /// A connection state beyond `coreLink`: the Core says slow down, the session is renewing, the Core restarted.
    public var linkNotice: LinkNotice?
    /// Retry for the connection banner and the Home Core button when the Core is unreachable.
    public var retryConnection: (@MainActor () -> Void)?
    /// When the session's Touch ID elevation ends; nil when locked.
    public var elevatedUntil: Date? {
        didSet {
            // The meter shrinks over whatever the Core granted this time (it is 5 minutes today).
            if let u = elevatedUntil, u != oldValue { elevationSpan = max(u.timeIntervalSinceNow, 1) }
            if elevatedUntil == nil { elevationPanelOpen = false }
        }
    }
    public private(set) var elevationSpan: TimeInterval = 300
    /// The panel under the elevation chip (what is unlocked, time left, Renew with Touch ID).
    public var elevationPanelOpen = false
    /// The one "waiting on you" number: approvals nobody answered, supplied by Agents (`AgentsModel.waitingOnYou`). Alerts and Brain
    /// inbox items are not in it; the bell counts them on their own. Until Agents is up, the bell's approval items stand in.
    public var waitingSource: (@MainActor () -> Int)?
    public var waitingOnYou: Int { waitingSource?() ?? bell.items.filter { $0.kind == .approval }.count }
    /// Alarms (backup age, an account turned off...): counted on their own, never added to the approvals.
    public var alertsOnYou: Int { bell.items.filter { $0.kind == .alarm }.count }

    /// Settings → Activity: the "N running · M waiting" chip in the status cluster. The bell is always there.
    public var showActivityChip = true {
        didSet { defaults.set(showActivityChip, forKey: Self.activityChipKey) }
    }
    static let activityChipKey = "ainkrad.core.activity.statusChip"
    /// The elevation chip: asks for Touch ID.
    public var elevate: (@MainActor () -> Void)?
    public var dialog: ShellDialog?
    public var topDialog: ShellDialog?

    public let launcher = LauncherRegistry()
    public let bell = BellRegistry()
    public let settings = SettingsRegistry()
    /// Day, Night or System (Settings → Appearance). Persisted; applied to the whole app.
    public var theme: ThemeChoice = ThemeChoice.stored() {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeChoice.key)
            NSApp?.appearance = theme.appearance
        }
    }

    public init(defaults: UserDefaults = .coreStore()) {
        self.defaults = defaults
        profile = UserProfile(defaults: defaults)
        tabNames = defaults.dictionary(forKey: Self.tabNamesKey) as? [String: String] ?? [:]
        widgets = defaults.data(forKey: Self.layoutKey).flatMap(WidgetLayout.decoded) ?? .standard()
        if !WidgetKind.boardShown { widgets.items.removeAll { $0.kind == .board } }
        showActivityChip = defaults.object(forKey: Self.activityChipKey) as? Bool ?? true
        installBuiltInSettings()
        NSApp?.appearance = theme.appearance
        // Follow the sun changes sides at 07:00 and 18:00: look again every minute.
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if self.theme == .sun { NSApp.appearance = self.theme.appearance }
            }
        }
        launcher.register(
            LauncherEntry(
                id: "settings", title: "Settings", sub: "Mac, Core, Security, Notifications, Appearance",
                symbol: "gearshape", keywords: ["preferences", "appearance", "activity"], tile: .slate
            ) { [weak self] in self?.open(.settings) })
        launcher.register(
            LauncherEntry(
                id: "shortcuts", title: "Keyboard Shortcuts", sub: "All keyboard shortcuts",
                symbol: "keyboard", keywords: ["keys", "help", "commands"], isAction: true, tile: .slate
            ) { [weak self] in self?.open(.shortcuts) })
        launcher.register(
            LauncherEntry(
                id: "widgets.add", title: "Add Widget…", sub: "Put a widget on Home", symbol: "plus",
                keywords: ["widgets", "home", "gallery"], isAction: true
            ) { [weak self] in
                self?.show(.home)
                self?.addingWidget = true
            })
        launcher.register(
            LauncherEntry(
                id: "widgets.edit", title: "Edit Widgets", sub: "Rearrange, resize or remove",
                symbol: "slider.horizontal.3",
                keywords: ["widgets", "home", "rearrange", "resize"], isAction: true
            ) { [weak self] in
                self?.show(.home)
                self?.editingWidgets = true
            })
    }

    // MARK: panes (Mac.openPane / closePane / updatePane)

    /// Opens a pane, or focuses it when it is already open; either way the workspace comes up.
    public func openPane(_ spec: PaneSpec) {
        animate {
            if panes.contains(where: { $0.id == spec.id }) {
                if focusedPane != nil { focusedPane = spec.id }
            } else {
                panes.append(spec)
                tree.open(spec.id)
                focusedPane = nil
            }
            activePane = spec.id
            surface = .workspace
        }
    }

    /// Closes a pane without a trace (a feature closing its own pane). People closing a pane use `dismissPane`.
    public func closePane(_ id: String) {
        guard let i = panes.firstIndex(where: { $0.id == id }) else { return }
        animate {
            panes.remove(at: i)
            tree.remove(id)
            if focusedPane == id { focusedPane = panes.first?.id }
            if activePane == id { activePane = panes.isEmpty ? nil : panes[min(i, panes.count - 1)].id }
            if panes.isEmpty { focusedPane = nil }
        }
    }

    /// A person closing a pane: it keeps running, a toast offers Undo and ⇧⌘T reopens it (ten deep).
    public func dismissPane(_ id: String) {
        guard let spec = panes.first(where: { $0.id == id }) else { return }
        closePane(id)
        closedPanes.append(spec)
        if closedPanes.count > 10 { closedPanes.removeFirst() }
        // Words name the pane the way its tab does; the title (which can carry an id) is hover help only.
        toast = ToastItem(
            "Closed \(tabName(spec)). It keeps running.", kind: .info, help: spec.title
        ) { [weak self] in self?.reopenClosedPane() }
    }

    public func reopenClosedPane() {
        guard let spec = closedPanes.popLast() else { return showToast("No closed pane to reopen.", kind: .info) }
        openPane(spec)
    }

    public func closeOtherPanes(except id: String) {
        for other in panes.map(\.id) where other != id { closePane(other) }
    }

    public func closeAllPanes() {
        animate {
            panes = []
            tree = TileTree()
            focusedPane = nil
            activePane = nil
        }
    }

    /// A pane's own actions, read each time its tab menu opens (so they follow the pane's state).
    public private(set) var paneMenus: [String: @MainActor () -> [PaneMenuItem]] = [:]
    public func setPaneMenu(_ id: String, _ items: @escaping @MainActor () -> [PaneMenuItem]) { paneMenus[id] = items }

    public func updatePane(_ id: String, title: String? = nil, sub: String?? = nil, chip: PaneChip?? = nil) {
        guard let i = panes.firstIndex(where: { $0.id == id }) else { return }
        if let title { panes[i].title = title }
        if let sub { panes[i].sub = sub }
        if let chip { panes[i].chip = chip }
    }

    /// Moves a pane to a place in reading order (drag to reorder, ⌃⌥← / →).
    public func movePane(_ id: String, to index: Int) {
        guard let from = tree.leaves.firstIndex(of: id) else { return }
        let to = min(max(index, 0), panes.count - 1)
        animate {
            var step = to - from
            while step != 0, tree.move(id, step: step > 0 ? 1 : -1) { step += step > 0 ? -1 : 1 }
            syncOrder()
        }
    }

    /// A pane dropped on the near half of another: it joins that row or column, or wraps the target in a 50/50 split.
    func dropPane(_ id: String, on target: String, edge: TileEdge) {
        animate {
            tree.drop(id, on: target, edge: edge)
            syncOrder()
        }
    }

    /// Seam drag (`position` along the split's axis from its origin). Not animated: it follows the pointer.
    func resizeSeam(_ seam: TileSeam, gap: CGFloat, position: CGFloat) {
        tree.resize(seam, gap: gap, position: position)
    }

    private func syncOrder() {
        let order = tree.leaves
        panes.sort { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
    }

    /// ⌘N: the active pane's own "new" (connect, new budget...), else a new agent session.
    public func newItem() {
        let id = activePane ?? panes.first?.id
        if surface == .workspace, let new = panes.first(where: { $0.id == id })?.onNew {
            new()
        } else {
            launcher.entry("agents.new")?.run()
        }
    }

    public func nudgeActivePane(_ step: Int) {
        guard let id = activePane else { return }
        animate {
            tree.move(id, step: step)
            syncOrder()
        }
    }

    public func cyclePane(_ step: Int) {
        guard !panes.isEmpty else { return }
        let i = panes.firstIndex { $0.id == activePane } ?? 0
        let next = panes[(i + step + panes.count) % panes.count].id
        animate {
            activePane = next
            if focusedPane != nil { focusedPane = next }
        }
    }

    public func toggleFocusMode() {
        guard !panes.isEmpty else { return }
        animate {
            focusedPane = focusedPane == nil ? (activePane ?? panes.first?.id) : nil
            surface = .workspace
        }
    }

    // MARK: surfaces and overlays

    public func show(_ surface: ShellSurface) { animate { self.surface = surface } }
    public func toggleSurface() { show(surface == .home ? .workspace : .home) }

    public func toggleLauncher() {
        bellOpen = false
        elevationPanelOpen = false
        launcherOpen.toggle()
    }

    public func toggleBell() {
        launcherOpen = false
        elevationPanelOpen = false
        bellOpen.toggle()
    }

    public func open(_ overlay: ShellOverlay) {
        launcherOpen = false
        bellOpen = false
        self.overlay = overlay
    }

    /// Esc: closes the topmost thing. Returns false when there was nothing to close.
    @discardableResult
    public func closeTopmost() -> Bool {
        if sheet != nil {
            sheet = nil
        } else if let top = topDialog {
            if top.dismissible { closeTopDialog() }
        } else if let dialog {
            if dialog.dismissible { closeDialog() }
        } else if elevationPanelOpen {
            elevationPanelOpen = false
        } else if launcherOpen {
            launcherOpen = false
        } else if actionsOpen {
            actionsOpen = false
        } else if overviewOpen {
            overviewOpen = false
        } else if bellOpen {
            bellOpen = false
        } else if overlay != nil {
            overlay = nil
        } else if addingWidget {
            addingWidget = false
        } else if editingWidgets {
            editingWidgets = false
        } else {
            return false
        }
        return true
    }

    /// Anything the shell shows over Home or the workspace.
    public var coverOpen: Bool {
        sheet != nil || launcherOpen || elevationPanelOpen || bellOpen || overlay != nil || dialog != nil
            || topDialog != nil
    }

    /// True when `id` is the pane the person is working in: the workspace is showing and this pane is the focused or active one.
    public func isFront(_ id: String) -> Bool { surface == .workspace && (focusedPane ?? activePane) == id }

    public func present(_ d: ShellDialog) {
        launcherOpen = false
        bellOpen = false
        dialog = d
    }

    public func closeDialog() {
        guard let d = dialog else { return }
        dialog = nil
        d.onClose()
    }

    public func presentOnTop(_ d: ShellDialog) { topDialog = d }

    public func closeTopDialog() {
        guard let d = topDialog else { return }
        topDialog = nil
        d.onClose()
    }

    public func showToast(
        _ message: String, kind: ToastKind = .ok, actionTitle: String = "Undo",
        undo: (@Sendable @MainActor () -> Void)? = nil
    ) {
        toast = ToastItem(message, kind: kind, actionTitle: actionTitle, undo: undo)
    }

    /// ⌘Z: runs the showing toast's Undo and clears it. False (nothing run) when there is none, its button is not an Undo, or
    /// the keys are going to a text field, whose own undo keeps ⌘Z.
    @discardableResult
    public func undoToast(inTextField: Bool = false) -> Bool {
        guard !inTextField, let t = toast, t.actionTitle == "Undo", let undo = t.undo else { return false }
        toast = nil
        undo()
        return true
    }

    public func presentSheet(title: String, message: String, actions: [ShellSheetAction], symbol: String? = nil) {
        sheet = ShellSheet(title: title, message: message, actions: actions, symbol: symbol)
    }

    /// Forget this Core: every preference this Mac kept goes back to a fresh install (name, Home widgets, theme).
    public func resetToFresh() {
        profile.set("")
        widgets = .standard()
        defaults.removeObject(forKey: Self.layoutKey)
        theme = .system
        tabNames = [:]
    }

    // MARK: widgets

    /// Every edit goes through here: it keeps the layout valid, saves it and animates the move.
    private func edit(_ change: (inout WidgetLayout) -> Bool) -> Bool {
        var next = widgets
        guard change(&next) else { return false }
        animate { widgets = next }
        if let d = next.encoded() { defaults.set(d, forKey: Self.layoutKey) }
        return true
    }

    /// Applies a layout a drag already worked out (the drop).
    public func setWidgets(_ items: [WidgetItem]) {
        _ = edit {
            $0.items = items
            return true
        }
    }
    public func moveWidget(_ id: UUID, dx: Int, dy: Int) { _ = edit { $0.nudge(id, dx: dx, dy: dy) } }

    public func resizeWidget(_ id: UUID, to size: WidgetSize) {
        if !edit({ $0.resize(id, to: size) }) { showToast("Not enough room for that size.") }
    }

    @discardableResult
    public func addWidget(_ kind: WidgetKind, _ size: WidgetSize? = nil) -> Bool {
        var added: WidgetItem?
        let ok = edit {
            added = $0.add(kind, size)
            return added != nil
        }
        if ok, let added {
            showToast("Added \(added.kind.title)")
        } else {
            showToast("No room on Home. Remove a widget first.")
        }
        return ok
    }

    public func removeWidget(_ id: UUID) {
        var gone: WidgetItem?
        guard
            edit({
                gone = $0.remove(id)
                return gone != nil
            }), let gone
        else { return }
        showToast("Removed \(gone.kind.title)") { [weak self] in
            guard let self else { return }
            if !self.edit({ $0.restore(gone) }) { self.showToast("No room to bring it back.") }
        }
    }

    public func resetWidgets() {
        let was = widgets
        _ = edit {
            $0 = .standard()
            return true
        }
        showToast("Home is back to the default layout") { [weak self] in
            _ = self?.edit {
                $0 = was
                return true
            }
        }
    }

    // MARK: -

    /// Layout changes animate with the move curve; Reduce Motion keeps the fade only (the views drop the travel).
    func animate(_ body: () -> Void) { withAnimation(Motion.out(Motion.move), body) }
}
