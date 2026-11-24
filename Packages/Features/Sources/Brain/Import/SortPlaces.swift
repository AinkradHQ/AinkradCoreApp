import CoreUI
import SwiftUI

/// Sort's list: what the Core already did in one line, then one row per place (name, items, a couple of titles) and
/// Unsorted last. Keys act on the chosen place: ↑ ↓ choose, ⌘R rename, ⌘M merge, ⌘⌫ to Unsorted.
struct PlaceList: View {
    let model: ImportModel

    var body: some View {
        let r = model.review
        VStack(alignment: .leading, spacing: Space.s2) {
            if let line = summary(r) {
                HStack(spacing: Space.s2) {
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s2)
                    if model.auto.undoneItems == nil {
                        Button("See changes") { Task { await r.openChanges() } }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        Button("Undo") { Task { await r.undoTidy() } }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small))
                            .help("Put back every place the Core merged or moved.")
                    }
                }
                .accessibilityIdentifier("brain-sort-summary")
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(r.places) { PlaceRow(card: $0, review: r) }
                    if let u = r.unsortedCard {
                        CoreRow(
                            "Unsorted",
                            subtitle:
                                Self.unsorted(u),
                            symbol: "tray"
                        )
                        .accessibilityIdentifier("brain-sort-unsorted")
                    }
                }
            }
            .frame(maxHeight: Space.s8 * 14)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(r.busy)
            if r.renaming == nil, let f = r.focused { keys(r, f) }
        }
    }

    /// "1,204 items".
    static func items(_ n: Int) -> String { "\(n.formatted()) \(n == 1 ? "item" : "items")" }

    /// "57 items that fit no place, like Wifi-Hotspot, Photo backup and Recipe cards. They wait in No room yet."
    static func unsorted(_ u: ProposalCard) -> String {
        let like = u.sampleTitles.prefix(3).formatted(.list(type: .and))
        return items(u.itemCount) + " that fit no place" + (like.isEmpty ? "" : ", like \(like)")
            + ". They wait in No room yet."
    }

    /// The Core's own line, or the Undo of an old sort; nothing when neither says anything.
    private func summary(_ r: ReviewModel) -> String? {
        if let n = model.auto.undoneItems {
            return "Undone. \(BrainWords.plural(n, "item is", "items are")) back in one pile to sort."
        }
        guard let p = r.prepared else { return nil }
        return p + "."
    }

    /// Hidden buttons that carry the keys; the menu on each row shows them.
    private func keys(_ r: ReviewModel, _ f: ProposalCard) -> some View {
        ZStack {
            Button("") { r.moveFocus(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { r.moveFocus(1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { r.renaming = f.id }.keyboardShortcut("r", modifiers: .command)
            Button("") { if !r.mergeTargets(for: f.id).isEmpty { r.mergingFor = f.id } }
                .keyboardShortcut("m", modifiers: .command)
            Button("") { Task { await r.moveToUnsorted(f.id) } }.keyboardShortcut(.delete, modifiers: .command)
        }
        .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }
}

/// One place: name, how much is in it and a couple of its titles; its menu, or the name field while it is renamed.
struct PlaceRow: View {
    let card: ProposalCard
    let review: ReviewModel
    @State private var name = ""
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Group {
            if review.renaming == card.id {
                HStack(alignment: .bottom, spacing: Space.s2) {
                    CoreTextField("Name", placeholder: card.name, text: $name, autofocus: true)
                    Button("Cancel") { review.renaming = nil }.buttonStyle(CoreButtonStyle(.secondary))
                        .coreShortcut(.cancel)
                    Button("Save") { Task { await review.saveRename(card.id, name) } }
                        .buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(.primary)
                }
                .padding(Space.s2)
                .onAppear { name = card.name }
            } else {
                CoreRow(card.name, subtitle: subtitle, symbol: "folder", selected: review.focused?.id == card.id) {
                    HStack(spacing: Space.s2) {
                        if card.isMixed {
                            StateBadge(ReviewWords.mixed, tone: .warn, symbol: "exclamationmark.triangle")
                            Button("Open") { Task { await review.openCard(card.id) } }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        }
                        menu
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { review.focus = card.id }
            }
        }
        .zIndex(review.menuFor == card.id ? 1 : 0)
        .accessibilityIdentifier("brain-place-\(card.id)")
    }

    /// "1,204 items · Queue migration order, Runner rewrite plan".
    private var subtitle: String {
        let titles = card.sampleTitles.prefix(2).joined(separator: ", ")
        let n = PlaceList.items(card.itemCount)
        return titles.isEmpty ? n : "\(n) · \(titles)"
    }

    private var menu: some View {
        let canMerge = !review.mergeTargets(for: card.id).isEmpty
        return CoreDropdown(
            items: [
                CoreDropdownItem("Rename", symbol: "pencil", note: "⌘R") {
                    review.focus = card.id
                    review.renaming = card.id
                },
                CoreDropdownItem("Merge into…", symbol: "arrow.triangle.merge", enabled: canMerge, note: "⌘M") {
                    review.focus = card.id
                    review.mergingFor = card.id
                },
                CoreDropdownItem("Move to Unsorted", symbol: "tray", note: "⌘⌫") {
                    Task { await review.moveToUnsorted(card.id) }
                },
                CoreDropdownItem("Ignore This Place", symbol: "eye.slash") {
                    Task { await review.ignore(card.id) }
                },
            ],
            isPresented: Binding(
                get: { review.menuFor == card.id },
                set: { on in
                    if on { review.menuFor = card.id } else if review.menuFor == card.id { review.menuFor = nil }
                })
        ) {
            Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(palette.text2)
                .frame(width: MacSize.controlMd, height: MacSize.controlSm)
                .coreWell(radius: Radius.chip, active: hovering || review.menuFor == card.id)
                .contentShape(coreShape(Radius.chip))
                .onHover { hovering = $0 }
                .animation(Motion.out(Motion.hover), value: hovering)
        }
        .help("Rename, merge or move \(card.name)")
        .accessibilityLabel("More for \(card.name)")
        .accessibilityIdentifier("brain-place-menu-\(card.id)")
    }
}

/// Which place the chosen one merges into. Opens in place of the list; ⌘1… pick, Esc goes back.
struct MergePicker: View {
    let review: ReviewModel
    let id: String

    var body: some View {
        let from = review.cards.first { $0.id == id }
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Merge \(from?.name ?? "this place") into…").coreFont(size: MacTextSize.body, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(review.mergeTargets(for: id).enumerated()), id: \.element.id) { i, to in
                        CoreRow(to.name, subtitle: PlaceList.items(to.itemCount), symbol: "folder") {
                            let b = Button("Merge here") { Task { await review.mergePlace(id, into: to.id) } }
                                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                                .accessibilityLabel("Merge \(from?.name ?? "") into \(to.name)")
                            if i < 9 { b.coreShortcut(.number(i + 1)) } else { b }
                        }
                        .accessibilityIdentifier("brain-merge-\(to.id)")
                    }
                }
            }
            .frame(maxHeight: Space.s8 * 14)
            .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(review.busy)
        .accessibilityIdentifier("brain-merge-picker")
    }
}
