import CoreUI
import SwiftUI

/// Search (⌘E, mockup 16): every current record across the open places, matched against the sidebar's field, narrowed by
/// area, type and "Important only" (backed by at least three sources); places whose name matches come first. A record opens
/// its detail on the right; with nothing picked, what Brain changed lately, each with Undo.
struct ExploreRecordsTab: View {
    let brain: BrainModel
    @State private var type = ""
    @State private var important = false
    @State private var rows: [BrainCalmModel.AreaRecord] = []
    @State private var loaded = false

    private static let types = ["", "rule", "preference", "fact", "decision", "task", "project-state", "summary"]
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainPageHead("Search", "Everything Brain knows, in every open place")
            filters
            HStack(alignment: .top, spacing: Space.s4) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                            .monospacedDigit().padding(.horizontal, Space.s3).padding(.bottom, Space.s1)
                        ForEach(places) { r in
                            CoreRow(r.name, subtitle: "Place · \(r.kind.label)", symbol: "folder", action: { open(r) })
                        }
                        ForEach(shown) { row in
                            let r = row.record
                            CoreRow(
                                r.body, subtitle: sub(row.area, r), symbol: CalmArea.symbol(r.type),
                                selected: calm.picked == r.id, action: { calm.picked = r.id })
                        }
                    }
                    .animation(Motion.out(Motion.ui), value: shown.map(\.id))
                }
                Group {
                    if let row = shown.first(where: { $0.record.id == calm.picked }) {
                        RecordDetail(brain: brain, record: row.record, area: row.area)
                    } else {
                        changedLately
                    }
                }
                .frame(width: Space.s8 * 12)
            }
        }
        .task { await load() }
        .onChange(of: calm.records.map(\.id)) { Task { await load() } }
        .accessibilityIdentifier("brain-explore-records")
    }

    private var filters: some View {
        HStack(spacing: Space.s3) {
            CoreSelect(
                nil, selection: Bindable(calm).searchArea,
                options: [CoreSelectOption("", "All areas")]
                    + ["me", "rules", "knowledge", "timeline"].map {
                        CoreSelectOption($0, BrainTab(rawValue: $0)?.title ?? $0)
                    }
            )
            .frame(width: Space.s8 * 6)
            CoreSelect(
                nil, selection: $type,
                options: Self.types.map {
                    CoreSelectOption($0, $0.isEmpty ? "All types" : $0.replacingOccurrences(of: "-", with: " "))
                }
            )
            .frame(width: Space.s8 * 6)
            CoreCheckbox("Important only", isOn: $important)
            Spacer()
        }
    }

    /// "What Brain changed lately": the newest it learned, each with Undo (the same as Home).
    private var changedLately: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What Brain changed lately").coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            if calm.learned.isEmpty {
                Text("Nothing new yet.").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            ForEach(calm.learned.prefix(6)) { l in
                CoreRow(l.line, subtitle: l.at, symbol: l.symbol) {
                    Button("Undo") { Task { await calm.undo(l) } }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Take this back. It is archived, never deleted.")
                }
            }
            Text("Select anything to see where it came from.").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).padding(.top, Space.s2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    private var words: String { calm.query.trimmingCharacters(in: .whitespaces) }

    private var shown: [BrainCalmModel.AreaRecord] {
        rows.filter { row in
            let r = row.record
            return (calm.searchArea.isEmpty || row.area == calm.searchArea) && (type.isEmpty || r.type == type)
                && (!important || r.support >= 3)
                && (words.isEmpty || r.body.localizedCaseInsensitiveContains(words)
                    || r.roomName.localizedCaseInsensitiveContains(words))
        }
    }

    private var places: [RoomSummary] {
        words.isEmpty ? [] : brain.rooms.filter { $0.name.localizedCaseInsensitiveContains(words) }
    }

    private var count: String {
        guard loaded else { return "Reading…" }
        let n = shown.count + places.count
        return words.isEmpty
            ? BrainWords.plural(n, "thing", "things")
            : n == 0 ? "Nothing matches “\(words)”." : "\(BrainWords.plural(n, "match", "matches")) for “\(words)”"
    }

    private func sub(_ area: String, _ r: BrainAreaRecordWire) -> String {
        "\(BrainTab(rawValue: area)?.title ?? area) · \(r.roomName) · \(BrainWords.plural(r.support, "source", "sources"))"
    }

    private func open(_ r: RoomSummary) {
        brain.view(r.id)
        brain.go(.rooms)
        brain.placeOpen = true
        if r.lock == nil { Task { await brain.inspect(r.id) } }
    }

    private func load() async {
        rows = await calm.everything()
        loaded = true
    }
}
