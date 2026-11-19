import CoreUI
import SwiftUI

/// Explore, Evidence (mockup 16): where Brain's knowledge comes from. The sources on the left by kind; the one you pick lists its
/// files and sessions on the right, and a file shows where it came from. Read from each open room's newest sources.
struct ExploreEvidenceTab: View {
    let brain: BrainModel

    struct Entry: Identifiable, Equatable {
        let item: LatestItem
        let room: String
        var id: String { room + "/" + item.itemID }
    }

    @State private var entries: [Entry] = []
    @State private var kind: String?
    @State private var picked: String?
    @State private var loaded = false
    @State private var trace: SourceTraceWire?

    private var kinds: [(kind: String, count: Int)] {
        Dictionary(grouping: entries, by: \.item.sourceKind).map { ($0.key, $0.value.count) }.sorted { $0.kind < $1.kind }
    }
    private var files: [Entry] { entries.filter { $0.item.sourceKind == kind } }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(spacing: 2) {
                if kinds.isEmpty {
                    Text(loaded ? "No sources in the open rooms yet." : "Reading…").foregroundStyle(GlassInk.secondary)
                        .padding(Space.s3)
                }
                ForEach(kinds, id: \.kind) { k in
                    CoreRow(Self.title(k.kind), subtitle: BrainWords.plural(k.count, "item", "items"),
                        symbol: Self.symbol(k.kind), selected: kind == k.kind
                    ) {
                        withAnimation(Motion.out(Motion.ui)) { kind = k.kind; picked = nil }
                    }
                }
            }
            .frame(width: Space.s8 * 9)
            VStack(alignment: .leading, spacing: Space.s3) {
                if let kind {
                    Text(Self.title(kind)).coreFont(size: MacTextSize.headline, weight: .semibold)
                    VStack(spacing: 2) {
                        ForEach(files) { f in
                            CoreRow(f.item.title.isEmpty ? "Untitled" : f.item.title,
                                subtitle: "\(Self.when(f.item.startedAt)) · \(roomName(f.room))", symbol: "doc",
                                selected: picked == f.id
                            ) { picked = f.id }
                        }
                    }
                    if let f = files.first(where: { $0.id == picked }) {
                        origin(f)
                        session(f)
                    }
                } else {
                    Text("Pick a source to see its files and what Brain took from them.")
                        .foregroundStyle(GlassInk.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(Motion.out(Motion.ui), value: picked)
        }
        .task(id: picked) { await loadTrace() }
        .task { await load() }
        .accessibilityIdentifier("brain-explore-evidence")
    }

    /// "Where it came from" for the picked file.
    private func origin(_ f: Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Where it came from").coreFont(size: MacTextSize.headline, weight: .semibold)
            CoreRow(Self.title(f.item.sourceKind), subtitle: Self.when(f.item.startedAt), symbol: Self.symbol(f.item.sourceKind))
            CoreRow(roomName(f.room), subtitle: "The place Brain filed it in", symbol: "folder")
            Text("Brain read this and wrote down what mattered. What it learned is under Records.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .transition(.opacity)
    }

    /// "From the session" (the source's own words) and "How it changed" (each record's history, with Undo for a record taken out).
    @ViewBuilder private func session(_ f: Entry) -> some View {
        if let t = trace {
            VStack(alignment: .leading, spacing: Space.s2) {
                if !t.excerpt.isEmpty {
                    Text("From the session").coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text("“\(t.excerpt)”").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                        .textSelection(.enabled)
                }
                if !t.records.isEmpty {
                    Text("How it changed").coreFont(size: MacTextSize.headline, weight: .semibold)
                    ForEach(t.records) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.body).lineLimit(2).coreFont(size: MacTextSize.meta, weight: .semibold)
                            ForEach(Array(r.history.enumerated()), id: \.offset) { i, s in
                                CoreRow(Self.step(s.op), subtitle: Self.when(s.at), symbol: "circle.fill") {
                                    if r.archived, i == r.history.count - 1, s.op == "record.archived" {
                                        Button("Undo") { Task { await restore(f.room, r.id) } }
                                            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            .transition(.opacity)
        }
    }

    private func loadTrace() async {
        trace = nil
        guard let id = picked, let f = entries.first(where: { $0.id == id }),
            let routes = brain.service?.importRoutes
        else { return }
        trace = try? await routes.trace(room: f.room, item: f.item.itemID)
    }

    private func restore(_ room: String, _ id: String) async {
        try? await brain.service?.importRoutes?.restoreRecord(room: room, id: id)
        await loadTrace()
    }

    static func step(_ op: String) -> String {
        switch op {
        case "record.candidate": "Proposed"
        case "record.accepted": "Learned"
        case "record.edited": "Reworded"
        case "record.archived": "Taken out"
        case "record.restored": "Put back"
        case "record.purged": "Removed for good"
        default: op
        }
    }

    private func roomName(_ id: String) -> String { brain.rooms.first { $0.id == id }?.name ?? id }

    private func load() async {
        guard let service = brain.service else { return }
        var all: [Entry] = []
        for r in brain.rooms where r.mounted && r.lock == nil {
            if let l = try? await service.latest(room: r.id) { all += l.items.map { Entry(item: $0, room: r.id) } }
        }
        entries = all
        kind = kind ?? kinds.first?.kind
        loaded = true
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "claude_code": "Claude Code"
        case "codex": "Codex"
        case "opencode": "OpenCode"
        case "antigravity": "Antigravity"
        case "cursor": "Cursor"
        case "note": "Notes folder"
        case "chat_export": "Chat exports"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "note": "folder"
        case "chat_export": "doc"
        default: "terminal"
        }
    }

    static func when(_ iso: String) -> String { SyncWords.date(iso).map { SyncWords.ago($0) } ?? iso }
}
