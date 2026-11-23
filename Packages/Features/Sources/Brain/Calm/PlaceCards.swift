import CoreUI
import SwiftUI

/// Places as cards: each place's count, what is in it by area (API minor 101), whether it learns now, and when it last
/// learned. The private About you place comes last. An older Core gives the total only.
struct PlaceCards: View {
    let model: BrainModel
    @State private var shown = false

    struct Card: Identifiable {
        let id: String
        let name: String
        let sub: String
        let place: PlaceWire?
        let room: RoomSummary?
        var total: Int { place?.total ?? room?.counts?.records ?? 0 }
        var locked: Bool { place?.locked ?? (room?.lock != nil) }
        var me: Bool { id == "me" }
    }

    static func cards(_ m: BrainModel) -> [Card] {
        if let places = m.calm.places {
            let rooms = Dictionary(m.rooms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let all = places.map { p in
                Card(
                    id: p.room, name: p.room == "me" ? "About you" : p.name,
                    sub: p.room == "me" ? "Private · only about you" : rooms[p.room]?.kind.label ?? "Place", place: p,
                    room: rooms[p.room])
            }
            return all.filter { !$0.me }.sorted { $0.total > $1.total } + all.filter(\.me)
        }
        return m.rooms.map { Card(id: $0.id, name: $0.name, sub: $0.kind.label, place: nil, room: $0) }
    }

    static func count(_ m: BrainModel) -> Int { m.calm.places?.count ?? m.rooms.count }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Space.s4, alignment: .top), count: 3),
            alignment: .leading, spacing: Space.s4
        ) {
            ForEach(Array(Self.cards(model).enumerated()), id: \.element.id) { i, c in
                PlaceCard(model: model, card: c).coreRise(shown, min(i, 8))
            }
        }
        .onAppear { shown = true }
    }
}

private struct PlaceCard: View {
    let model: BrainModel
    let card: PlaceCards.Card
    @Environment(\.coreAccent) private var accent
    @State private var hover = false

    private var learning: Bool { card.place?.learning == true }

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    BrainTile(symbol: card.locked || card.me ? "lock" : "folder", lit: learning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        Text(card.sub).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Space.s2)
                    badge
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s1 + 2) {
                    Text(card.locked ? "–" : card.total.formatted()).font(.system(size: 22, weight: .semibold))
                        .monospacedDigit().contentTransition(.numericText())
                    Text("things known").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                }
                if let p = card.place, !card.me, !card.locked {
                    HStack(spacing: Space.s2) {
                        part(p.knowledge, "Knowledge")
                        part(p.rules, "Rules")
                        part(p.timeline, "Events")
                    }
                }
                if learning { CoreBusyBar().accessibilityHidden(true) }
                HStack {
                    Text(footLeft)
                    Spacer(minLength: Space.s2)
                    if let r = footRight { Text(r) }
                }
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(card.me ? GlassInk.accent(accent).opacity(0.08) : .clear, in: coreShape(Radius.cardMac))
            .coreWell(active: hover)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(card.me ? "What Brain learned about how you work" : "Open \(card.name)")
        .contextMenu {
            if let room = card.room {
                if room.lock == nil {
                    Button("Seal Place") { Task { await model.seal(room.id) } }
                } else {
                    Button("Open with Touch ID") { Task { await model.open(room.id) } }
                }
            }
        }
        .accessibilityIdentifier("brain-room-\(card.id)")
    }

    @ViewBuilder private var badge: some View {
        if card.locked {
            StateBadge("Sealed", tone: .queue, symbol: "lock")
        } else if learning {
            StateBadge("Learning", tone: .done, symbol: "sparkles")
        } else if card.total == 0 {
            StateBadge("Empty", tone: .queue, symbol: "circle.dashed")
        } else if card.place != nil {
            StateBadge("Up to date", tone: .queue, symbol: "checkmark")
        }
    }

    private func part(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n.formatted()).coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s2 + 2).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    private var footLeft: String {
        if card.me { return card.total == 0 ? "Fills in from how you work" : "Only about you" }
        if card.locked { return "Sealed. Open it with Touch ID" }
        if learning { return "Reading new sessions" }
        return card.place != nil ? "Nothing new to read" : (card.room?.kind.label ?? "")
    }

    private var footRight: String? {
        if let at = SyncWords.date(card.place?.lastLearnedAt) { return "Learned \(SyncWords.agoInLine(at))" }
        return card.room.flatMap { model.lastSyncLabel($0) }
    }

    private func pick() {
        if card.me {
            model.go(.me)
            return
        }
        model.view(card.id)
        model.placeOpen = true
        guard card.room?.lock == nil else { return }
        Task { await model.inspect(card.id) }
    }
}
