import CoreUI
import SwiftUI

/// Home's "Learned today": the newest things Brain took in, each with Forget (Undo in the toast), and the imports it sorted
/// by itself with their Undo.
struct LearnedCard: View {
    let brain: BrainModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    private static let shown = 5

    var body: some View {
        let calm = brain.calm
        let rows = Array(calm.learned.prefix(max(0, Self.shown - calm.autoImports.count)))
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "Learned today") {
                HStack(spacing: Space.s1) {
                    Text("\(calm.learned.count.formatted()) new").monospacedDigit()
                    if calm.learned.count > rows.count {
                        Text("·")
                        Button("See All") { brain.go(.records) }.buttonStyle(.plain).brainAccentInk()
                            .help("Search everything Brain knows (⌘E)")
                            .accessibilityIdentifier("brain-learned-more")
                    }
                }
            }
            if calm.learned.isEmpty && calm.autoImports.isEmpty {
                Text("Nothing new yet. It keeps watching.").coreFont(size: MacTextSize.body)
                    .foregroundStyle(GlassInk.secondary)
            }
            ForEach(calm.autoImports) { a in
                HStack(spacing: Space.s3) {
                    BrainTile(symbol: "folder")
                    Text("Sorted your import into \(BrainWords.plural(a.rooms, "place", "places"))")
                        .coreFont(size: MacTextSize.body).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Undo") { Task { await calm.undoImport(a) } }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Put the import back in one pile, open for review")
                }
            }
            ForEach(rows) { l in
                LearnedLine(
                    symbol: l.symbol, line: l.line,
                    meta: [l.areaTitle, l.roomName, l.at].filter { !$0.isEmpty }.joined(separator: " · ")
                ) { brain.forget(l) }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading).coreWell()
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.learned.map(\.id))
        .accessibilityIdentifier("brain-learned")
    }
}

/// Home's "Where it knows most": the places with the most in them, as bars. A place learning now says so.
struct KnowsMostCard: View {
    let brain: BrainModel
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette

    private struct Line: Identifiable {
        let id: String
        let name: String
        let total: Int
        let learning: Bool
    }

    /// The Core's places (API minor 101), else the open rooms' counts.
    private var lines: [Line] {
        let all: [Line] =
            if let p = brain.calm.places {
                p.filter { $0.room != "me" && !$0.locked }.map {
                    Line(id: $0.room, name: $0.name, total: $0.total, learning: $0.learning)
                }
            } else {
                brain.recordsPerRoom.map {
                    Line(id: $0.room.id, name: $0.room.name, total: $0.counts.records, learning: false)
                }
            }
        return Array(all.sorted { $0.total > $1.total }.prefix(5))
    }

    var body: some View {
        let lines = lines
        let top = Double(max(lines.first?.total ?? 1, 1))
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "Where it knows most") {
                Button("All Places") { brain.go(.rooms) }.buttonStyle(.plain).brainAccentInk()
                    .help("Open Places")
            }
            if lines.isEmpty {
                Text("No places yet.").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            ForEach(lines) { l in
                Button {
                    brain.view(l.id)
                    brain.placeOpen = true
                    brain.go(.rooms)
                } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "folder").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                        Text(l.name).coreFont(size: MacTextSize.body).lineLimit(1)
                            .frame(width: Space.s8 * 5, alignment: .leading)
                        CoreMeter(Double(l.total) / top, label: "\(l.name), \(l.total) things")
                        Group {
                            if l.learning {
                                HStack(spacing: Space.s1) {
                                    LiveDot()
                                    Text("now").foregroundStyle(palette.success)
                                }
                            } else {
                                Text(l.total.formatted()).foregroundStyle(GlassInk.secondary).monospacedDigit()
                            }
                        }
                        .coreFont(size: MacTextSize.body)
                        .frame(width: Space.s8 * 2, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(l.name)")
            }
            HStack(spacing: Space.s2) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text("Each place is its own room. What Brain learns in one never leaks into another.")
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading).coreWell()
        .accessibilityIdentifier("brain-knows-most")
    }
}
