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
    public var symbol: String
    public var chip: PaneChip?
    /// Panes with their own sidebar (Citadel, Core, admin) ask for more room than a list or terminal.
    public var minWidth: CGFloat
    public let content: AnyView

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

public struct ShellSheetAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let primary: Bool
    public let run: @MainActor () -> Void
    public init(_ label: String, primary: Bool = false, run: @escaping @MainActor () -> Void = {}) {
        self.label = label
        self.primary = primary
        self.run = run
    }
}

/// `Mac.sheet({ title, body, actions })`.
public struct ShellSheet: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let actions: [ShellSheetAction]
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
    public private(set) var panes: [PaneSpec] = []
    /// Each pane's share of the row; equal until a seam is dragged (`tiles.js` re-equalises on open and close).
    public private(set) var paneFractions: [CGFloat] = []
    /// Focus mode shows this one pane full size.
    public var focusedPane: String?
    /// The pane the keyboard acts on (⌃⌥← / →, ⌘W).
    public var activePane: String?
    public var launcherOpen = false
    public var bellOpen = false
    public var overlay: ShellOverlay?
    public var toast: ToastItem?
    public var sheet: ShellSheet?
    public var home = HomeSnapshot.empty
    public var hiddenWidgets: Set<WidgetKind> = []
    public var editingWidgets = false
    public var addingWidget = false
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
    public var elevatedUntil: Date?
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
            NSApp.appearance = theme.appearance
        }
    }

    public init() {
        installBuiltInSettings()
        NSApp?.appearance = theme.appearance
    }

    // MARK: panes (Mac.openPane / closePane / updatePane)

    /// Opens a pane, or focuses it when it is already open; either way the workspace comes up.
    public func openPane(_ spec: PaneSpec) {
        animate {
            if panes.contains(where: { $0.id == spec.id }) {
                if focusedPane != nil { focusedPane = spec.id }
            } else {
                panes.append(spec)
                equalise()
                focusedPane = nil
            }
            activePane = spec.id
            surface = .workspace
        }
    }

    public func closePane(_ id: String) {
        guard let i = panes.firstIndex(where: { $0.id == id }) else { return }
        animate {
            panes.remove(at: i)
            equalise()
            if focusedPane == id { focusedPane = panes.first?.id }
            if activePane == id { activePane = panes.isEmpty ? nil : panes[min(i, panes.count - 1)].id }
            if panes.isEmpty { focusedPane = nil }
        }
    }

    public func closeAllPanes() {
        animate {
            panes = []
            focusedPane = nil
            activePane = nil
        }
    }

    public func updatePane(_ id: String, title: String? = nil, sub: String?? = nil, chip: PaneChip?? = nil) {
        guard let i = panes.firstIndex(where: { $0.id == id }) else { return }
        if let title { panes[i].title = title }
        if let sub { panes[i].sub = sub }
        if let chip { panes[i].chip = chip }
    }

    /// Moves a pane to a column index (drag to reorder, ⌃⌥← / →).
    public func movePane(_ id: String, to index: Int) {
        guard let from = panes.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), panes.count - 1)
        guard to != from else { return }
        animate { panes.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to) }
    }

    /// Seam drag: moves the boundary between pane `i` and `i + 1`; `left` is the new fraction of pane `i`, the pair keeps its total.
    public func setSeam(_ i: Int, leftFraction left: CGFloat) {
        guard paneFractions.indices.contains(i + 1) else { return }
        let pair = paneFractions[i] + paneFractions[i + 1]
        paneFractions[i] = left
        paneFractions[i + 1] = pair - left
    }

    private func equalise() {
        paneFractions = panes.isEmpty ? [] : Array(repeating: 1 / CGFloat(panes.count), count: panes.count)
    }

    public func nudgeActivePane(_ step: Int) {
        guard let id = activePane, let i = panes.firstIndex(where: { $0.id == id }) else { return }
        movePane(id, to: i + step)
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
        launcherOpen.toggle()
    }

    public func toggleBell() {
        launcherOpen = false
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
        if let top = topDialog {
            if top.dismissible { closeTopDialog() }
        } else if let dialog {
            if dialog.dismissible { closeDialog() }
        } else if launcherOpen {
            launcherOpen = false
        } else if bellOpen {
            bellOpen = false
        } else if addingWidget {
            addingWidget = false
        } else if overlay != nil {
            overlay = nil
        } else if editingWidgets {
            editingWidgets = false
        } else {
            return false
        }
        return true
    }

    /// Anything the shell shows over Home or the workspace.
    public var coverOpen: Bool { launcherOpen || bellOpen || overlay != nil || dialog != nil || topDialog != nil }

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

    public func showToast(_ message: String, undo: (@Sendable @MainActor () -> Void)? = nil) {
        toast = ToastItem(message, undo: undo)
    }

    public func presentSheet(title: String, message: String, actions: [ShellSheetAction]) {
        sheet = ShellSheet(title: title, message: message, actions: actions)
    }

    // MARK: widgets

    public func removeWidget(_ kind: WidgetKind) {
        animate { hiddenWidgets.insert(kind) }
        showToast("\(kind.title) removed from Home") { [weak self] in self?.restoreWidget(kind) }
    }

    public func restoreWidget(_ kind: WidgetKind) { animate { hiddenWidgets.remove(kind) } }

    // MARK: -

    /// Layout changes animate with the move curve; Reduce Motion keeps the fade only (the views drop the travel).
    func animate(_ body: () -> Void) { withAnimation(Motion.out(Motion.move), body) }
}
