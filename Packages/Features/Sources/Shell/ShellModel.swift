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
    /// The least height the app works in; no app is squeezed below it (a taller window is asked for, never a shorter pane).
    public var minHeight: CGFloat
    /// Design, Lore and Projects need the whole screen: they open in a workspace of their own and nothing else tiles beside them.
    public var fullScreenOnly: Bool
    public let content: AnyView
    /// What ⌘N does while this pane is the active one; nil leaves ⌘N to start an AI session.
    public var onNew: (@MainActor () -> Void)?

    public init<V: View>(
        id: String, title: String, sub: String? = nil, symbol: String, chip: PaneChip? = nil,
        minWidth: CGFloat? = nil, minHeight: CGFloat? = nil, fullScreenOnly: Bool = false,
        @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.chip = chip
        self.minWidth = max(minWidth ?? 0, ShellMetrics.paneMinWidth)
        self.minHeight = max(minHeight ?? 0, ShellMetrics.paneMinHeight)
        self.fullScreenOnly = fullScreenOnly
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
    /// One plain line shown as the item's tooltip.
    public let help: String?
    /// Items in a submenu (Running command ▸ Stop it, Pause it…); empty for a plain action.
    public let children: [PaneMenuItem]
    public let run: @MainActor () -> Void
    public init(
        _ title: String, symbol: String, destructive: Bool = false, enabled: Bool = true,
        help: String? = nil, children: [PaneMenuItem] = [], run: @escaping @MainActor () -> Void = {}
    ) {
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.enabled = enabled
        self.help = help
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

/// Whether the app is open or covered by the Unlock card (E1-1).
public enum AppLock: Equatable, Sendable {
    case open
    case locked
    /// Touch ID is being asked for.
    case checking
}

/// The top bar's dropdowns that hold more than a list (E2-2, D-10).
public enum TopMenu: Hashable, Sendable { case core, runners, brain }

/// One device in the Core dropdown: its name, a line under it and whether it answers now.
public struct DeviceGlance: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sub: String
    public let symbol: String
    public let online: Bool
    public init(id: String, name: String, sub: String, symbol: String, online: Bool) {
        self.id = id
        self.name = name
        self.sub = sub
        self.symbol = symbol
        self.online = online
    }
}

/// What the Brain dropdown shows: how it is, what it does now, and a few counts.
public struct BrainGlance: Sendable, Equatable {
    public struct Stat: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public let label: String
        public let count: Int
        /// The Brain area this count opens (`me`, `rules`, `knowledge`, `timeline`, `places`); nil for a plain count.
        public let area: String?
        public init(_ label: String, _ count: Int, area: String? = nil) {
            self.label = label
            self.count = count
            self.area = area
        }
    }
    /// "Learning quietly in the background", "Paused"...
    public let status: String
    public let healthy: Bool
    /// What it is doing now ("Tidying 12 new notes"), with how far along it is (0...1), when known.
    public let doing: String?
    public let progress: Double?
    public let stats: [Stat]
    /// The step of Collect, Distill, Remember it is on now (0...2); nil draws no flow.
    public let flowStep: Int?
    /// Things it learned today, with an Undo in the dropdown; 0 hides the row.
    public let learned: Int
    /// An import under way, with its step and how far it is; nil when none runs.
    public var importing: Importing?
    /// An import in progress, as the top bar, the dropdown and Brain Home show it.
    public struct Importing: Sendable, Equatable {
        /// The wizard's step: "Collect", "Sort", "Learn"...
        public let step: String
        /// "Reading your sessions".
        public let line: String
        /// "9,928 of 12,391", when counted.
        public let detail: String?
        /// 0...1 when known; nil draws a busy bar.
        public let progress: Double?
        public init(step: String, line: String, detail: String? = nil, progress: Double? = nil) {
            self.step = step
            self.line = line
            self.detail = detail
            self.progress = progress
        }
    }
    public init(
        status: String, healthy: Bool, doing: String? = nil, progress: Double? = nil, stats: [Stat] = [],
        flowStep: Int? = nil, learned: Int = 0
    ) {
        self.status = status
        self.healthy = healthy
        self.doing = doing
        self.progress = progress
        self.stats = stats
        self.flowStep = flowStep
        self.learned = learned
    }
}

