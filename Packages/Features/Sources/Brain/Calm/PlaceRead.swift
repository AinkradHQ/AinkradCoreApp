import CoreUI
import SwiftUI

/// A place's What It Read: what Brain read here by kind, a search, the newest sources by day, and beside them the chosen
/// source's start and what Brain learned from it, with Forget What It Learned (archived, Undo in the toast). Counts are
/// of the sources the Core lists (its newest 100); the line above the list says so when the place holds more.
struct PlaceRead: View {
    let model: BrainModel
    let room: RoomSummary
    @State private var latest: RoomLatest?
    @State private var loaded = false
    @State private var kind: String?
    @State private var query = ""
    @State private var hits: [SearchHit]?
    @State private var picked: String?
    @State private var trace: SourceTraceWire?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { model.calm }

    private var items: [LatestItem] { latest?.items ?? [] }
    private var listed: [LatestItem] {
        if let hits {
            return hits.map {
                LatestItem(
                    itemID: $0.itemID, type: "source", sourceKind: $0.sourceKind, title: $0.title,
                    startedAt: $0.startedAt)
            }
        }
        return items.filter { kind == nil || $0.sourceKind == kind }
    }
    private var kinds: [(kind: String, count: Int)] {
        Dictionary(grouping: items, by: \.sourceKind).map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if !items.isEmpty { tiles.coreRise(shown, 0) }
            tools
            if loaded, items.isEmpty {
                Text("Brain has not read anything in \(room.name) yet.").coreFont(size: MacTextSize.body)
                    .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s2)
            } else if !loaded {
                BrainSkeleton(shape: .list)
            } else {
                HStack(alignment: .top, spacing: Space.s4) {
                    list.frame(maxWidth: .infinity)
                    if let item = listed.first(where: { $0.itemID == picked }) {
                        panel(item).frame(width: Space.s8 * 11).transition(.opacity)
                    }
                }
                .coreRise(shown, 1)
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: picked)
        .onAppear { shown = true }
        .task(id: room.id) {
            latest = await calm.placeSources(room: room.id)
            loaded = true
            picked = picked ?? items.first?.itemID
        }
        .task(id: picked) { await loadTrace() }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else {
                hits = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let found = await calm.placeSearch(room: room.id, q)
            if !Task.isCancelled { hits = found }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-read")
    }

    // MARK: kinds

    private var tiles: some View {
        HStack(spacing: Space.s2) {
            tile(nil, "Everything", "square.grid.2x2", items.count)
            ForEach(kinds, id: \.kind) { k in
                tile(k.kind, ExploreEvidenceTab.title(k.kind), Self.kindSymbol(k.kind), k.count)
            }
            Spacer(minLength: 0)
        }
    }

    private func tile(_ k: String?, _ title: String, _ symbol: String, _ n: Int) -> some View {
        KindTileButton(
            title: title, symbol: symbol, count: n, share: Double(n) / Double(max(items.count, 1)), on: kind == k
        ) {
            kind = k
            query = ""
            picked = listed.first?.itemID
        }
    }

    // MARK: search and list

    private var tools: some View {
        HStack(spacing: Space.s3) {
            FilterField(placeholder: "Search what it read in \(room.name)", text: $query) {}
                .frame(maxWidth: Space.s8 * 10)
            Spacer(minLength: Space.s3)
            Text(countLine).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
        }
    }

