import CoreUI
import SwiftUI

/// One opened card: rename, kind, merge, split, refuse, the room's settings, and its items with Needed and Refused marks.
struct ReviewDetail: View {
    let review: ReviewModel
    @State private var name = ""
    @State private var mergeInto = ""
    @State private var splitName = ""
    @State private var days = ""
    @State private var local = false
    @State private var readers = ""
    @State private var grants = ""

    var body: some View {
        if let card = review.opened {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    header(card)
                    actions(card)
                    settings(card)
                    items(card)
                }
            }
            .frame(maxHeight: Space.s8 * 18)
            .onAppear { load(card) }
            .onChange(of: card) { _, c in load(c) }
        }
    }

    private func load(_ c: ProposalCard) {
        name = c.name
        days = c.config.reviewDays.map(String.init) ?? ""
        local = c.config.allowedModels == "local_only"
        readers = (c.config.readers ?? []).joined(separator: ", ")
        grants = (c.config.grants ?? []).joined(separator: ", ")
        mergeInto = review.visible.first { $0.id != c.id && !$0.isUnsorted }?.id ?? ""
    }

    private func header(_ c: ProposalCard) -> some View {
        HStack(spacing: Space.s2) {
            Button {
                review.closeCard()
            } label: {
                Label("All rooms", systemImage: "chevron.left")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Text(c.name).coreFont(size: MacTextSize.headline, weight: .semibold)
            if let s = ReviewWords.state(c) { BrainChip(s, GlassInk.blue) }
            ForEach(c.warnings, id: \.self) { BrainChip(ReviewWords.warning($0), GlassInk.red) }
            Spacer()
            if c.isAccepted {
                Button("Undo accept") { Task { await review.unaccept(c.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            } else {
                let block = review.acceptBlock(c)
                Button("Accept") { Task { await review.accept(c.id) } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(block != nil)
                    .help(block ?? "Put this room in the import.")
            }
        }
        .disabled(review.busy)
    }

    private func actions(_ c: ProposalCard) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !c.isUnsorted {
                HStack(alignment: .bottom, spacing: Space.s2) {
                    CoreTextField("Name", placeholder: "Room name", text: $name) {
                        Task { await review.rename(c.id, to: name) }
                    }
                    Button("Rename") { Task { await review.rename(c.id, to: name) } }
                        .buttonStyle(CoreButtonStyle(.secondary)).disabled(
                            name.trimmingCharacters(in: .whitespaces).isEmpty || name == c.name)
                    CoreSelect(
                        "Kind",
                        selection: Binding(get: { c.kind }, set: { k in Task { await review.setKind(c.id, k) } }),
                        options: ReviewWords.kinds.map { CoreSelectOption($0.id, $0.title) })
                }
            }
            let others = review.visible.filter { $0.id != c.id && !$0.isUnsorted }
            HStack(alignment: .bottom, spacing: Space.s2) {
                if !others.isEmpty {
                    CoreSelect(
                        "Merge with", selection: $mergeInto,
                        options: others.map { CoreSelectOption($0.id, $0.name) })
                    Button("Merge") { Task { await review.merge(c.id, into: mergeInto) } }
                        .buttonStyle(CoreButtonStyle(.secondary)).disabled(mergeInto.isEmpty)
                }
                CoreTextField("Split selected items into", placeholder: "New room name", text: $splitName)
                Button("Split…") {
                    Task {
                        await review.splitSelected(from: c.id, name: splitName)
                        splitName = ""
                    }
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(review.selected.isEmpty)
                .help("Choose items below first.")
                if !c.isUnsorted, c.state != "refused" {
                    Button("Refuse") { Task { await review.refuse(c.id) } }.buttonStyle(CoreButtonStyle(.secondary))
                }
            }
        }
        .disabled(review.busy)
    }

    private func settings(_ c: ProposalCard) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("This room's settings").coreFont(size: MacTextSize.headline, weight: .semibold)
            CoreSegmented(
                "Models allowed",
                segments: [CoreSegment(false, "Approved cloud"), CoreSegment(true, "Local models only")],
                selection: $local)
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreTextField("Review again after", placeholder: "180", text: $days, suffix: "days")
                CoreTextField("Readers besides you", placeholder: "Device names, comma separated", text: $readers)
            }
            CoreTextField("Grants", placeholder: "Comma separated", text: $grants)
            Text(
                "An admin sees every room. Every room is kept on your Core, encrypted. Review dates archive; nothing is deleted."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Button("Save settings") { Task { await review.setConfig(c.id, config()) } }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(review.busy)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    func config() -> RoomConfigWire {
        func list(_ s: String) -> [String] {
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return RoomConfigWire(
            allowedModels: local ? "local_only" : "approved_providers", readers: list(readers),
            reviewDays: Int(days.trimmingCharacters(in: .whitespaces)), grants: list(grants))
    }

    private func items(_ c: ProposalCard) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("\(c.itemCount) items").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer()
                Button("Needed") { Task { await review.markSelected("needed") } }
                Button("Refused") { Task { await review.markSelected("refused") } }
                Button("Clear mark") { Task { await review.markSelected("clear") } }
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .disabled(review.selected.isEmpty || review.busy)
            ForEach(review.itemsBySource, id: \.source) { group in
                Text(group.source.replacingOccurrences(of: "_", with: " ").capitalized)
                    .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                ForEach(group.rows) { row in
                    CoreCheckbox(
                        row.title.isEmpty ? "Untitled" : row.title,
                        detail: [String(row.startedAt.prefix(10)), row.mark.map { $0.capitalized }]
                            .compactMap { $0 }.joined(separator: " · "),
                        isOn: Binding(
                            get: { review.selected.contains(row.id) },
                            set: { on in
                                if on { review.selected.insert(row.id) } else { review.selected.remove(row.id) }
                            }))
                }
            }
            if review.more != nil {
                Button("Show more") { Task { await review.loadMore() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }
}