/// The shell's one state holder. Feature modules talk to it only through `openPane`, `launcher`, `bell`, `settings`, `toast` and `sheet`.
@MainActor @Observable
public final class ShellModel {
    public var surface: ShellSurface = .home
    /// Every open pane in every workspace. All of them stay in the view tree (the others folded away) so a terminal in another
    /// workspace keeps its AppKit view.
    public internal(set) var allPanes: [PaneSpec] = []
    /// The workspaces, in order. The current one's pane state lives in `tree`, `activePane` and `focusedPane`; the saved copy here is
    /// refreshed when it is left.
    public internal(set) var spaces: [Workspace] = []
    public internal(set) var currentSpace = UUID()
    var paneSpace: [String: UUID] = [:]
    /// The width the workspace has for panes; set by the workspace view. Zero means not measured yet, and everything fits.
    public var workspaceWidth: CGFloat = 0
    /// Why the newest workspace was opened (the note card says it once).
    public var spaceNote: SpaceNote?
    /// Set while the launcher opens something with ⌘↵: the app comes next to the current one, even from another workspace.
    public var openBeside = false
    /// The open panes of the current workspace, in reading order of the tiling tree.
    public var panes: [PaneSpec] { allPanes.filter { paneSpace[$0.id] == currentSpace } }
    /// How the open panes of the current workspace are tiled (`tiles.js`): an N-ary split tree, equal columns until a seam is dragged or a pane is dropped.
    var tree = TileTree()
    /// Panes closed from the head, the menu or the keyboard, newest last (⇧⌘T brings the last one back). They keep running.
    public private(set) var closedPanes: [PaneSpec] = []
    /// Focus mode shows this one pane full size.
    public var focusedPane: String?
    /// The pane the keyboard acts on (⌃⌥← / →, ⌘W).
    public var activePane: String?
    public var launcherOpen = false
    /// ⇧⌘A: the launcher holding the active pane's actions instead of apps.
    public var actionsOpen = false
    /// ⇧⌘O / ⌃↑: every workspace as a tile to pick from.
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
    /// Home widgets that act on the Core: the app sets them. The Brain question is kept (true) or dropped (false), and a
    /// task on today's note is ticked or unticked by its place in the note.
    public var answerBrainQuestion: (@MainActor (_ id: String, _ room: String, _ keep: Bool) -> Void)?
    public var toggleNoteTodo: (@MainActor (_ index: Int) -> Void)?
    public private(set) var widgets: WidgetLayout
    public let profile: UserProfile
    let defaults: UserDefaults
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
    /// What the Mac's network path says (`NWPathMonitor`), for telling "no network" from "Core not answering".
    public var networkUp = true
    /// Retries since the link dropped, when the next one starts, and how long the wait is: the chip and its panel say them.
    public var retryAttempt = 0
    public var nextRetryAt: Date?
    public var retrySpan: TimeInterval?
    /// The one top-bar dropdown that is open (Core, Runners or Brain). The bell and the launcher have their own flags.
    public var topMenu: TopMenu?
    /// The Core dropdown (formerly the connection panel).
    public var connectionPanelOpen: Bool {
        get { topMenu == .core }
        set { topMenu = newValue ? .core : (topMenu == .core ? nil : topMenu) }
    }
    /// How long the last call to the Core took, in milliseconds; the app sets it after each health read.
    public var responseMs: Int?
    /// What the Devices block of the Core dropdown lists; the app (Pairing) supplies it.
    public var devicesGlance: (@MainActor () -> [DeviceGlance])?
    /// What the Brain dropdown shows; the Brain module supplies it. Nil means the Brain is not up yet.
    public var brainGlance: (@MainActor () -> BrainGlance?)?
    /// Tool installs under way on runners, by runner id, from `runner.tool_install` (Core API minor 95; `RunnerUpdates`).
    public private(set) var runnerUpdates: [String: RunnerUpdate] = [:]
    /// True on a Core with API minor 95: the Runners dropdown then says Updating while a runner gets its tools.
    public var showsRunnerUpdates = false
    public func toolInstall(_ fields: [String: String]) {
        guard showsRunnerUpdates else { return }
        RunnerUpdates.apply(fields, to: &runnerUpdates)
    }
    /// Reads the Brain's fresh numbers when its dropdown opens (Core API minor 95); nil on an older Core.
    public var brainRefresh: (@MainActor () async -> Void)?
    /// Opens Brain at an area (`me`, `rules`, `knowledge`, `timeline`, `places`).
    public var brainOpenArea: (@MainActor (String) -> Void)?
    /// Takes back what the Brain learned today.
    public var brainUndoLearned: (@MainActor () -> Void)?
    /// The Core's self-update (E12-3): what its pop-up shows. The app fills it from `GET /system/update`.
    public var coreUpdate = CoreUpdateStatus() {
        didSet { if coreUpdate != oldValue { updates.receive(coreUpdate) } }
    }
    /// "Update now" and "Try again now" in the pop-up; nil until the app has a Core that serves the route.
    public var startCoreUpdate: (@MainActor () -> Void)?
    /// "What is new" for the Core's last update, and the update's own words under "See what happened".
    public var coreUpdateNews: (@MainActor () -> Void)?
    @ObservationIgnored let networkWatch = NetworkWatch()
    public var chipState: ConnectionChipState? {
        ConnectionChipState.of(link: coreLink, networkUp: networkUp, attempt: retryAttempt)
    }
    /// Starts watching the network once.
    public func watchNetwork() { networkWatch.start { [weak self] up in self?.networkUp = up } }
    public func toggleConnectionPanel() { toggleMenu(.core) }
    /// Opens a top-bar dropdown, or closes it when it is the one open; any other layer closes.
    public func toggleMenu(_ menu: TopMenu) {
        launcherOpen = false
        bellOpen = false
        topMenu = topMenu == menu ? nil : menu
    }
    /// When the Core was last reachable: what the "resuming" banner says the screen is current to.
    public private(set) var lastLiveAt: Date?
    /// A connection state beyond `coreLink`: the Core says slow down, the session is renewing, the Core restarted.
    public var linkNotice: LinkNotice?
    /// Retry for the connection banner and the Home Core button when the Core is unreachable.
    public var retryConnection: (@MainActor () -> Void)?
    /// When the session's Touch ID elevation ends; nil when locked.
    public var elevatedUntil: Date?
    /// The app unlock (E1-1, mockup 01): `.open` shows the app; the others cover it with the Unlock card.
    public var lock: AppLock = .open
    /// First-run setup is still open: the desktop stays hidden (only the wallpaper) until setup is finished or skipped.
    public var setupOpen: () -> Bool = { false }
    /// The Unlock card's buttons: Touch ID, and the password fallback (the system sheet offers it after Touch ID).
    public var unlock: (@MainActor () -> Void)?
    /// The one "waiting on you" number: approvals nobody answered, supplied by Agents (`AgentsModel.waitingOnYou`). Alerts and Brain
    /// inbox items are not in it; the bell counts them on their own. Until Agents is up, the bell's approval items stand in.
    public var waitingSource: (@MainActor () -> Int)?
    /// The AI session counts the status chip shows, from the same index as the AI Sessions list and its sidebar (review
    /// 2026-11-16: the chip, the sidebar and the groups disagreed). Nil until Agents is up: the home feed stands in.
    public var sessionCounts: (@MainActor () -> (running: Int, needYou: Int))?
    /// The Brain icon's state (E9-2), supplied by Brain from the Core's status call. Nil hides the icon (an older Core, or no Brain).
    public var brainStatus: (@MainActor () -> BrainChip?)?
    /// Opens the Brain's import panel (a new one, or the one under way); nil when the Brain cannot import.
    public var brainOpenImport: (@MainActor () -> Void)?
    /// Opens the Brain from the icon's panel.
    public var openBrain: (@MainActor () -> Void)?
    public var brainPanelOpen = false
    public var waitingOnYou: Int {
        guard let source = waitingSource else { return bell.items.filter { $0.kind == .approval }.count }
        return source() + joinRequests
    }
    /// A new device asking to join needs an approval too (Pairing's bell items, `pairing-<id>`); Agents does not count them.
    var joinRequests: Int { bell.items.filter { $0.kind == .approval && $0.id.hasPrefix("pairing-") }.count }
    /// Alarms (backup age, an account turned off...): counted on their own, never added to the approvals.
    public var alertsOnYou: Int { bell.items.filter { $0.kind == .alarm }.count }

