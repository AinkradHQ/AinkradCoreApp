import CoreUI
import SwiftUI

/// The Brain, in the shape of every other Core app: tab tiles and action tiles in one header, the open-room bar under it,
/// the tab below, and a quiet footer. Overview and Checks are global; the room picker sits inside Rooms, Inbox and Activity,
/// the tabs that look at one room. The keyboard drives it: ⌘1 to ⌘5 tabs, ⌘N a new room, ⌥⌘N the advanced sheet, Esc back.
struct BrainPane: View {
    let model: BrainModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                // No service attached: nothing to look at, so no tabs over the unavailable card.
                if model.tabsVisible {
                    ForEach(Array(model.visibleTabs.enumerated()), id: \.offset) { i, t in
                        AppFilterTile(
                            title: t.title, count: model.tabCount(t), on: model.currentTab == t, key: "⌘\(i + 1)"
                        ) {
                            go(t)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                        .accessibilityIdentifier("brain-nav-\(t.rawValue)")
                    }
                }
            } actions: {
                actions
            }
            .background { importKey }
            if model.load == .ready, model.setup == .ready, !model.rooms.isEmpty, let sync = model.sync,
                model.currentTab == .rooms || model.currentTab == .sources
            {
                SyncBannerView(brain: model, sync: sync)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
            }
            if model.currentTab == .rooms, model.load == .ready, model.setup == .ready, !model.rooms.isEmpty {
                // The Rooms page fills the pane: its list and its room each scroll on their own.
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let n = model.notice { notice(n) }
                    BrainConditions(model: model)
                    RoomsTab(model: model)
                }
                .coreFont(size: MacTextSize.body)
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        if model.load == .ready, !model.rooms.isEmpty, showsRoomBar { RoomBar(model: model) }
                        if let n = model.notice { notice(n) }
                        content
                    }
                    .coreFont(size: MacTextSize.body)
                    .foregroundStyle(GlassInk.primary)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.isSample { footer }
            }
        }
        .focusable().focused($paneFocus).focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "brain") { paneFocus = true }
        .paneLook(BrainPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-pane")
    }

    /// Rooms and Sources: when this Mac last synced and Sync now. Before the first rooms: Import.
    @ViewBuilder private var actions: some View {
        let ready = model.setup == .ready && model.load == .ready
        if ready, !model.rooms.isEmpty, let sync = model.sync,
            model.currentTab == .rooms || model.currentTab == .sources
        {
            SyncNowTile(sync: sync)
        } else if model.service?.importRoutes != nil, model.load == .ready, model.setup != .ready || model.rooms.isEmpty
        {
            AppActionTile(title: "Import…", symbol: "square.and.arrow.down", key: "⌘I", hue: GlassInk.blue) {
                model.openImport()
            }
        }
        if model.currentTab == .rooms, model.load == .ready, model.canMakeRooms {
            AppActionTile(
                title: "New room (advanced)…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue
            ) {
                BrainSheets.openNewRoom(model)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            AppActionTile(title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                Task { await model.quickRoom() }
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    /// ⌘I opens Import from every tab, also where the header shows Sync now instead of the Import tile.
    private var importKey: some View {
        Button("Import into the Brain") { model.openImport() }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(model.service?.importRoutes == nil)
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    /// Rooms, Inbox (but not the no-room list) and Activity look at one room. Overview and Checks are global.
    private var showsRoomBar: Bool {
        switch model.currentTab {
        case .activity: true
        case .inbox: model.inboxState.list != .noRoom
        case .overview, .checks, .rooms, .sources: false
        }
    }

    private func go(_ t: BrainTab) {
        withAnimation(.smooth(duration: 0.3)) {
            model.closeInspect()
            model.tab = t
        }
        paneFocus = true
    }

    private func notice(_ text: String) -> some View {
        CoreNotice(symbol: "exclamationmark.circle", title: text, tone: .fail) {
            Button("Dismiss") { model.dismissNotice() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .unavailable:
            BrainStateCard(
                symbol: "brain", title: BrainWords.unavailableTitle, text: BrainWords.unavailableText,
                secondary: CoreAction("How the Brain works") { BrainHowItWorks.open(model.host.shell) }
            )
            .accessibilityIdentifier("brain-unavailable")
        case .loading:
            BrainSkeleton(shape: .page).accessibilityIdentifier("brain-loading")
        case .failed(let why):
            BrainStateCard(
                symbol: "exclamationmark.triangle", title: "The Brain did not load", text: why,
                primary: CoreAction("Try again") { model.retry() })
        case .ready where model.setup != .ready:
            setupCard
        case .ready where model.rooms.isEmpty:
            BrainStateCard(
                symbol: "tray", title: "No rooms yet",
                text: "A room keeps one kind of memory sealed apart from every other. Make the first one.",
                secondary: CoreAction("New room (advanced)…") { BrainSheets.openNewRoom(model) },
                primary: CoreAction("New room") { Task { await model.quickRoom() } })
        case .ready:
            BrainConditions(model: model)
            Group {
                switch model.currentTab {
                case .overview: OverviewTab(model: model)
                case .rooms: RoomsTab(model: model)
                case .sources: if let sync = model.sync { SourcesTab(brain: model, sync: sync) }
                case .inbox: if model.isSample { InboxTab(model: model) } else { BrainComingLater(title: "The Inbox") }
                case .activity:
                    if model.isSample { ActivityTab(model: model) } else { BrainComingLater(title: "Activity") }
                case .checks: if model.isSample { ChecksTab(model: model) } else { BrainComingLater(title: "Checks") }
                }
            }
            .transition(.opacity)
        }
    }

    /// The Core has the Brain, but it is locked or has no rooms yet; or an import is under way.
    @ViewBuilder private var setupCard: some View {
        let how = CoreAction("How the Brain works") { BrainHowItWorks.open(model.host.shell) }
        switch model.setup {
        case .locked(let why):
            BrainStateCard(symbol: "lock", title: "The Brain is locked", text: why, secondary: how)
                .accessibilityIdentifier("brain-locked")
        default:
            if model.importer?.isActive == true {
                BrainStateCard(
                    symbol: "square.and.arrow.down", title: "Import in progress",
                    text: "Your sessions are being collected and sorted into rooms. Nothing is kept until you import.",
                    secondary: how, primary: CoreAction("Continue") { model.openImport() }
                )
                .accessibilityIdentifier("brain-importing")
            } else {
                BrainStateCard(
                    symbol: "tray", title: "Nothing in the Brain yet",
                    text:
                        "Import your AI sessions to make the first rooms. You review every room before anything is kept.",
                    secondary: how, primary: CoreAction("Import") { model.openImport() }
                )
                .accessibilityIdentifier("brain-not-set-up")
            }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: Space.s3) {
            if model.isSample {
                AppStatChip("testtube.2", BrainWords.sampleLabel, GlassInk.slate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3).frame(minHeight: MacSize.controlSm)
    }
}

/// The open-room bar: which room, sealed or open, where it lives, who may read it, how long its key lasts.
struct RoomBar: View {
    let model: BrainModel
    var body: some View {
        let r = model.viewing
        HStack(spacing: Space.s3) {
            CoreSelect(
                nil, selection: Binding(get: { model.viewingID ?? "" }, set: { model.view($0) }),
                options: model.rooms.map {
                    CoreSelectOption(
                        $0.id, $0.name, symbol: $0.mounted ? nil : "lock", note: $0.mounted ? nil : "Sealed")
                }
            )
            .frame(width: Space.s8 * 7)
            if let r {
                if r.lock == nil {
                    StateBadge("Open", tone: .done, symbol: "lock.open")
                        .help("\(BrainWords.keyRenews(r.lease.left)). \(BrainWords.leaseHelp)")
                } else {
                    StateBadge(r.lock == .expired ? "Key ended" : "Sealed", tone: .queue, symbol: "lock")
                }
            }
            Spacer(minLength: Space.s2)
            if let r {
                if r.lock == nil {
                    Button {
                        Task { await model.seal(r.id) }
                    } label: {
                        Label("Seal room", systemImage: "lock")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.busy != nil)
                } else {
                    Button {
                        Task { await model.open(r.id) }
                    } label: {
                        Label("Open with Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.busy != nil)
                }
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .coreWell()
        .help(r?.help ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-roombar")
    }
}
