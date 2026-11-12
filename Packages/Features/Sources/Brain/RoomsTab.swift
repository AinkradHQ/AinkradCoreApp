import CoreUI
import SwiftUI

/// Rooms: the list of rooms on the left, the chosen room on the right with its search and its rules. A sealed room shows
/// its name only, and the way to open it. Choosing another room clears the old one from memory first.
struct RoomsTab: View {
    let model: BrainModel

    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            RoomList(model: model).frame(width: Space.s8 * 13)
            Group {
                if let r = model.viewing {
                    RoomPane(model: model, room: r).id(r.id)
                } else {
                    Text("Choose a room.").foregroundStyle(GlassInk.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coreWell()
        }
        .animation(Motion.out(Motion.ui), value: model.viewingID)
        .task {
            if let id = model.viewingID, model.inspectingID != id, model.viewing?.lock == nil {
                await model.inspect(id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-rooms")
    }
}

/// The left column: every room with its count and when it last took something new.
private struct RoomList: View {
    let model: BrainModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("Rooms").coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                CountBadge(model.rooms.count, tone: .quiet, label: "rooms")
            }
            .padding(.horizontal, Space.s3)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.rooms) { r in RoomRow(model: model, room: r) }
                }
            }
            .scrollIndicators(.automatic)
            Text(SyncWords.neverRead).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s3)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct RoomRow: View {
    let model: BrainModel
    let room: RoomSummary

    var body: some View {
        CoreRow(
            room.name, subtitle: subtitle, symbol: room.lock == nil ? "folder" : "lock",
            selected: room.id == model.viewingID, action: pick
        ) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(room.counts.map { $0.records.formatted() } ?? "Sealed")
                    .coreFont(size: MacTextSize.body, weight: .medium).monospacedDigit()
                HStack(spacing: 0) {
                    if let n = newCount, n > 0 {
                        Text("+\(n) new · ").foregroundStyle(GlassInk.blueInk)
                    }
                    Text(model.lastSyncLabel(room) ?? "")
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .help(room.help)
        .contextMenu {
            if room.lock == nil {
                Button("Seal Room") { Task { await model.seal(room.id) } }
            } else {
                Button("Open with Touch ID") { Task { await model.open(room.id) } }
            }
        }
        .accessibilityIdentifier("brain-room-\(room.id)")
    }

    private var subtitle: String {
        if room.lock != nil { return "Sealed · \(room.kind.label)" }
        let types = BrainWords.breakdown(room.counts?.byType ?? [])
        return types.isEmpty ? "\(room.kind.label) · \(room.mode.label)" : types
    }

    /// What the last sync added here.
    private var newCount: Int? {
        model.sync?.outcome?.routed.first { $0.room == room.id }?.sources
    }

    private func pick() {
        model.view(room.id)
        guard room.lock == nil else { return }
        Task { await model.inspect(room.id) }
    }
}

/// The chosen room: who it is, its search and its rules.
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
                    if let sync = model.sync {
                        RoomSearch(sync: sync, room: room)
                        RoomRules(sync: sync, room: room)
                    }
                }
            }
            .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            IconTile(room.lock == nil ? "folder" : "lock", hue: room.lock == nil ? GlassInk.blue : GlassInk.slate)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(line).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            VStack(alignment: .trailing, spacing: 2) {
                if let when = model.lastSyncLabel(room) { Text("Synced \(when.lowercased())") }
                Text("\(room.mode.label) · \(room.provider.label)").help(room.provider.help)
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .help(room.help)
        .contextMenu {
            if room.lock == nil { Button("Seal Room") { Task { await model.seal(room.id) } } }
        }
    }

    private var line: String {
        var parts = [room.kind.label]
        if let c = room.counts { parts.append(BrainWords.plural(c.records, "item", "items")) }
        return parts.joined(separator: " · ")
    }

    /// The key or the cost cap, only when one needs you.
    @ViewBuilder private var notices: some View {
        if let d = model.inspected, d.room.id == room.id {
            if d.room.lease.state == .expiring {
                CoreNotice(
                    symbol: "clock", title: "The key renews in \(BrainWords.unit(d.room.lease.left))",
                    text: "Renew it before then, or the room seals.", tone: .warn)
            }
            if let c = d.cost, c.capReached {
                CoreNotice(
                    symbol: "dollarsign", title: "Monthly cost cap reached",
                    text: "Meaning search is paused for this room. Exact search still works.", tone: .warn)
            }
        }
    }
}

