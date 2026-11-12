import CoreUI
import SwiftUI

/// Step 3: one row per proposed room with Accept or Refuse, or one opened room. The footer imports what is accepted.
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
            } else if r.visible.isEmpty {
                Text("Nothing was found to put in a room.").foregroundStyle(GlassInk.secondary)
                    .padding(Space.s4).frame(maxWidth: .infinity).coreWell()
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(BrainWords.plural(r.visible.filter { !$0.isUnsorted }.count, "room", "rooms") + " found")
                        .coreFont(size: MacTextSize.headline, weight: .semibold)
                    Spacer(minLength: Space.s3)
                    Text(ReviewWords.tally(r.cards)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(r.visible) { ProposalRow(card: $0, review: r) }
                    }
                }
                .frame(maxHeight: Space.s8 * 14)
                .fixedSize(horizontal: false, vertical: true)
            }
            WizardFooter(
                back: ("Close", close),
                primary: (ReviewWords.importTitle(r.accepted.count), { Task { await model.commit() } }),
                enabled: r.canCommit)
        }
        .accessibilityIdentifier("brain-import-review")
    }
}

/// One proposed room: what it is and how much is in it, Accept or Refuse, and the way into it.
struct ProposalRow: View {
    let card: ProposalCard
    let review: ReviewModel

    var body: some View {
        CoreRow(card.name, subtitle: ReviewWords.line(card), symbol: card.isUnsorted ? "list.bullet" : "folder") {
            HStack(spacing: Space.s2) {
                if card.isUnsorted {
                    StateBadge("Waits in No room yet", tone: .queue, symbol: "tray")
                } else {
                    if card.isMixed { StateBadge(ReviewWords.mixed, tone: .warn, symbol: "exclamationmark.triangle") }
                    if card.isHeld { StateBadge("Held", tone: .queue, symbol: "clock").help(ReviewWords.held) }
                    CoreSegmented(
                        "Keep \(card.name)",
                        segments: [CoreSegment("accept", "Accept"), CoreSegment("refuse", "Refuse")],
                        selection: Binding(get: { choice }, set: pick)
                    )
                    .help(
                        review.acceptBlock(card)
                            ?? (card.isAccepted
                                ? "Click Accept again to take it out of the import."
                                : "Accept puts it in the import. Refuse leaves it out, next time too.")
                    )
                }
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
        .accessibilityIdentifier("brain-room-card-\(card.id)")
    }

    private var choice: String { card.isAccepted ? "accept" : card.state == "refused" ? "refuse" : "" }

    private func pick(_ v: String) { Task { await review.choose(card.id, v) } }
}
