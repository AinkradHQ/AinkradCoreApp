import CoreUI
import SwiftUI

/// Step 3: one row per proposed room with its box, or one opened room. The footer imports the ticked rooms; the unticked
/// ones are deleted, and a line above it says how many.
struct ReviewStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let r = model.review
        VStack(alignment: .leading, spacing: Space.s3) {
            if let n = r.notice {
                CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) {
                    Button("Dismiss") { r.notice = nil }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
            if r.opened != nil {
                ReviewDetail(review: r)
            } else if r.sameProjectFor != nil {
                SameProjectPicker(review: r)
            } else if r.showingChanges {
                TidyChangesList(review: r)
            } else if r.visible.isEmpty {
                Text("Nothing was found to put in a room.").foregroundStyle(GlassInk.secondary)
                    .padding(Space.s4).frame(maxWidth: .infinity).coreWell()
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(BrainWords.plural(r.visible.filter { !$0.isUnsorted }.count, "room", "rooms") + " found")
                        .coreFont(size: MacTextSize.headline, weight: .semibold)
                    Spacer(minLength: Space.s3)
                    Text(ReviewWords.tally(checked: r.kept.count, of: r.open.filter { !$0.isUnsorted }.count))
                        .coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
                SemanticStatusLine(review: r)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(r.visible) { ProposalRow(card: $0, review: r) }
                    }
                }
                .frame(maxHeight: Space.s8 * 14)
                .fixedSize(horizontal: false, vertical: true)
            }
            if r.opened == nil,
                let line = ReviewWords.willDelete(
                    rooms: r.dropped.filter { !$0.isUnsorted }.count, unsorted: !r.keepUnsorted)
            {
                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("brain-review-will-delete")
            }
            WizardFooter(
                back: ("Close", close),
                primary: (ReviewWords.importTitle(r.kept.count), { Task { await model.commit() } }),
                enabled: r.canCommit)
        }
        .accessibilityIdentifier("brain-import-review")
    }
}

/// One proposed room: its box, what it is and how much is in it, and the way into it.
struct ProposalRow: View {
    let card: ProposalCard
    let review: ReviewModel

    var body: some View {
        CoreRow(card.name, subtitle: subtitle, symbol: card.isUnsorted ? "list.bullet" : "folder") {
            HStack(spacing: Space.s2) {
                // The hint sits in the subtitle (it wraps there); the row keeps only the button, so the box never shrinks.
                if let s = card.suggestMerge, card.state == "proposed" {
                    Button("Merge") { Task { await review.merge(card.id, into: s.into) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Move everything in \(card.name) into \(s.name).")
                        .fixedSize()
                }
                if card.isUnsorted {
                    if review.isChecked(card) { StateBadge("Waits in No room yet", tone: .queue, symbol: "tray") }
                } else {
                    if card.isMixed { StateBadge(ReviewWords.mixed, tone: .warn, symbol: "exclamationmark.triangle") }
                    if card.isHeld { StateBadge("Held", tone: .queue, symbol: "clock").help(ReviewWords.held) }
                }
                if card.state != "committed" { RoomBox(card: card, review: review) }
                if review.offersSameProject(card) { ProposalMenu(card: card, review: review) }
                Button {
                    Task { await review.openCard(card.id) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Look inside \(card.name)")
                .accessibilityLabel("Open \(card.name)")
            }
            .disabled(review.busy)
        }
        .zIndex(review.menuFor == card.id ? 1 : 0)
        .accessibilityIdentifier("brain-room-card-\(card.id)")
    }

    private var subtitle: String {
        guard let s = card.suggestMerge, card.state == "proposed" else { return ReviewWords.line(card) }
        return "\(ReviewWords.line(card)) · \(ReviewWords.suggestion(s))"
    }
}

/// A room's one box: ticked is imported, unticked is deleted on Import. Unsorted's box keeps its items waiting in No room
/// yet. Local only: nothing reaches the Core until Import.
struct RoomBox: View {
    let card: ProposalCard
    let review: ReviewModel

    var body: some View {
        CoreCheckbox(
            card.isUnsorted ? "Keep" : "Import",
            isOn: Binding(get: { review.isChecked(card) }, set: { review.setChecked(card.id, $0) }),
            spoken: card.isUnsorted ? "Keep the Unsorted items" : "Import \(card.name)"
        )
        .fixedSize()
        .disabled(review.checkBlock(card) != nil)
        .help(
            review.checkBlock(card)
                ?? (card.isUnsorted
                    ? "Ticked, its items wait in No room yet. Unticked, they are deleted on Import."
                    : "Ticked, it is imported. Unticked, it is deleted on Import and refused next time too.")
        )
        .accessibilityIdentifier("brain-room-box-\(card.id)")
    }
}
