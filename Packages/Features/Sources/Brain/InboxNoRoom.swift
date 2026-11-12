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
                "lock", GlassInk.slate, "This list is not a room",
                "Nothing here is searched or shown to AI sessions, and nothing is assigned for you."
            )
            .help("A capture older than 14 days shows as stale; at 30 days it also rings the bell.")
            if st.captures.isEmpty {
                BrainStateCard(
                    symbol: "tray", title: "Nothing without a room",
                    text: "Every capture found its room. A growing list here would mean the room signals need a look.",
                    secondary: CoreAction("Back to Overview") { withAnimation { model.tab = .overview } }
                )
                .accessibilityIdentifier("inbox-empty")
            } else {
                if st.selected.isEmpty { SelectAll(model: model) } else { BulkBar(model: model) }
                LazyVStack(spacing: Space.s2) { ForEach(st.captures) { u in CaptureRow(model: model, u: u) } }
            }
        }
    }
}

/// The "…" menu of rows and of the bulk bar: the lesser actions, each with a quiet line saying what it does, so Exclude,
/// Mark private and Delete cannot be mixed up. Assign stays outside, as the one main action on the right.
private struct MoreMenu: View {
    let model: BrainModel
    let ids: [String]
    let split: Bool
    @Binding var open: Bool
    var body: some View {
        var items: [CoreDropdownItem] = []
        if split {
            items.append(
                CoreDropdownItem("Split…", symbol: "rectangle.split.2x1", note: "Give each part its own room") {
                    BrainSheets.split(model, ids[0])
                })
        }
        items.append(
            CoreDropdownItem("Mark private", symbol: "eye.slash", note: "Scrub it, never search it") {
                Task { await model.markPrivate(ids) }
            })
        items.append(
            CoreDropdownItem("Exclude", symbol: "nosign", destructive: true, note: "Refuse it and wipe it") {
                Task { await model.exclude(ids) }
            })
        items.append(
            CoreDropdownItem("Delete…", symbol: "trash", destructive: true, note: "Remove it after you review") {
                BrainSheets.confirmDelete(model, ids)
            })
        return CoreDropdown(items: items, isPresented: $open) {
            Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(GlassInk.primary)
                .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                .background(open ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
                .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                .contentShape(coreShape(Radius.control))
        }
        .help("More: \(items.map { $0.title.replacingOccurrences(of: "…", with: "") }.joined(separator: ", "))")
        .accessibilityLabel(ids.count == 1 ? "More actions for this capture" : "More actions for the selected captures")
        .accessibilityIdentifier("inbox-more")
    }
}

private struct SelectAll: View {
    let model: BrainModel
    var body: some View {
        let st = model.inboxState
        HStack {
            Button("Select all \(st.captures.count)") { st.selected = Set(st.captures.map(\.id)) }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
            Spacer(minLength: 0)
        }
    }
}

private struct BulkBar: View {
    let model: BrainModel
    @State private var more = false
    var body: some View {
        let ids = orderedSelection
        HStack(spacing: Space.s2) {
            Text("\(ids.count) selected").coreFont(size: MacTextSize.headline, weight: .semibold)
            Button("Select all") { model.inboxState.selected = Set(model.inboxState.captures.map(\.id)) }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .disabled(ids.count == model.inboxState.captures.count)
            Button("Clear") { model.inboxState.selected = [] }.buttonStyle(CoreButtonStyle(.plain, size: .small))
            Spacer(minLength: Space.s2)
            MoreMenu(model: model, ids: ids, split: false, open: $more)
            Button("Assign selected…") { BrainSheets.assign(model, ids) }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
        .padding(Space.s3).coreWell()
        .zIndex(more ? 10 : 0)
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
    @State private var more = false

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
                Text(u.source).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(2)
                ChipFlow(spacing: Space.s2) {
                    Text("Waiting \(BrainWords.glue(u.age))").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                    if u.stale { BrainChip("Stale", GlassInk.amber, help: "Older than 14 days") }
                    if u.inBell { BrainChip("In the bell", GlassInk.blue, help: "Older than 30 days") }
                    BrainChip(
                        u.guess.map { "Guess: \($0)" } ?? "No guess", GlassInk.slate,
                        help: "A local model may suggest a room only if you turn that on. It is advice, not action.")
                }
            }
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s2) {
                MoreMenu(model: model, ids: [u.id], split: true, open: $more)
                Button("Assign to a room…") { BrainSheets.assign(model, [u.id]) }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    .help("Choose the room this capture belongs to.")
            }
            .disabled(model.busy != nil)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .zIndex(more ? 10 : 0)
        .help("Capture id: \(u.id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-capture-\(u.id)")
    }
}
