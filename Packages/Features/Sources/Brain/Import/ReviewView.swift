import CoreUI
import SwiftUI

/// Step 3: a grid of room cards, or one opened card. The footer imports what is accepted.
struct ReviewStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let r = model.review
        VStack(alignment: .leading, spacing: Space.s3) {
            if let n = r.notice {
                CoreNotice(symbol: "exclamationmark.circle", title: n, tone: .fail) {
                    Button("Dismiss") { r.notice = nil }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            if r.opened != nil {
                ReviewDetail(review: r)
            } else if r.visible.isEmpty {
                Text("Nothing was found to put in a room.").foregroundStyle(GlassInk.secondary)
                    .padding(Space.s4).frame(maxWidth: .infinity).coreWell()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Space.s8 * 9), spacing: Space.s3, alignment: .top)],
                        spacing: Space.s3
                    ) {
                        ForEach(r.visible) { ProposalCardView(card: $0, review: r) }
                    }
                }
                .frame(maxHeight: Space.s8 * 16)
            }
            if r.refusedCount > 0 {
                Text("\(r.refusedCount) refused. The same material is refused next time.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            CoreDialogFooter(
                cancel: CoreAction("Close", key: .cancel, run: close),
                primary: CoreAction("Import accepted rooms (\(r.accepted.count))", key: .primary) {
                    Task { await model.commit() }
                }, enabled: r.canCommit)
        }
        .accessibilityIdentifier("brain-import-review")
    }
}

/// One proposed room: what it is, what is in it, and the three quick actions. The rest is in the opened card.
struct ProposalCardView: View {
    let card: ProposalCard
    let review: ReviewModel

    var body: some View {
        let block = review.acceptBlock(card)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s2)
                if let s = ReviewWords.state(card) {
                    BrainChip(s, card.state == "refused" ? GlassInk.slate : GlassInk.blue)
                }
            }
            ChipFlow(spacing: Space.s2) {
                BrainChip(ReviewWords.kind(card.kind), GlassInk.slate)
                ForEach(card.warnings, id: \.self) { BrainChip(ReviewWords.warning($0), GlassInk.red) }
            }
            Text("\(card.itemCount) items \(ReviewWords.range(card.first, card.last))")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            ForEach(card.sampleTitles.prefix(3), id: \.self) {
                Text($0).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            if card.isHeld {
                Text(ReviewWords.held).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.s2) {
                if card.isAccepted {
                    Button("Undo accept") { Task { await review.unaccept(card.id) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                } else {
                    Button("Accept") { Task { await review.accept(card.id) } }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(block != nil)
                        .help(block ?? "Put this room in the import.")
                }
                Button("Open") { Task { await review.openCard(card.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                if !card.isUnsorted, card.state != "refused" {
                    Button("Refuse") { Task { await review.refuse(card.id) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Leave this out, and refuse the same material next time.")
                }
            }
            .disabled(review.busy)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 6, alignment: .topLeading)
        .coreWell().opacity(card.state == "refused" ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-room-card-\(card.id)")
    }
}
