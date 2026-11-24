import CoreUI
import SwiftUI

/// Places (mockup 15): every room as a card with its kind, count, AI and last sync; a card opens the place, with a way
/// back. A sealed place shows its name only, and the way to open it. Choosing another place clears the old one from memory.
struct RoomsTab: View {
    let model: BrainModel

    var body: some View {
        Group {
            if model.placeOpen, let r = model.viewing {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Button {
                        withAnimation(Motion.out(Motion.ui)) { model.placeOpen = false }
                    } label: {
                        Label("Places", systemImage: "chevron.left")
                    }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .keyboardShortcut("[", modifiers: .command).environment(\.coreKeycap, "⌘[")
                    .accessibilityIdentifier("brain-places-back")
                    RoomPane(model: model, room: r).id(r.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .task(id: r.id) {
                    if model.inspectingID != r.id, r.lock == nil { await model.inspect(r.id) }
                }
                .transition(.opacity)
            } else {
                grid.transition(.opacity)
            }
        }
        .animation(Motion.out(Motion.ui), value: model.placeOpen)
        .task {
            for r in model.rooms where model.candidates.policy(r.id) == nil { await model.candidates.loadPolicy(r.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-rooms")
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "folder", title: "Places", count: PlaceCards.count(model),
                sub: "Each project is its own place. What Brain learns in one stays there."
            ) {
                if let sync = model.sync { SyncNowTile(sync: sync) }
                if model.canMakeRooms {
                    Button {
                        Task { await model.quickRoom() }
                    } label: {
                        Label("New Place…", systemImage: "plus")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
                    .help("Make a new place (⌘N); ⌥⌘N to choose its kind")
                    .background {
                        Button("New Place (Advanced)") { BrainSheets.openNewRoom(model) }
                            .keyboardShortcut("n", modifiers: [.command, .option])
                            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            ScrollView {
                PlaceCards(model: model)
                Text(SyncWords.neverRead).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Space.s2)
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// One place (2026-11-23, Designs/core/0-10/review/brain/place.html): who it is and how it stands, then Overview, What It
/// Read and Settings. A sealed place shows its name only, and the way to open it.
private struct RoomPane: View {
    let model: BrainModel
    let room: RoomSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let lock = room.lock {
                    CoreNotice(symbol: "lock", title: lock.sentence, tone: .queue) {
                        Button {
                            Task { await model.open(room.id) }
                        } label: {
                            Label("Open with Touch ID", systemImage: "touchid")
                        }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(model.busy != nil)
                    }
                } else {
                    notices
                    switch mode {
                    case .overview: PlaceOverview(model: model, room: room)
                    case .settings: RoomSettings(model: model, room: room)
                    case .items: PlaceRead(model: model, room: room)
                    }
                }
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
        }
    }

    /// Overview and What It Read always; Settings where this Core serves the policy routes.
    private var tabs: [RoomPaneMode] {
        [.overview, .items] + (model.service?.servesCandidates == true ? [.settings] : [])
    }

    private var mode: RoomPaneMode {
        tabs.contains(model.candidates.paneMode) ? model.candidates.paneMode : .overview
    }

    private var place: PlaceWire? { model.calm.places?.first { $0.room == room.id } }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            BrainTile(symbol: room.lock == nil ? "folder" : "lock", lit: room.lock == nil, size: Space.s8 + Space.s4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(room.name).coreFont(size: MacTextSize.large, weight: .semibold).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if room.lock == nil { badge }
                }
                Text(line).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            if room.lock == nil, tabs.count > 1 {
                CoreSegmented(
                    "Place view", segments: tabs.map { CoreSegment($0, $0.title) },
                    selection: Binding(get: { mode }, set: { model.candidates.paneMode = $0 }))
            }
        }
        .help(room.help)
        .contextMenu {
            if room.lock == nil { Button("Seal Place") { Task { await model.seal(room.id) } } }
        }
    }

    /// "Writing its overview" while the Core writes it, "Learning" while it reads, else "Up to date".
    @ViewBuilder private var badge: some View {
        let o: RoomOverviewModel = model.roomOverview
        if o.roomID == room.id, let cur = o.current,
            cur.isWriting || (cur.state == .notWritten && model.writesOverviews && (room.counts?.records ?? 0) > 0)
        {
            StateBadge("Writing its overview", tone: .done, symbol: "sparkles")
        } else if place?.learning == true {
            StateBadge("Learning", tone: .done, symbol: "sparkles")
        } else if place != nil {
            StateBadge("Up to date", tone: .queue, symbol: "checkmark")
        }
    }

    /// "A product · 1,381 things read · learned 12 min ago", with the parts this Core has.
    private var line: String {
        var parts = [room.kind.label]
        if let c = room.counts { parts.append("\(c.records.formatted()) \(c.records == 1 ? "thing" : "things") read") }
        if let at = SyncWords.date(place?.lastLearnedAt) {
            parts.append("learned \(SyncWords.agoInLine(at))")
        } else if let when = model.lastSyncLabel(room) {
            parts.append("synced \(when.lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    /// The key or the cost cap, only when one needs you.
    @ViewBuilder private var notices: some View {
        if let d = model.inspected, d.room.id == room.id {
            if d.room.lease.state == .expiring {
                CoreNotice(
                    symbol: "clock", title: "The key renews in \(BrainWords.unit(d.room.lease.left))",
                    text: "Renew it before then, or the place seals.", tone: .warn)
            }
            if let c = d.cost, c.capReached {
                CoreNotice(
                    symbol: "dollarsign", title: "Monthly cost cap reached",
                    text: "Meaning search is paused for this place. Exact search still works.", tone: .warn)
            }
        }
    }
}

/// One rule as a switch: what it does, its pattern under it, a lock when it cannot change.
struct RuleRow: View {
    let sync: SyncModel
    let rule: RuleWire

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.reason.isEmpty ? rule.pattern : rule.reason).coreFont(size: MacTextSize.body, weight: .medium)
                if !rule.reason.isEmpty {
                    Text(rule.pattern).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            Spacer(minLength: Space.s3)
            if rule.locked {
                Image(systemName: "lock").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .help("This rule is always on.").accessibilityHidden(true)
            }
            CoreSwitch(
                isOn: Binding(get: { rule.enabled }, set: { on in Task { await sync.toggleRule(rule, on: on) } })
            )
            .accessibilityLabel(rule.reason.isEmpty ? rule.pattern : rule.reason)
            .disabled(rule.locked)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(minHeight: Space.s8 + Space.s4)
        // The whole row is the switch's target, as in the mockup; the switch stays the keyboard path.
        .contentShape(Rectangle())
        .onTapGesture { if !rule.locked { Task { await sync.toggleRule(rule, on: !rule.enabled) } } }
        .modifier(BrainRowHover(enabled: !rule.locked))
    }
}