/// One room's search, and its newest items while nothing is asked. Matches are marked; nothing from another room is ever
/// asked for.
private struct RoomSearch: View {
    let sync: SyncModel
    let room: RoomSummary
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var latest: [LatestItem] = []
    @State private var asked = ""
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            field
            if asked.isEmpty, !latest.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("Latest").coreFont(size: MacTextSize.headline, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: Space.s3)
                        Text("Newest first").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(latest) { LatestRow(item: $0, room: room.name) }
                    }
                }
                .transition(.opacity)
            } else if !asked.isEmpty {
                if hits.isEmpty {
                    Text("Nothing in \(room.name) matches “\(asked)”.").foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(hits) { HitRow(hit: $0, room: room.name) }
                    }
                }
            }
        }
        .task { latest = await sync.latest(room: room.id) }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else {
                hits = []
                asked = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let found = await sync.search(room: room.id, query: q)
            if Task.isCancelled { return }
            hits = found
            asked = q
        }
    }

    private var field: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("Search \(room.name)", text: $query)
                .textFieldStyle(.plain).focused($focused)
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .accessibilityLabel("Search \(room.name)")
            if !asked.isEmpty {
                Text(BrainWords.plural(hits.count, "result", "results"))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else {
                Text("⌘F").coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(minHeight: MacSize.controlLg + Space.s1)
        .coreFieldSurface(focused: focused)
        .background {
            Button("Search this room") { focused = true }.keyboardShortcut("f", modifiers: .command)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// One of the room's newest items: its type, its title with source and room under it, and its day at the right.
private struct LatestRow: View {
    let item: LatestItem
    let room: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(MemoryType(rawValue: item.type)?.label ?? item.type)
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 2.5, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(2)
                Text("\(SyncWords.title(item.sourceKind, ImportSources.standard())) · \(room)")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let d = SyncWords.date(item.startedAt) {
                Text(d.formatted(.dateTime.day().month(.abbreviated)))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).fixedSize()
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .modifier(BrainRowHover())
        .accessibilityElement(children: .combine)
    }
}

/// One search hit: its source, its title and the snippet with every match marked.
private struct HitRow: View {
    let hit: SearchHit
    let room: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(SyncWords.title(hit.sourceKind, ImportSources.standard()))
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 2.5, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.marked(hit.title)).coreFont(size: MacTextSize.body, weight: .medium)
                Text(Self.marked(hit.snippet)).foregroundStyle(GlassInk.secondary).lineLimit(2)
                Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .modifier(BrainRowHover())
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts = [room]
        if let d = SyncWords.date(hit.startedAt) { parts.append(d.formatted(.dateTime.day().month(.abbreviated))) }
        return parts.joined(separator: " · ")
    }

    /// « » become a marked run: semibold on a soft blue.
    static func marked(_ s: String) -> AttributedString {
        var out = AttributedString()
        for p in SearchHit.pieces(of: s) {
            var run = AttributedString(p.text)
            if p.match {
                run.inlinePresentationIntent = .stronglyEmphasized
                run.backgroundColor = GlassInk.blue.opacity(0.24)
                run.foregroundColor = GlassInk.primary
            }
            out += run
        }
        return out
    }
}

/// The rules that name this room. Each switch asks for Touch ID; a locked one cannot change.
private struct RoomRules: View {
    let sync: SyncModel
    let room: RoomSummary

    var body: some View {
        let rules = sync.rules.filter { $0.room == room.id }
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("Room rules").coreFont(size: MacTextSize.headline, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.s3)
                    Text("Changing a rule asks for Touch ID").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .padding(.horizontal, 2)
                VStack(spacing: 2) { ForEach(rules) { RuleRow(sync: sync, rule: $0) } }
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