    private var countLine: String {
        if let hits { return BrainWords.plural(hits.count, "match", "matches") }
        if let total = room.counts?.records, total > items.count {
            return "Newest \(items.count.formatted()) of \(total.formatted()) · newest first"
        }
        return "Newest first"
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            if listed.isEmpty {
                Text(hits != nil ? "Nothing here matches “\(query)”." : "Nothing of this kind yet.")
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).padding(Space.s2)
            }
            ForEach(Self.days(listed), id: \.day) { d in
                Text(d.day).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s2).padding(.top, Space.s3).padding(.bottom, Space.s1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(d.items) { row($0) }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: listed.map(\.itemID))
    }

    private func row(_ i: LatestItem) -> some View {
        Button {
            picked = i.itemID
        } label: {
            HStack(spacing: Space.s3) {
                BrainTile(symbol: Self.kindSymbol(i.sourceKind))
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.title.isEmpty ? "Untitled" : i.title).coreFont(size: MacTextSize.body, weight: .medium)
                        .lineLimit(1)
                    Text(ExploreEvidenceTab.title(i.sourceKind)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.time(i.startedAt)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Space.s2 + 2).padding(.vertical, Space.s2)
            .background(
                picked == i.itemID ? GlassInk.well : .clear, in: coreShape(Radius.control)
            )
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .modifier(BrainRowHover())
        .accessibilityAddTraits(picked == i.itemID ? .isSelected : [])
    }

    // MARK: panel

    private func panel(_ i: LatestItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("\(ExploreEvidenceTab.title(i.sourceKind)) · \(Self.time(i.startedAt))")
                .coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
            Text(i.title.isEmpty ? "Untitled" : i.title).coreFont(size: MacTextSize.title, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let t = trace {
                if !t.excerpt.isEmpty {
                    Text("“\(t.excerpt.trimmingCharacters(in: .whitespacesAndNewlines))…”")
                        .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(8)
                        .textSelection(.enabled)
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                }
                let kept = t.records.filter { !$0.archived }
                Text(kept.isEmpty ? "Brain kept nothing from it" : "What Brain learned from it · \(kept.count)")
                    .coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                ForEach(kept) { r in
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: Self.symbol(r.type)).foregroundStyle(GlassInk.secondary)
                            .accessibilityHidden(true)
                        Text("\(Self.label(r.type)): \(BrainCalmModel.Learned.lowerFirst(r.body))")
                            .coreFont(size: MacTextSize.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                }
                if !kept.isEmpty {
                    Button {
                        forget(kept.map(\.id))
                    } label: {
                        Label("Forget What It Learned", systemImage: "trash")
                    }
                    .buttonStyle(CoreButtonStyle(.quietDanger, size: .small))
                    .help(
                        "Take out everything Brain learned from this. It is kept in the archive, and Undo brings it back."
                    )
                }
            } else {
                CoreSkeleton().frame(height: Space.s8 * 2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-read-panel")
    }

    private func loadTrace() async {
        trace = nil
        guard let id = picked else { return }
        let t = await calm.trace(room: room.id, item: id)
        if !Task.isCancelled, picked == id { trace = t }
    }

    private func forget(_ ids: [String]) {
        let room = room.id
        Task {
            let done = await calm.forgetLearned(room: room, ids: ids)
            await loadTrace()
            guard !done.isEmpty else { return }
            model.host.shell.showToast("Forgot what it learned from this · kept in the archive") {
                Task {
                    await calm.restore(room: room, ids: done)
                    await loadTrace()
                }
            }
        }
    }

    // MARK: words

    /// A file kind reads as a page, a session kind as a terminal.
    static func kindSymbol(_ kind: String) -> String {
        switch kind {
        case "doc", "note", "file", "chat_export": "doc"
        default: "terminal"
        }
    }

    static func label(_ type: String) -> String {
        switch type {
        case "rule": "Rule"
        case "preference": "Preference"
        case "decision": "Decision"
        case "fact": "Fact"
        case "task": "Task"
        case "project-state": "Event"
        default: "Note"
        }
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "rule", "preference": "checkmark"
        case "decision": "star"
        case "project-state": "clock"
        default: "sparkles"
        }
    }

    /// "10:42" today and yesterday, else the day.
    static func time(_ iso: String) -> String {
        guard let d = SyncWords.date(iso) else { return "" }
        return d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// Sources by day, newest first: "Today", "Yesterday", "21 Nov".
    static func days(_ items: [LatestItem]) -> [(day: String, items: [LatestItem])] {
        var out: [(day: String, items: [LatestItem])] = []
        let cal = Calendar.current
        for i in items {
            let d = SyncWords.date(i.startedAt)
            let name =
                d.map {
                    cal.isDateInToday($0)
                        ? "Today"
                        : cal.isDateInYesterday($0) ? "Yesterday" : $0.formatted(.dateTime.day().month(.abbreviated))
                } ?? "Earlier"
            if out.last?.day == name { out[out.count - 1].items.append(i) } else { out.append((name, [i])) }
        }
        return out
    }
}

/// One kind of what it read: its tile, how many and its share of the whole as a thin bar.
private struct KindTileButton: View {
    let title: String
    let symbol: String
    let count: Int
    let share: Double
    let on: Bool
    let pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s3) {
                BrainTile(symbol: symbol, size: Space.s6 + Space.s1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count.formatted()).coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
                    Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    CoreMeter(share, height: 3, label: "\(title), \(count)")
                }
            }
            .padding(.vertical, Space.s2).padding(.leading, Space.s2).padding(.trailing, Space.s3)
            .frame(width: Space.s8 * 5.5, alignment: .leading)
            .background(PlaceSelectFill(on: on, hover: hover))
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(on ? title : "Show only \(title.lowercased())")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
