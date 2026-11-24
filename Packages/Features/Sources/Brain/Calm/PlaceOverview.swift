import CoreUI
import SwiftUI

/// A place's Overview (Designs/core/0-10/review/brain/place.html): what Brain wrote about it, its counts, and four short
/// lists that each open the matching Brain page narrowed to this place. There is no "write it" empty state: from API
/// minor 102 the Core writes and refreshes overviews by itself, so a place with things read and no overview is shown
/// being written. Parts this Core has no data for are left out, never filled with made-up numbers.
struct PlaceOverview: View {
    let model: BrainModel
    let room: RoomSummary
    @State private var lists = PlaceLists()
    @State private var shown = false
    private var o: RoomOverviewModel { model.roomOverview }
    private var cur: RoomOverview? { o.roomID == room.id ? o.current : nil }
    private var place: PlaceWire? { model.calm.places?.first { $0.room == room.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let n = o.notice { CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .warn) }
            if model.servesOverview { PlaceSummary(model: model, room: room, place: place).coreRise(shown, 0) }
            stats.coreRise(shown, 1)
            grid.coreRise(shown, 2)
        }
        .onAppear { shown = true }
        .task(id: "\(room.id)#\(o.epoch)") { if model.servesOverview { await o.open(room.id) } }
        .task(id: "\(room.id)#\(cur?.isWriting == true)") {
            if cur?.isWriting == true { await o.watch(room.id) }
        }
        .task(id: "\(room.id)#\(cur?.state.rawValue ?? "-")") {
            // Not written yet on a Core that writes by itself: look again until it starts.
            while model.writesOverviews, cur?.state == .notWritten, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled { await o.load(room.id, quiet: true) }
            }
        }
        .task(id: room.id) { lists = await PlaceLists.load(model.calm, room: room.id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-overview")
    }

    // MARK: stats

    /// Knowledge, Rules, Events (API minor 101) and Things read. The Core has no per-place daily counts yet, so there is
    /// no "+today" and no 14-day bars here.
    @ViewBuilder private var stats: some View {
        let tiles: [(String, String, Int)] =
            (place.map { p in
                [
                    ("sparkles", "Knowledge", p.knowledge), ("checkmark", "Rules", p.rules),
                    ("clock", "Events", p.timeline),
                ]
            } ?? []) + (room.counts.map { [("doc", "Things read", $0.records)] } ?? [])
        if !tiles.isEmpty {
            HStack(spacing: Space.s3) {
                ForEach(tiles, id: \.1) { t in StatTile(symbol: t.0, title: t.1, value: t.2) }
            }
        }
    }

    // MARK: lists

    @ViewBuilder private var grid: some View {
        let cards = listCards
        if !cards.isEmpty {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s4, alignment: .top),
                    GridItem(.flexible(), spacing: Space.s4, alignment: .top),
                ], alignment: .leading, spacing: Space.s4
            ) {
                ForEach(cards, id: \.title) { $0 }
            }
        }
    }

    private var listCards: [PlaceListCard] {
        var out: [PlaceListCard] = []
        let id = room.id
        if let r = lists.rules, !r.records.isEmpty {
            out.append(
                PlaceListCard(
                    title: "Rules it follows here", symbol: "checkmark", link: "All \(r.total.formatted()) rules",
                    rows: r.records.map { .init(id: $0.id, text: $0.body, meta: "seen \($0.support)×") }
                ) { model.openPlaceList(.rules, room: id) })
        } else if let body = cur?.overview, !body.rules.groups.isEmpty {
            // An older Core: the rules the written overview names.
            let rules = body.rules.groups.flatMap(\.rules).prefix(4)
            out.append(
                PlaceListCard(
                    title: "Rules it follows here", symbol: "checkmark", link: nil,
                    rows: rules.map { .init(id: $0.id, text: $0.text, meta: "from \($0.sources.count)") }))
        }
        if let d = lists.decisions, !d.records.isEmpty {
            out.append(
                PlaceListCard(
                    title: "Latest decisions", symbol: "star", link: "All decisions",
                    rows: d.records.map { .init(id: $0.id, text: $0.body, meta: Self.day($0.createdAt)) }
                ) { model.openPlaceList(.knowledge, room: id, type: "decision") })
        }
        if let t = lists.events, !t.records.isEmpty {
            out.append(
                PlaceListCard(
                    title: "What happened lately", symbol: "clock", link: "Timeline",
                    rows: t.records.map { .init(id: $0.id, text: $0.body, meta: Self.day($0.createdAt)) }
                ) { model.openPlaceList(.timeline, room: id) })
        }
        if let f = lists.facts, !f.records.isEmpty {
            out.append(
                PlaceListCard(
                    title: "Most useful facts", symbol: "sparkles", link: "All \(f.total.formatted())",
                    rows: f.records.map { .init(id: $0.id, text: $0.body, meta: BrainSure.words($0.support)) }
                ) { model.openPlaceList(.knowledge, room: id, type: "fact") })
        }
        return out
    }

    /// "today", "Sat", "12 Nov".
    static func day(_ iso: String, now: Date = Date()) -> String {
        guard let d = SyncWords.date(iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInYesterday(d) { return "yesterday" }
        if let days = cal.dateComponents([.day], from: d, to: now).day, days < 7 {
            return d.formatted(.dateTime.weekday(.abbreviated))
        }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The four lists of a place's Overview, read once per place.
struct PlaceLists: Equatable {
    var rules: BrainAreaPageWire?
    var decisions: BrainAreaPageWire?
    var events: BrainAreaPageWire?
    var facts: BrainAreaPageWire?

    @MainActor static func load(_ calm: BrainCalmModel, room: String) async -> PlaceLists {
        async let r = calm.placeRecords("rules", room: room, limit: 4)
        async let d = calm.placeRecords("knowledge", room: room, type: "decision", limit: 3)
        async let t = calm.placeRecords("timeline", room: room, limit: 3)
        async let f = calm.placeRecords("knowledge", room: room, type: "fact", limit: 3)
        var out = PlaceLists(rules: await r, decisions: await d, events: await t, facts: await f)
        // Most useful first: the best supported facts.
        out.facts?.records.sort { $0.support > $1.support }
        return out
    }
}

/// One count of the place: its tile, name and number.
private struct StatTile: View {
    let symbol: String
    let title: String
    let value: Int
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                BrainTile(symbol: symbol, size: Space.s5 + 2)
                Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Text(value.formatted()).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(active: hover)
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// "Rules it follows here" and the others: a title with its link, then short rows with a quiet note on the right.
struct PlaceListCard: View {
    struct Row: Identifiable {
        let id: String
        let text: String
        let meta: String
    }
    let title: String
    let symbol: String
    let link: String?
    let rows: [Row]
    var open: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            BrainCardHead(title: title) {
                if let link, let open {
                    Button(link, action: open).buttonStyle(.plain).brainAccentInk()
                        .help("Open \(link.lowercased()) in this place")
                }
            }
            .padding(.bottom, Space.s1)
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: Space.s3) {
                    BrainTile(symbol: symbol, size: Space.s5 + 2)
                    Text(r.text).coreFont(size: MacTextSize.body).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.meta).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).fixedSize()
                        .padding(.top, 2)
                }
                .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
                .modifier(BrainRowHover())
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}
