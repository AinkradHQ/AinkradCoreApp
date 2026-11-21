import CoreUI
import SwiftUI

/// The Brain: one app with a sidebar (Home, the four areas, Places, To check, Sources, Activity, the search) once it has
/// rooms (`BrainCalmView`). Before that, the header and one card that says why it is empty and what to do.
/// The keyboard drives it: ⌘1 to ⌘9 sections, ⌘E search, ⌘I Import, ⌘N a new room (sample), Esc back.
struct BrainPane: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: BrainModel
    @FocusState private var paneFocus: Bool

    private var ready: Bool { model.load == .ready && model.setup == .ready && !model.rooms.isEmpty }

    var body: some View {
        Group {
            if ready {
                BrainCalmView(brain: model)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    AppHeader {
                    } actions: {
                        actions
                    }
                    .background { importKey }
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            if let n = model.notice { notice(n) }
                            content
                        }
                        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .coreFont(size: MacTextSize.body)
        .foregroundStyle(GlassInk.primary)
        .focusable().focused($paneFocus).focusEffectDisabled()
        .onAppear { paneFocus = true }
        .retakeFocus(after: model.host.shell, pane: "brain") { paneFocus = true }
        .paneLook(AppLookPrefs.shared("brain").look)
        .appLookTheme(AppLookPrefs.shared("brain"))
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-pane")
    }

    /// Before the first rooms: Import, or a new room on the sample.
    @ViewBuilder private var actions: some View {
        if model.isSample {
            AppStatChip("testtube.2", "Sample data", GlassInk.slate).help(BrainWords.sampleLabel)
                .accessibilityLabel(BrainWords.sampleLabel)
        }
        if model.service?.importRoutes != nil, model.load == .ready {
            AppActionTile(
                title: "Import…", symbol: "square.and.arrow.down", key: "⌘I", hue: GlassInk.accent(paneAccent)
            ) {
                model.openImport()
            }
        }
        if model.load == .ready, model.canMakeRooms {
            AppActionTile(
                title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent), prominent: true
            ) {
                Task { await model.quickRoom() }
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    /// ⌘I opens Import before the first rooms too.
    private var importKey: some View {
        Button("Import into the Brain") { model.openImport() }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(model.service?.importRoutes == nil)
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func notice(_ text: String) -> some View {
        CoreNotice(symbol: "exclamationmark.triangle", title: text, tone: .fail) {
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
            EmptyView()
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
