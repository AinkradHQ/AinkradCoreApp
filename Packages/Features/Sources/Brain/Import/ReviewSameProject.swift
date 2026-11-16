import CoreUI
import SwiftUI

/// "Same project as…" (API minor 72): two rooms that are one project under two names. Unlike Merge, the Core remembers it,
/// so the next imports file the first room's items under the second by themselves.
extension ReviewModel {
    /// The rooms `id` can be the same project as: the other live rooms of this run, not Unsorted.
    public func sameProjectChoices(for id: String) -> [ProposalCard] {
        visible.filter { $0.id != id && !$0.isUnsorted && ["proposed", "accepted"].contains($0.state) }
    }

    /// Whether the row of `card` offers "Same project as…".
    public func offersSameProject(_ card: ProposalCard) -> Bool {
        canSameProject && !card.isUnsorted && ["proposed", "accepted"].contains(card.state)
            && !sameProjectChoices(for: card.id).isEmpty
    }

    public func openSameProject(_ id: String) {
        closeCard()
        showingChanges = false
        sameProjectFor = id
    }

    public func closeSameProject() { sameProjectFor = nil }

    /// Merges `id` into `into` and has the Core remember it, then reads the rooms again.
    public func sameProject(_ id: String, into: String) async {
        guard let run, let from = cards.first(where: { $0.id == id }) else { return }
        await act {
            let to = try await routes.sameProject(run: run, proposal: id, into: into)
            await refresh()
            sameProjectFor = nil
            host.shell.showToast("\(from.name) is now part of \(to.name).")
        }
    }
}

/// The row's "…": the rarer actions on a room. Today only "Same project as…".
struct ProposalMenu: View {
    let card: ProposalCard
    let review: ReviewModel
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let open = review.menuFor == card.id
        CoreDropdown(
            items: [
                CoreDropdownItem("Same project as…", symbol: "arrow.triangle.merge") {
                    review.openSameProject(card.id)
                }
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
                .coreWell(radius: Radius.chip, active: hovering || open)
                .contentShape(coreShape(Radius.chip))
                .onHover { hovering = $0 }
                .animation(Motion.out(Motion.hover), value: hovering)
        }
        .help("More for \(card.name)")
        .accessibilityLabel("More for \(card.name)")
        .accessibilityIdentifier("brain-room-menu-\(card.id)")
    }
}

/// Which room the chosen one is the same project as. Opens in place of the rooms, like a room does.
struct SameProjectPicker: View {
    let review: ReviewModel

    var body: some View {
        if let id = review.sameProjectFor, let card = review.cards.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Button {
                        review.closeSameProject()
                    } label: {
                        Label("All rooms", systemImage: "chevron.left")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Which room is the same project?").coreFont(size: MacTextSize.headline, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Text("The Core remembers this for next imports.").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(review.sameProjectChoices(for: id)) { to in
                            CoreRow(to.name, subtitle: ReviewWords.line(to), symbol: "folder") {
                                Button("Choose") { Task { await review.sameProject(id, into: to.id) } }
                                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                                    .help("Put \(card.name) in \(to.name), now and in next imports.")
                                    .accessibilityLabel("\(card.name) is the same project as \(to.name)")
                            }
                            .accessibilityIdentifier("brain-same-project-\(to.id)")
                        }
                    }
                }
                .frame(maxHeight: Space.s8 * 14)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(review.busy)
            .accessibilityIdentifier("brain-same-project-picker")
        }
    }
}
