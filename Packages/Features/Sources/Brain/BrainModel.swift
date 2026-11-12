import Admin
import AppKit
import Foundation
import Observation
import Shell
import SwiftUI

/// The Brain pane's state. It owns the room list, the Overview and the one room view, asks for Touch ID through the host
/// for opening a room, widening one and clearing Paused, and registers the launcher entries, the bell source and the Look.
///
/// Safety first: the pane has its own *viewing room* (separate from the room of any running session, Q4). A room view
/// shows exactly one room, and switching, sealing, an expired lease or a locked Mac clears it from memory first.
@MainActor @Observable
public final class BrainModel {
    let host: any AdminHost
    public private(set) var service: (any BrainService)?
    public internal(set) var load: BrainLoad = .unavailable
    /// What the Core has of the Brain. Stand-in services are always `.ready`.
    public internal(set) var setup: BrainSetup = .ready
    /// The import in this session, kept while its sheet is closed so a collect in progress is not lost.
    public internal(set) var importer: ImportModel?
    /// The sources the wizard offers. Tests and the Debug gallery replace it; the default reads this Mac's AI session histories, docs and chat exports.
    @ObservationIgnored public var importSources: @Sendable () -> [any ImportSource] = {
        ImportSources.standard()
    }
    /// Sync now, sources and rules on the Rooms page; nil until a service attaches.
    public private(set) var sync: SyncModel?
    /// Every known room. A sealed one carries a name and mode only (`RoomSummary.counts` is nil).
    public private(set) var rooms: [RoomSummary] = []
    public private(set) var overview: BrainOverview?
    public var tab: BrainTab = .overview
    /// What the pane is looking at (admin view).
    public private(set) var viewingID: String?
    /// The Rooms tab's room view: one room, cleared when the viewing room changes.
    public private(set) var inspected: RoomDetail?
    public private(set) var inspectingID: String?
    /// A refusal or failure for the action just taken, in words.
    public internal(set) var notice: String?
    public internal(set) var busy: String?
    /// The Inbox tab's content: the viewing room's lists and the unclassified captures. Cleared with the room view.
    public let inboxState = InboxState()
    @ObservationIgnored private var bellIDs: Set<String> = []
    @ObservationIgnored private var lockWatch: (any NSObjectProtocol)?

    /// Activity and Checks keep their own state; both read this model for rooms, Paused and the service.
    @ObservationIgnored public private(set) var activity: ActivityModel!
    @ObservationIgnored public private(set) var checks: ChecksModel!

    public init(host: any AdminHost) {
        self.host = host
        activity = ActivityModel(brain: self)
        checks = ChecksModel(brain: self)
    }

    // MARK: connection

    /// Attach a service. Release attaches none until Core serves the Brain; Debug demo and tests attach the sample.
    public func use(_ service: any BrainService) {
        self.service = service
        let sources = importSources
        sync = SyncModel(host: host, service: service, sources: { sources() })
        registerActions()
        load = .loading
        Task { await reload() }
    }

    public func detach() {
        service = nil
        for id in Self.actionIDs { host.shell.launcher.unregister(id) }
        activity.reset()
        checks.reset()
        clearRoomView()
        rooms = []
        overview = nil
        viewingID = nil
        importer = nil
        sync?.stopTimer()
        sync = nil
        setup = .absent
        load = .unavailable
        refreshBell()
    }

    public var isSample: Bool { service?.isSample ?? false }
    /// A real Core makes rooms by an import, not by a button.
    public var canMakeRooms: Bool { isSample }
    /// The tab bar: only where the Brain has rooms to look at.
    public var tabsVisible: Bool { load != .unavailable && setup == .ready }

    // MARK: derived

    public var viewing: RoomSummary? { rooms.first { $0.id == viewingID } }
    /// Why the viewing room has nothing on screen, or nil.
    public var viewingLock: RoomLock? { viewing?.lock }
    public var mountedRooms: [RoomSummary] { rooms.filter(\.mounted) }
    public var sealedRooms: [RoomSummary] { rooms.filter { !$0.mounted } }
    public func room(_ id: String?) -> RoomSummary? { rooms.first { $0.id == id } }

    /// Q2: a need that names a room appears only for a mounted room. Counts are data too.
    public var visibleNeeds: [NeedItem] {
        (overview?.needs ?? []).filter { n in n.room.map { room($0)?.mounted ?? false } ?? true }
    }
    public var needsTotal: Int { visibleNeeds.reduce(0) { $0 + $1.n } }
    /// Mounted rooms only, never a sealed one.
    public var recordsPerRoom: [(room: RoomSummary, counts: RoomCounts)] {
        mountedRooms.compactMap { r in r.counts.map { (r, $0) } }
    }
    public var health: BrainHealth { overview?.health ?? .healthy }
    /// Mounted rooms whose search is stopped, by name.
    public var pausedNames: [String] {
        (overview?.pausedRooms ?? []).compactMap { room($0) }.filter(\.mounted).map(\.name)
    }
    public func roomName(_ need: NeedItem) -> String? { need.room.flatMap { room($0)?.name } }

