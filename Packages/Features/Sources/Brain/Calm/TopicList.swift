import CoreUI
import SwiftUI

/// A Knowledge topic's records (or, on an older Core, the best-supported facts): a search, the places to narrow to, the
/// list with where each is kept and how sure, and the chosen record's panel.
struct TopicList: View {
    let brain: BrainModel
    /// The topic's places by name; empty shows no place filter.
    let places: [String]
    let topic: String?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                FilterField(
                    placeholder: topic.map { "Search in \($0)" } ?? "Search facts", text: Bindable(calm).filterText
                ) {
                    await calm.refilter()
                }
                .frame(maxWidth: Space.s8 * 10)
                if !places.isEmpty {
                    placeChip("All places", room: nil)
                    ForEach(places.prefix(6), id: \.self) { name in
                        placeChip(name, room: brain.rooms.first { $0.name == name }?.id ?? name)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if calm.records.isEmpty {
                            Text(calm.loading ? "Reading…" : "Nothing here yet. Brain fills this in as it learns.")
                                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3)
                        }
                        ForEach(calm.records) { row($0) }
                    }
                    .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.records.map(\.id))
                }
                .frame(maxWidth: .infinity)
                if let r = calm.records.first(where: { $0.id == calm.picked }) {
                    ScrollView { RecordPanel(brain: brain, record: r, topic: topic) }
                        .frame(width: Space.s8 * 11)
                        .transition(.opacity)
                }
            }
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.picked)
        }
        .onAppear { if calm.picked == nil { calm.picked = calm.records.first?.id } }
    }

    private func placeChip(_ title: String, room: String?) -> some View {
        let on = calm.topicRoom == room
        return Button(title) {
            calm.topicRoom = room
            Task { await calm.refilter() }
        }
        .buttonStyle(.plain)
        .coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular)
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
        .background(on ? palette.navActive : GlassInk.well, in: coreShape(Radius.control))
        .help(room == nil ? "Show every place" : "Show only \(title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ r: BrainAreaRecordWire) -> some View {
        let picked = calm.picked == r.id
        let decision = r.type == "decision"
        let when = SyncWords.date(r.createdAt)
        let meta =
            decision
            ? "Decision · \(when.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "")"
            : "Fact · learned \(when.map { SyncWords.agoInLine($0) } ?? "")"
        return Button {
            calm.picked = r.id
        } label: {
            HStack(spacing: Space.s3) {
                BrainTile(symbol: decision ? "star" : "sparkles")
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.body).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(2)
                    Text(meta).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                PlaceChip(name: r.roomName)
                SureBars(support: r.support)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
            .background(picked ? palette.navActive : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
