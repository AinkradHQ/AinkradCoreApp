import CoreUI
import SwiftUI

/// The Brain, in the shape of every other Core app: tab tiles and action tiles in one header, the open-room bar under it,
/// the tab below, and a quiet footer. Overview and Rooms are real in this change; Inbox, Activity and Checks are placeholders
/// the next changes fill. The keyboard drives it: ⌘1 to ⌘5 tabs, ⌘N a new room, ⌥⌘N the advanced sheet, Esc back.
struct BrainPane: View {
    let model: BrainModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                ForEach(Array(BrainTab.allCases.enumerated()), id: \.offset) { i, t in
                    AppFilterTile(title: t.title, count: model.tabCount(t), on: model.tab == t, key: "⌘\(i + 1)") {
                        go(t)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .accessibilityIdentifier("brain-nav-\(t.rawValue)")
                }
            } actions: {
                if model.tab == .rooms, model.load == .ready {
                    AppActionTile(title: "Advanced…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue) {
                        BrainSheets.openNewRoom(model)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    AppActionTile(title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                        Task { await model.quickRoom() }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            if model.load == .ready, !model.rooms.isEmpty { RoomBar(model: model).padding(.horizontal, Space.s4) }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let n = model.notice { notice(n) }
                    content
                }
                .font(.system(size: MacTextSize.body))
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .focusable().focused($paneFocus).focusEffectDisabled()
            .onAppear { paneFocus = true }
            .onKeyPress(.escape) {
                guard model.inspectingID != nil else { return .ignored }
                withAnimation(.smooth(duration: 0.25)) { model.closeInspect() }
                return .handled
            }
            footer
        }
        .paneLook(BrainPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-pane")
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
                symbol: "brain", title: BrainWords.unavailableTitle, text: BrainWords.unavailableText
            )
            .accessibilityIdentifier("brain-unavailable")
        case .loading:
            BrainStateCard(symbol: "hourglass", title: "Loading the Brain", text: "Reading your rooms.")
        case .failed(let why):
            BrainStateCard(symbol: "exclamationmark.triangle", title: "The Brain did not load", text: why, tone: .fail)
            {
                Button("Cancel") { model.host.shell.closePane("brain") }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Retry") { model.retry() }.buttonStyle(CoreButtonStyle(.prominent))
            }
        case .ready where model.rooms.isEmpty:
            BrainStateCard(
                symbol: "tray", title: "No rooms yet",
                text: "A room keeps one kind of memory sealed apart from every other. Make the first one."
            ) {
                Button("New room (advanced)…") { BrainSheets.openNewRoom(model) }.buttonStyle(
                    CoreButtonStyle(.secondary))
                Button("New room") { Task { await model.quickRoom() } }.buttonStyle(CoreButtonStyle(.prominent))
            }
        case .ready:
            BrainConditions(model: model)
            Group {
                switch model.tab {
                case .overview: OverviewTab(model: model)
                case .rooms: RoomsTab(model: model)
                case .inbox: Placeholder(title: "Inbox", text: "Memories waiting for you, conflicts and blocked notes.")
                case .activity: ActivityTab(model: model)
                case .checks: ChecksTab(model: model)
                case .inbox: InboxTab(model: model)
                case .activity:
                    Placeholder(title: "Activity", text: "Who searched, saved or was refused, room by room.")
                case .checks: Placeholder(title: "Checks", text: "Run the safety checks and see their history.")
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: Space.s3) {
            if model.isSample {
                AppStatChip("testtube.2", BrainWords.sampleLabel, GlassInk.slate)
            }
            Spacer(minLength: 0)
            if model.tab == .rooms, model.inspectingID != nil {
                Text("Esc back to all rooms").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3).frame(minHeight: MacSize.controlSm)
    }
}

/// A quiet placeholder for a tab the next change builds. It says so in plain words.
private struct Placeholder: View {
    let title: String
    let text: String
    var body: some View {
        BrainStateCard(symbol: "clock", title: "\(title) is coming in the next change", text: text)
            .accessibilityIdentifier("brain-placeholder")
    }
}

/// The open-room bar: which room, sealed or open, where it lives, who may read it, how long its key lasts.
struct RoomBar: View {
    let model: BrainModel
    var body: some View {
        let r = model.viewing
        HStack(spacing: Space.s3) {
            Image(systemName: r?.lock == nil ? "lock.open" : "lock").foregroundStyle(GlassInk.secondary)
                .accessibilityHidden(true)
            CoreSelect(
                nil, selection: Binding(get: { model.viewingID ?? "" }, set: { model.view($0) }),
                options: model.rooms.map {
                    CoreSelectOption(
                        $0.id, $0.name, symbol: $0.mounted ? nil : "lock", note: $0.mounted ? nil : "Sealed")
                }
            )
            .frame(width: Space.s8 * 7)
            if let r {
                BrainChip(
                    r.lock == nil ? "Open" : r.lock == .expired ? "Lease ended" : "Sealed",
                    r.lock == nil ? GlassInk.green : GlassInk.slate)
                RoomChips(room: r)
                Text(r.lock == nil ? "Lease \(r.lease.left) left" : "Nothing from it is on screen.")
                    .font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
                    .lineLimit(1)
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