    public func tabCount(_ tab: BrainTab) -> Int {
        switch tab {
        case .inbox: visibleNeeds.filter { $0.tab == .inbox }.reduce(0) { $0 + $1.n }
        case .checks: visibleNeeds.filter { $0.tab == .checks }.reduce(0) { $0 + $1.n }
        default: -1
        }
    }

    /// The pane head chip: Paused (red), Needs you with its count (blue), or Healthy (green).
    var chip: PaneChip {
        switch health {
        case .paused: PaneChip("Paused, \(needsTotal)", tone: .fail, symbol: "pause.circle")
        case .needsYou: PaneChip("Needs you, \(needsTotal)", tone: .run, symbol: "hand.raised")
        case .healthy: PaneChip("Healthy", tone: .done, symbol: "checkmark.circle")
        }
    }

    // MARK: loading

    func reload() async {
        guard let service else { return }
        do {
            let st = try await service.setup()
            guard self.service != nil else { return }
            setup = st
            switch st {
            case .absent:
                rooms = []
                overview = nil
                load = .unavailable
                refreshBell()
                return
            case .locked, .notSetUp:
                rooms = []
                overview = nil
                load = .ready
                refreshBell()
                return
            case .ready: break
            }
            async let r = service.rooms()
            async let o = service.overview()
            let (rs, ov) = try await (r, o)
            guard self.service != nil else { return }
            rooms = rs
            overview = ov
            load = .ready
            if let sync, sync.status == nil {
                await sync.reload()
                // Real Cores only: the sample has no Mac collectors to run.
                if service.importRoutes != nil { sync.startTimer() }
            }
            if viewing == nil { viewingID = rs.first { $0.mounted }?.id ?? rs.first?.id }
            // A room that sealed or lost its lease under us must not stay on screen.
            if let id = inspectingID, room(id)?.lock != nil { clearRoomView() }
            if viewingLock != nil { clearRoomView() }
        } catch {
            load = .failed(BrainWords.failure(error))
        }
        refreshBell()
        host.shell.updatePane("brain", sub: .some(viewing?.name), chip: .some(chip))
    }

    public func retry() {
        load = .loading
        Task { await reload() }
    }

    // MARK: rooms

    /// Drops everything a room view held. Called before any switch, seal or lock, not after.
    func clearRoomView() {
        activity?.clear()
        inboxState.clear()
        inspected = nil
        inspectingID = nil
    }

    /// Switches the pane's viewing room. The old room's view is cleared first.
    public func view(_ id: String) {
        guard id != viewingID else { return }
        clearRoomView()
        viewingID = id
        notice = nil
        host.shell.updatePane("brain", sub: .some(viewing?.name))
    }

    /// Opens one room's view in the Rooms tab (a mounted room only).
    public func inspect(_ id: String) async {
        clearRoomView()
        inspectingID = id
        guard let service, room(id)?.lock == nil else { return }
        do {
            let d = try await service.room(id)
            // Only if nothing changed while the answer was on its way.
            if inspectingID == id { inspected = d }
        } catch {
            if inspectingID == id { notice = BrainWords.failure(error) }
        }
    }

    public func closeInspect() { clearRoomView() }

    public func seal(_ id: String) async {
        guard let service else { return }
        if id == viewingID || id == inspectingID { clearRoomView() }
        busy = "seal"
        defer { busy = nil }
        do {
            try await service.sealRoom(id)
            host.shell.showToast("Room sealed")
        } catch { notice = BrainWords.failure(error) }
        await reload()
    }

