import CoreUI
import SwiftUI

/// The captures that had no trusted room. This list is not a room: never searched, never shown to agents, never deleted or
/// assigned for you. Stale at 14 days, a bell at 30.
struct NoRoomList: View {
    let model: BrainModel
    private var st: InboxState { model.inboxState }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            InboxNote(
                "lock", GlassInk.slate,
                Text("This list is not a room. ").bold()
                    + Text(
                        "These captures had no trusted room. They are never searched and never shown to agents. A capture older than 14 days shows as stale, and at 30 days it also rings the bell. Nothing is deleted or assigned for you."
                    ))
            if !st.selected.isEmpty { BulkBar(model: model) }
            if st.captures.isEmpty {
                BrainStateCard(
                    symbol: "tray", title: "Nothing without a room",
                    text: "Every capture found its room. A growing list here would mean the room signals need a look."
                ) {
                    Button("Back to Overview") { withAnimation { model.tab = .overview } }
                        .buttonStyle(CoreButtonStyle(.secondary))
                }
                .accessibilityIdentifier("inbox-empty")
            } else {
                ForEach(st.captures) { u in CaptureRow(model: model, u: u) }
            }
        }
    }
}

private struct BulkBar: View {
    let model: BrainModel
    var body: some View {
        let ids = orderedSelection
        HStack(spacing: Space.s2) {
            Text("\(ids.count) selected").font(.system(size: MacTextSize.headline, weight: .semibold))
            Spacer(minLength: Space.s2)
            Button("Delete after review…") { BrainSheets.confirmDelete(model, ids) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button("Mark private") { Task { await model.markPrivate(ids) } }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button("Assign selected…") { BrainSheets.assign(model, ids) }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
        .padding(Space.s3).coreWell()
        .disabled(model.busy != nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-bulk")
    }
    private var orderedSelection: [String] {
        model.inboxState.captures.map(\.id).filter(model.inboxState.selected.contains)
    }
}

private struct CaptureRow: View {
    let model: BrainModel
    let u: Capture

    var body: some View {
        let st = model.inboxState
        HStack(alignment: .center, spacing: Space.s3) {
            CoreCheckbox(
                "",
                isOn: Binding(
                    get: { st.selected.contains(u.id) },
                    set: { if $0 { st.selected.insert(u.id) } else { st.selected.remove(u.id) } }),
                spoken: "Select this capture"
            )
            .fixedSize()
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(u.source).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                HStack(spacing: Space.s2) {
                    Text("Waiting \(u.age)").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    if u.stale { BrainChip("Stale", GlassInk.orange, help: "Older than 14 days") }
                    if u.inBell { BrainChip("In the bell", GlassInk.blue, help: "Older than 30 days") }
                    BrainChip(
                        u.guess.map { "Guess: \($0)" } ?? "No guess", GlassInk.slate,
                        help: "A local model may suggest a room only if you turn that on. It is advice, not action.")
                }
            }
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s2) {
                Button("Assign to a room…") { BrainSheets.assign(model, [u.id]) }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                Button("Split…") { BrainSheets.split(model, u.id) }.buttonStyle(
                    CoreButtonStyle(.secondary, size: .small)
                )
                .help("Give each part of a mixed capture its own room.")
                Button("Mark private") { Task { await model.markPrivate([u.id]) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Scrub it and block it. It will not be searched. Touch ID asks.")
                Button("Exclude") { Task { await model.exclude([u.id]) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Refuse it and wipe it. It never enters any room. Touch ID asks.")
                Button("Delete…") { BrainSheets.confirmDelete(model, [u.id]) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
            .disabled(model.busy != nil)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .help("Capture id: \(u.id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-capture-\(u.id)")
    }
}
