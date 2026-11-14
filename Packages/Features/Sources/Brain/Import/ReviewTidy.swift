import CoreUI
import SwiftUI

/// The local AI's one line under "N rooms found": its progress while it reads, then what it tidied with Undo and
/// See changes. Never a row to decide on: the Core did the tidying, the person only undoes it if they disagree.
struct SemanticStatusLine: View {
    let review: ReviewModel

    var body: some View {
        if let state = review.semanticState {
            HStack(spacing: Space.s3) {
                if state == "pending" {
                    if let p = review.semanticProgress {
                        CoreMeter(Double(p.done) / Double(p.total), label: "Local AI progress")
                            .frame(width: Space.s8 * 4)
                    }
                    words(ReviewWords.reading(review.semanticProgress))
                } else if let t = review.tidy {
                    words(ReviewWords.tidied(t))
                    Spacer(minLength: Space.s3)
                    Button("Undo") { Task { await review.undoTidy() } }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Put back every room and item the local AI changed.")
                        .accessibilityIdentifier("brain-review-tidy-undo")
                    Button("See changes") { review.showingChanges = true }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("List every change by name.")
                        .accessibilityIdentifier("brain-review-tidy-changes")
                } else {
                    words("Local AI found nothing to tidy.")
                }
            }
            .disabled(review.busy)
            .help("Runs on your Core. Nothing leaves your server.")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("brain-review-semantic-status")
        }
    }

    private func words(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Every change the local AI made, grouped by kind, each by name. Opens in place of the rooms, like a room does.
struct TidyChanges: View {
    let review: ReviewModel
    let tidy: TidyView

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Button {
                    review.showingChanges = false
                } label: {
                    Label("All rooms", systemImage: "chevron.left")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Text("What the local AI changed").coreFont(size: MacTextSize.headline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s3)
                Button("Undo all") { Task { await review.undoTidy() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(review.busy)
                    .help("Put back every room and item the local AI changed.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(ReviewWords.tidyGroups(tidy), id: \.title) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).coreFont(size: MacTextSize.meta, weight: .semibold)
                                .foregroundStyle(GlassInk.secondary).padding(.bottom, Space.s1)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(g.changes) { c in
                                CoreRow(c.title, subtitle: ReviewWords.change(c), symbol: g.symbol)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: Space.s8 * 14)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("brain-review-tidy-list")
    }
}