    /// Opens a sealed room. Touch ID first; a cancelled one leaves the room sealed.
    @discardableResult
    public func open(_ id: String) async -> Bool {
        guard let service else { return false }
        busy = "open"
        defer { busy = nil }
        do {
            try await host.elevated("Open this room on this Mac.", done: "opened", keepsEdit: false) {
                try await service.openRoom(id)
            }
            viewingID = id
            await reload()
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    /// Clears Paused. Touch ID first; cancelled leaves it paused.
    @discardableResult
    public func clearPaused() async -> Bool {
        guard let service else { return false }
        busy = "clear"
        defer { busy = nil }
        do {
            try await host.elevated(
                "Clear the pause so search across rooms resumes.", done: "cleared", keepsEdit: false
            ) { try await service.clearPaused() }
            host.shell.showToast("Pause cleared")
            await reload()
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    /// Makes a room (sample only: a real Core makes rooms by an import).
    @discardableResult
    public func createRoom(_ draft: NewRoomDraft) async -> Bool {
        guard let service else { return false }
        busy = "create"
        defer { busy = nil }
        do {
            let made = try await service.createRoom(draft)
            host.shell.showToast("Room \(made.name) created")
            await reload()
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            notice = BrainWords.failure(error)
            return false
        }
    }

    /// "New room", "New room 2"...: the quick path needs no typing.
    public var quickName: String {
        let names = Set(rooms.map(\.name))
        if !names.contains("New room") { return "New room" }
        return (2...).lazy.map { "New room \($0)" }.first { !names.contains($0) } ?? "New room"
    }

    public func quickRoom() async { _ = await createRoom(.quick(name: quickName)) }

    public func dismissNotice() { notice = nil }

    // MARK: shell

    /// Opens the pane on a tab.
    public func show(_ tab: BrainTab = .overview) {
        self.tab = tab
        var spec = PaneSpec(
            id: "brain", title: "Brain", sub: viewing?.name, symbol: "brain", chip: chip, minWidth: 720
        ) { BrainPane(model: self) }
        spec.tab = "Brain"
        host.shell.openPane(spec)
        if load == .loading || (service != nil && overview == nil) { Task { await reload() } }
    }

    /// The bell carries room names (Q3, Mac) and counts, never a title or snippet. Stale items go away.
    func refreshBell() {
        let bell = host.shell.bell
        var live: Set<String> = []
        for n in visibleNeeds {
            let id = "brain.\(n.id)"
            live.insert(id)
            let paused = n.kind == .paused
            bell.add(
                BellItem(
                    id: id, kind: paused ? .alarm : .approval,
                    title: BrainWords.bell(kind: n.kind, n: n.n, room: roomName(n), pausedRooms: pausedNames.count),
                    sub: "Brain",
                    actions: [BellAction("Open", primary: true) { [weak self] in self?.show(n.tab) }]))
        }
        for id in bellIDs.subtracting(live) { bell.remove(id) }
        bellIDs = live
    }

    /// What the bell shows now, as text (read by tests and nothing else).
    var bellTexts: [String] {
        visibleNeeds.map {
            BrainWords.bell(kind: $0.kind, n: $0.n, room: roomName($0), pausedRooms: pausedNames.count)
        }
    }

    private static let actionIDs = ["brain-open-room", "brain-new-room", "brain-new-room-advanced", "brain-import"]
    @ObservationIgnored private var installed = false

    private func entry(
        _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String], action: Bool = false,
        _ run: @escaping @MainActor (BrainModel) -> Void
    ) {
        host.shell.launcher.register(
            LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys, isAction: action) {
                [weak self] in if let self { run(self) }
            })
    }

    /// The room actions need a service to act on: registered when one attaches, withdrawn when it goes.
    private func registerActions() {
        guard installed else { return }
        if service?.importRoutes != nil {
            entry(
                "brain-import", "Import into the Brain…", "Collect your AI sessions into rooms",
                "square.and.arrow.down",
                ["import", "sessions", "rooms", "claude"], action: true
            ) { $0.openImport() }
        }
        entry(
            "brain-open-room", "Open room…", "Pick a room to look at", "lock.open", ["room", "mount", "unseal"],
            action: true
        ) { $0.show(.rooms) }
        guard isSample else { return }
        entry(
            "brain-new-room", "New room", "Makes a room at once", "plus", ["create", "room"],
            action: true
        ) { m in
            m.show(.rooms)
            Task { await m.quickRoom() }
        }
        entry(
            "brain-new-room-advanced", "New room (advanced)…", "Name it and choose its kind",
            "slider.horizontal.3", ["create", "room"], action: true
        ) { m in
            m.show(.rooms)
            BrainSheets.openNewRoom(m)
        }
    }

    /// Launcher entries, the bell watch and the Look section in Settings.
    public func install() {
        let shell = host.shell
        installed = true
        entry("brain", "Brain", "Rooms, memory and health", "brain", ["memory", "rooms", "sealed", "health"]) {
            $0.show(.overview)
        }
        entry("brain-how", "How the Brain works", "What it keeps and where", "questionmark.circle", ["help", "brain"]) {
            BrainHowItWorks.open($0.host.shell)
        }
        if service != nil { registerActions() }
        shell.settings.section(
            SettingsSection(
                id: "brain-link", group: .apps, title: "Brain", sub: "Look of the memory app", symbol: "brain",
                order: 5
            ) { BrainLookSection(model: self) })
        // A locked Mac clears the room view from memory (security rule 7).
        lockWatch = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.clearRoomView() } }
    }
}
