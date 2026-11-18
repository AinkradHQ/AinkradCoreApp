import CoreUI
import SwiftUI

/// Activity's memory view: what the Core saved, reinforced, dropped or tidied in the viewing room by itself, one line per
/// change set with Undo and "See changes". Nothing waits for approval; this is where a person sees it and takes it back.
struct ChangesView: View {
    let model: BrainModel

    var body: some View {
        let m: ChangesModel = model.changes
        Group {
            if model.viewing == nil {
                BrainStateCard(
                    symbol: "lock", title: "Pick a room first",
                    text: "Memory changes belong to one room. Choose a room in the picker above.")
            } else if let lock = model.viewingLock {
                BrainStateCard(symbol: "lock", title: "This room is sealed", text: lock.sentence)
            } else {
                switch m.phase {
                case .loading:
                    BrainSkeleton(shape: .list)
                case .failed(let why, let code):
                    BrainStateCard(
                        symbol: "exclamationmark.triangle", title: "Memory changes could not load", text: why,
                        primary: CoreAction("Try again") { m.retry() }
                    )
                    .help("Code: \(code)")
                case .ready:
                    if m.changes.isEmpty {
                        BrainStateCard(
                            symbol: "tray", title: "Nothing saved yet",
                            text:
                                "When the Brain saves, merges or drops memories in this room, each batch shows here with Undo."
                        )
                        .accessibilityIdentifier("changes-empty")
                    } else {
                        list(m)
                    }
                }
            }
        }
        .task { m.enter() }
        .onChange(of: model.viewingID) { m.enter() }
        .accessibilityIdentifier("brain-changes")
    }

    private func list(_ m: ChangesModel) -> some View {
        LazyVStack(spacing: Space.s2) {
            ForEach(m.changes) { c in ChangeLine(model: m, change: c) }
            if m.hasMore {
                Button("Load more") { m.loadMore() }.buttonStyle(CoreButtonStyle(.secondary))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One change set: its summary line, Undo, "See changes", and when open the records it touched.
private struct ChangeLine: View {
    let model: ChangesModel
    let change: MemoryChange
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var open: Bool { model.expanded.contains(change.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(change.at).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .frame(width: Space.s8 * 3.5, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(change.line).fontWeight(.semibold)
                    Text(change.kind.label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
            note
            if open { ChangeRows(model: model, change: change) }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.hover), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(change.line), \(change.at)")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s2) {
            if change.undone {
                BrainChip("Undone", GlassInk.slate, help: "This set was put back. It cannot be undone twice.")
            } else if change.canUndo {
                Button("Undo") { model.undo(change.id) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: model.undoing.contains(change.id)))
                    .disabled(model.undoing.contains(change.id))
                    .help("Put these memories back as they were. Any changed since are kept.")
            } else {
                BrainChip("Removed for good", GlassInk.slate, help: "A purge deletes its rows, so it cannot be undone.")
            }
            if change.kind.hasRows {
                Button(open ? "Hide changes" : "See changes") {
                    withAnimation(reduce ? nil : .easeOut(duration: Motion.ui)) { model.toggle(change.id) }
                }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Show each memory this set touched, before and after.")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
            }
        }
    }

    /// What Undo did, or why it failed, in one quiet line.
    @ViewBuilder private var note: some View {
        if let why = model.undoFailed[change.id] {
            Label(why, systemImage: "exclamationmark.triangle").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.redInk)
        } else if let r = model.results[change.id] {
            Label(ChangesModel.sentence(r), systemImage: "arrow.uturn.backward").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
        }
    }
}
