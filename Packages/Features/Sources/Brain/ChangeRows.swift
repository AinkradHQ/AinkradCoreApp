import CoreUI
import SwiftUI

/// The records one change set touched, each with what it was and what it became, and the sources an AI-proposed memory
/// cites. A record Undo kept because it changed since is marked.
struct ChangeRows: View {
    let model: ChangesModel
    let change: MemoryChange

    var body: some View {
        let d = model.details[change.id] ?? ChangesModel.Detail()
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(d.rows) { row in
                ChangeRowView(row: row, kept: model.kept(row, in: change.id), cites: change.kind == .ai)
            }
            if let why = d.failed {
                HStack(spacing: Space.s2) {
                    Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(GlassInk.redInk)
                    Button("Try again") { Task { await model.loadRows(change.id, after: d.rows.last?.seq) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                .coreFont(size: MacTextSize.meta)
            } else if d.loading {
                CoreSkeleton(coreShape(Radius.cardMac)).frame(height: Space.s8 * 2)
            } else if d.rows.isEmpty {
                Text("This set holds no records.").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else if d.more {
                Button("Show more") { model.moreRows(change.id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(.top, Space.s1)
    }
}

private struct ChangeRowView: View {
    @Environment(\.coreAccent) private var paneAccent
    let row: ChangeRow
    let kept: Bool
    /// An AI-proposed set: a memory with no cited source is said so, not left blank.
    let cites: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                BrainChip(row.verb, row.verb == "Removed" ? GlassInk.red : GlassInk.accent(paneAccent))
                Text((row.after ?? row.before)?.type.capitalized ?? "").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
                if kept {
                    BrainChip(
                        "Kept, changed since", GlassInk.slate,
                        help: "Undo left this alone because it changed after this set.")
                }
                Spacer(minLength: Space.s2)
                Text(row.record).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(
                    GlassInk.secondary
                )
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: Space.s2) {
                side("Before", row.before, empty: "Did not exist")
                side("After", row.after, empty: "Removed")
            }
            sources
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        .accessibilityElement(children: .contain)
    }

    private func side(_ title: String, _ image: MemoryImage?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
            if let image {
                Text(image.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else {
                Text(empty).foregroundStyle(GlassInk.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The sources the memory now cites (the Core keeps their ids). Shown for any record that has them; an AI-proposed
    /// one with none says so.
    @ViewBuilder private var sources: some View {
        let ids = row.after?.sources ?? row.before?.sources ?? []
        if !ids.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("Cited").coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
                ChipFlow { ForEach(ids, id: \.self) { BrainChip($0, GlassInk.slate) } }
            }
        } else if cites, row.after != nil {
            Label("No source cited", systemImage: "exclamationmark.triangle").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.amberInk)
        }
    }
}