    /// Settings → Activity: the "N running · M waiting" chip in the status cluster. The bell is always there.
    public var showActivityChip = true {
        didSet { defaults.set(showActivityChip, forKey: Self.activityChipKey) }
    }
    static let activityChipKey = "ainkrad.core.activity.statusChip"
    public var dialog: ShellDialog?
    public var topDialog: ShellDialog?

    public let launcher = LauncherRegistry()
    /// What the Core says about its hardware (E15): the top bar's load, and where jobs and sessions ran.
    public let hardwareDeck = HardwareDeck()
    public let bell = BellRegistry()
    public let settings = SettingsRegistry()
    /// The Core page of Settings: its name, crash reports, updates and storage.
    public let corePage = CorePageModel()
    /// Settings, Updates: the Core's check, the runners and this app's updater.
    public let updates = UpdatesModel()
    /// Day, Night or System (Settings → Appearance). Persisted; applied to the whole app.
    public var theme: ThemeChoice = ThemeChoice.stored() {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeChoice.key)
            NSApp?.appearance = theme.appearance
        }
    }

    /// ⌃⌘D and the launcher entry: flip what the window shows now, and say how to go back.
    public func switchDayAndNight(isDark: Bool? = nil) {
        let dark = isDark ?? (NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        theme = theme.toggled(isDark: dark)
        showToast(
            dark
                ? "Day look. Settings, Appearance changes it back to Follow the Mac."
                : "Night look. Settings, Appearance changes it back to Follow the Mac.")
    }

    public init(defaults: UserDefaults = .coreStore()) {
        self.defaults = defaults
        profile = UserProfile(defaults: defaults)
        tabNames = defaults.dictionary(forKey: Self.tabNamesKey) as? [String: String] ?? [:]
        widgets = defaults.data(forKey: Self.layoutKey).flatMap(WidgetLayout.decoded) ?? .standard()
        if !WidgetKind.boardShown { widgets.items.removeAll { $0.kind == .board } }
        showActivityChip = defaults.object(forKey: Self.activityChipKey) as? Bool ?? true
        spaces = [Workspace(id: currentSpace)]
        launcher.attach(defaults)
        installBuiltInSettings()
        updates.publish = { [weak self] s in if self?.coreUpdate != s { self?.coreUpdate = s } }
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
                id: "settings", title: "Settings", sub: "General, Apps, Core",
                symbol: "gearshape", keywords: ["preferences", "appearance", "activity"], tile: .slate
            ) { [weak self] in self?.open(.settings) })
        launcher.register(
            LauncherEntry(
                id: "shortcuts", title: "Keyboard Shortcuts", sub: "All keyboard shortcuts",
                symbol: "keyboard", keywords: ["keys", "help", "commands"], isAction: true, tile: .slate
            ) { [weak self] in self?.open(.shortcuts) })
        launcher.register(
            LauncherEntry(
                id: "day-night", title: "Switch Day and Night", sub: "Flip the look of the app",
                symbol: "circle.lefthalf.filled", keywords: ["theme", "dark", "light", "appearance"], isAction: true,
                tile: .slate
            ) { [weak self] in self?.switchDayAndNight() })
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
        launcher.register(
            LauncherEntry(
                id: "workspaces.new", title: "New Workspace", sub: "An empty space for more apps",
                symbol: "rectangle.on.rectangle", keywords: ["workspace", "space", "desktop"], isAction: true
            ) { [weak self] in self?.newSpace() })
        launcher.register(
            LauncherEntry(
                id: "workspaces.all", title: "All Workspaces", sub: "See and switch workspaces",
                symbol: "square.grid.2x2", keywords: ["workspace", "space", "overview"], isAction: true
            ) { [weak self] in self?.toggleSpaces() })
    }

    // MARK: panes (Mac.openPane / closePane / updatePane)

    /// Opens a pane, or focuses it when it is already open; either way the workspace comes up.
    public func openPane(_ spec: PaneSpec) {
        animate {
            if let home = paneSpace[spec.id] {
                if openBeside && home != currentSpace { bringHere(spec.id) } else { enterSpace(home) }
                if focusedPane != nil { focusedPane = spec.id }
            } else {
                if needsNewSpace(for: spec) { openSpace(for: spec) }
                allPanes.append(spec)
                paneSpace[spec.id] = currentSpace
                tree.open(spec.id)
                focusedPane = nil
            }
            activePane = spec.id
            surface = .workspace
        }
    }

    /// Shows `spec` in the place of pane `oldID` (switching what a pane shows, as the session sidebar does): same tab position,
    /// same tile. When `spec` is already open elsewhere it is focused instead, and `oldID` stays.
    public func replacePane(_ oldID: String, with spec: PaneSpec) {
        guard paneSpace[oldID] == currentSpace, paneSpace[spec.id] == nil,
            let i = allPanes.firstIndex(where: { $0.id == oldID })
        else {
            openPane(spec)
            return
        }
        allPanes[i] = spec
        paneSpace[oldID] = nil
        paneSpace[spec.id] = currentSpace
        tree.rename(oldID, to: spec.id)
        if focusedPane == oldID { focusedPane = spec.id }
        activePane = spec.id
        surface = .workspace
    }

    /// Closes a pane without a trace (a feature closing its own pane). People closing a pane use `dismissPane`.
    public func closePane(_ id: String) {
        guard let home = paneSpace[id], let all = allPanes.firstIndex(where: { $0.id == id }) else { return }
        animate {
            if home == currentSpace {
                let i = panes.firstIndex { $0.id == id } ?? 0
                allPanes.remove(at: all)
                paneSpace[id] = nil
                tree.remove(id)
                let left = panes
                if focusedPane == id { focusedPane = left.first?.id }
                if activePane == id { activePane = left.isEmpty ? nil : left[min(i, left.count - 1)].id }
                if left.isEmpty {
                    focusedPane = nil
                    closeEmptySpace()
                }
            } else if let k = spaces.firstIndex(where: { $0.id == home }) {
                allPanes.remove(at: all)
                paneSpace[id] = nil
                spaces[k].tree.remove(id)
                if spaces[k].focused == id { spaces[k].focused = nil }
                if spaces[k].active == id { spaces[k].active = spaces[k].tree.leaves.first }
                // Nobody is looking at it and nothing is in it: it just goes.
                if spaces[k].tree.leaves.isEmpty { spaces.remove(at: k) }
            }
        }
    }

    /// A person closing a pane: it keeps running, a toast offers Undo and ⇧⌘T reopens it (ten deep).
    public func dismissPane(_ id: String) {
        guard let spec = allPanes.first(where: { $0.id == id }) else { return }
        closePane(id)
        closedPanes.append(spec)
        if closedPanes.count > 10 { closedPanes.removeFirst() }
        // Words name the pane the way its tab does; the title (which can carry an id) is hover help only.
        toast = ToastItem(
            "Closed “\(tabName(spec))”. It keeps running.", kind: .info, help: spec.title
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
            allPanes = []
            paneSpace = [:]
            spaces = [Workspace(id: currentSpace)]
            tree = TileTree()
            focusedPane = nil
            activePane = nil
        }
    }

    /// A pane's own actions, read each time its tab menu opens (so they follow the pane's state).
    public private(set) var paneMenus: [String: @MainActor () -> [PaneMenuItem]] = [:]
    public func setPaneMenu(_ id: String, _ items: @escaping @MainActor () -> [PaneMenuItem]) { paneMenus[id] = items }

    public func updatePane(_ id: String, title: String? = nil, sub: String?? = nil, chip: PaneChip?? = nil) {
        guard let i = allPanes.firstIndex(where: { $0.id == id }) else { return }
        if let title { allPanes[i].title = title }
        if let sub { allPanes[i].sub = sub }
        if let chip { allPanes[i].chip = chip }
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
        let mine = tree.leaves.compactMap { id in allPanes.first { $0.id == id } }
        allPanes = allPanes.filter { paneSpace[$0.id] != currentSpace } + mine
    }

    /// ⌘N: the active pane's own "new" (connect, new budget...), else a new AI session.
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
    /// ⌘0: Home, and back to the workspace you left. With nothing open there is no workspace to go back to.
    public func toggleSurface() {
        if surface == .home && allPanes.isEmpty { return }
        show(surface == .home ? .workspace : .home)
    }

    public func toggleLauncher() {
        bellOpen = false
        topMenu = nil
        if !launcherOpen { launcher.refreshPicks() }
        launcherOpen.toggle()
    }

    public func toggleBell() {
        launcherOpen = false
        topMenu = nil
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
        } else if topMenu != nil {
            topMenu = nil
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
        sheet != nil || launcherOpen || topMenu != nil || bellOpen || overlay != nil
            || dialog != nil
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
        id: UUID = UUID(), lifetime: TimeInterval? = nil, undo: (@Sendable @MainActor () -> Void)? = nil
    ) {
        toast = ToastItem(message, kind: kind, actionTitle: actionTitle, id: id, lifetime: lifetime, undo: undo)
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

/// What the top-bar Brain icon and its panel say.
public struct BrainChip: Equatable, Sendable {
    /// `locked`, `needs_you`, `working` or `idle`.
    public var state: String
    public var line: String
    /// What Brain waits on, in words. Empty when nothing.
    public var needs: [String]
    /// A distil or overview failed in the last day.
    public var attention: Bool
    /// How far the work is (an import), 0...1; nil when not counted.
    public var progress: Double?
    public init(state: String, line: String, needs: [String], attention: Bool, progress: Double? = nil) {
        self.state = state
        self.line = line
        self.needs = needs
        self.attention = attention
        self.progress = progress
    }
}
