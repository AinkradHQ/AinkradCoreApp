import CoreUI
import SwiftUI

/// Places (mockup 15): every room as a card with its kind, count, AI and last sync; a card opens the place, with a way
/// back. A sealed place shows its name only, and the way to open it. Choosing another place clears the old one from memory.
struct RoomsTab: View {
    @Environment(\.coreAccent) private var paneAccent
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
                        .coreWell()
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
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainPageHead(
                "Places",
                "\(BrainWords.plural(model.rooms.count, "place", "places")). Each one is its own room, and nothing crosses between them."
            ) {
                if let sync = model.sync { SyncNowTile(sync: sync) }
                if model.canMakeRooms {
                    AppActionTile(
                        title: "New room (advanced)…", symbol: "slider.horizontal.3", key: "⌥⌘N",
                        hue: GlassInk.accent(paneAccent)
                    ) {
                        BrainSheets.openNewRoom(model)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    AppActionTile(
                        title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent), prominent: true
                    ) {
                        Task { await model.quickRoom() }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Space.s8 * 8), spacing: Space.s3, alignment: .top)],
                    alignment: .leading, spacing: Space.s3
                ) {
                    ForEach(model.rooms) { r in PlaceCard(model: model, room: r) }
                }
                Text(SyncWords.neverRead).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Space.s2)
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// One place: its icon, name and kind; what is in it; its count, its AI and when it last took something new.
private struct PlaceCard: View {
    let model: BrainModel
    let room: RoomSummary

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: room.lock == nil ? "folder" : "lock").coreFont(size: MacTextSize.body)
                        .frame(width: Space.s6, height: Space.s6)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                        .accessibilityHidden(true)
                    Text(room.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text(room.kind.label).coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s2).padding(.vertical, 2)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                }
                Text(subtitle).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s2)
                HStack(spacing: Space.s3) {
                    Text(room.counts.map { "\($0.records.formatted()) known" } ?? "Sealed").monospacedDigit()
                    if waiting {
                        Text("Needs a local model").foregroundStyle(GlassInk.amberInk)
                    } else {
                        Text(policyLabel).foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: Space.s2)
                    if let when = model.lastSyncLabel(room) { Text(when).foregroundStyle(GlassInk.secondary) }
                }
                .coreFont(size: MacTextSize.meta)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: Space.s8 * 4, alignment: .topLeading)
            .coreWell()
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
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

    private var policy: RoomPolicy? { model.candidates.policy(room.id) }
    private var waiting: Bool { policy?.needsLocalModel ?? false }
    private var policyLabel: String {
        (policy.map { $0.model == .localOnly } ?? (room.provider == .local)) ? "Local only" : "Cloud"
    }

    private var subtitle: String {
        if room.lock != nil { return "Sealed · \(room.kind.label)" }
        // Sources named with capitals ("Claude Code 842") are listed as they are; record types are counted and pluralised.
        let shares = room.counts?.byType ?? []
        let types =
            shares.contains { $0.type.first?.isUppercase == true }
            ? shares.filter { $0.count > 0 }.map { "\($0.type) \($0.count.formatted())" }.joined(separator: " · ")
            : BrainWords.breakdown(shares)
        return types.isEmpty ? "\(room.kind.label) · \(room.mode.label)" : types
    }

    private func pick() {
        model.view(room.id)
        model.placeOpen = true
        guard room.lock == nil else { return }
        Task { await model.inspect(room.id) }
    }
}

/// The chosen room: who it is, its search and its rules.
private struct RoomPane: View {
    @Environment(\.coreAccent) private var paneAccent
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
                } else if mode == .overview {
                    notices
                    RoomOverviewTab(model: model, room: room)
                } else if mode == .settings {
                    RoomSettings(model: model, room: room)
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

    /// The halves this Core can show: Overview where it writes one, Settings where it serves the policy routes.
    private var tabs: [RoomPaneMode] {
        (model.servesOverview ? [.overview] : []) + [.items]
            + (model.service?.servesCandidates == true ? [.settings] : [])
    }

    /// The chosen half, or Items when this Core does not have it.
    private var mode: RoomPaneMode {
        tabs.contains(model.candidates.paneMode) ? model.candidates.paneMode : .items
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            IconTile(
                room.lock == nil ? "folder" : "lock",
                hue: room.lock == nil ? GlassInk.accent(paneAccent) : GlassInk.slate)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(line).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            if room.lock == nil, tabs.count > 1 {
                CoreSegmented(
                    "Room view", segments: tabs.map { CoreSegment($0, $0.title) },
                    selection: Binding(get: { mode }, set: { model.candidates.paneMode = $0 }))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    if let when = model.lastSyncLabel(room) { Text("Synced \(when.lowercased())") }
                    Text("\(room.mode.label) · \(room.provider.label)").help(room.provider.help)
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .help(room.help)
        .contextMenu {
            if room.lock == nil { Button("Seal Room") { Task { await model.seal(room.id) } } }
        }
    }

    private var line: String {
        var parts = [room.kind.label]
        if let c = room.counts { parts.append("\(c.records.formatted()) \(c.records == 1 ? "item" : "items")") }
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
    @State private var latest: Result<RoomLatest, BrainFailure>?
    @State private var asked = ""
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            field
            if asked.isEmpty, case .failure(let f) = latest {
                Text(f.sentence).foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3)
            } else if asked.isEmpty, case .success(let l) = latest, l.items.isEmpty {
                Text("Nothing is in \(room.name) yet.").foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3)
            } else if asked.isEmpty, case .success(let l) = latest {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("Latest").coreFont(size: MacTextSize.headline, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: Space.s3)
                        Text("Newest first").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, 2)
                    if l.records == 0 {
                        Text(BrainWords.importedOnly).foregroundStyle(GlassInk.secondary).padding(.horizontal, 2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(l.items) { LatestRow(item: $0, room: room.name) }
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
        .task(id: room.id) {
            let l = await sync.latest(room: room.id)
            if !Task.isCancelled { latest = l }
        }
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
            Text(MemoryType(rawValue: item.type)?.label ?? SyncWords.title(item.sourceKind, ImportSources.standard()))
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
