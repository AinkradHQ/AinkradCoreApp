import CoreUI
import SwiftUI

/// What the local AI notices in the review: topics among Unsorted, near-copies, rooms that look like one. Every row is a
/// suggestion with Accept and Dismiss; nothing applies by itself.
struct ReviewSuggestions: View {
    let review: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if !review.roomHints.isEmpty {
                group("Suggested rooms") {
                    ForEach(review.roomHints, id: \.name) { RoomHintRow(hint: $0, review: review) }
                }
            }
            if !review.closestHints.isEmpty {
                let all = review.closestHints
                group("Closest rooms") {
                    ForEach(all.prefix(Self.closestShown), id: \.itemId) { ClosestHintRow(hint: $0, review: review) }
                    if all.count > Self.closestShown {
                        Text("and \(all.count - Self.closestShown) more").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3)
                    }
                }
            }
            if !review.copyHints.isEmpty {
                group("Near-copies") {
                    ForEach(review.copyHints, id: \.keep) { CopyHintRow(hint: $0, review: review) }
                }
            }
            if !review.mergeHints.isEmpty {
                group("Merge hints") {
                    ForEach(review.mergeHints, id: \.from) { MergeHintRow(hint: $0, review: review) }
                }
            }
        }
        .accessibilityIdentifier("brain-review-suggestions")
    }

    static let closestShown = 5

    private func group<C: View>(_ title: String, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .padding(.bottom, Space.s1).accessibilityAddTraits(.isHeader)
            rows()
        }
    }
}

/// The quiet line while the model works, or when it found nothing. Never a spinner over the list.
struct SemanticStatusLine: View {
    let review: ReviewModel

    var body: some View {
        if let state = review.semanticState, state == "pending" || !review.hasHints {
            HStack(spacing: Space.s2) {
                if state == "pending" { CoreBusyBar().frame(width: Space.s8 * 2).accessibilityHidden(true) }
                Text(
                    state == "pending"
                        ? "Local AI: looking for duplicates and topics…" : "Local AI found no duplicates or topics."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            .help("Runs on your Core. Nothing leaves your server. It only suggests; you decide.")
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("brain-review-semantic-status")
        }
    }
}

private func percent(_ score: Double) -> String { "\(Int((score * 100).rounded()))% alike" }

private struct Buttons: View {
    let accept: String
    let help: String
    let busy: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: Space.s2) {
            Button(accept, action: onAccept).buttonStyle(CoreButtonStyle(.secondary, size: .small)).help(help)
            Button("Dismiss", action: onDismiss).buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Hide this suggestion. Nothing changes.")
        }
        .disabled(busy)
    }
}

private struct RoomHintRow: View {
    let hint: RoomHint
    let review: ReviewModel
    var body: some View {
        CoreRow(
            hint.name,
            subtitle: ([BrainWords.plural(hint.itemIds.count, "item", "items")] + [
                hint.keywords.joined(separator: ", ")
            ])
            .filter { !$0.isEmpty }.joined(separator: " · "),
            symbol: "folder.badge.plus"
        ) {
            HStack(spacing: Space.s3) {
                Text(percent(hint.score)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
                Buttons(
                    accept: "Accept", help: "Make a room called \(hint.name) from these items in No room yet.",
                    busy: review.busy, onAccept: { Task { await review.accept(hint) } },
                    onDismiss: { review.dismiss(hint) })
            }
        }
        .accessibilityIdentifier("brain-suggest-room-\(hint.name)")
    }
}

private struct CopyHintRow: View {
    let hint: DuplicateHint
    let review: ReviewModel
    var body: some View {
        let n = hint.itemIds.count
        CoreRow(
            "\(n) items say nearly the same thing", subtitle: "Keeps the newest, refuses the other \(n - 1)",
            symbol: "doc.on.doc"
        ) {
            HStack(spacing: Space.s3) {
                Text(percent(hint.score)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
                Buttons(
                    accept: "Accept", help: "Keep the newest. Refuse the other \(n - 1), next time too.",
                    busy: review.busy, onAccept: { Task { await review.accept(hint) } },
                    onDismiss: { review.dismiss(hint) })
            }
        }
        .accessibilityIdentifier("brain-suggest-copies-\(hint.keep)")
    }
}

private struct MergeHintRow: View {
    let hint: MergeHint
    let review: ReviewModel
    var body: some View {
        let from = hint.fromName ?? hint.from
        let to = hint.toName ?? hint.to
        CoreRow(
            "\(from) looks like \(to)", subtitle: "Move everything in \(from) into \(to)",
            symbol: "arrow.triangle.merge"
        ) {
            HStack(spacing: Space.s3) {
                Text(percent(hint.score)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
                Buttons(
                    accept: "Merge", help: "Move everything in \(from) into \(to).", busy: review.busy,
                    onAccept: { Task { await review.accept(hint) } }, onDismiss: { review.dismiss(hint) })
            }
        }
        .accessibilityIdentifier("brain-suggest-merge-\(hint.from)")
    }
}

/// One item no rule placed, and the room it looks closest to. The runner-up is only a quiet second line.
private struct ClosestHintRow: View {
    let hint: ClosestHint
    let review: ReviewModel
    var body: some View {
        let item = review.hintItem(hint)
        CoreRow(
            item.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "",
            subtitle: "Looks like it belongs in \(hint.roomName) (\(ReviewWords.score(hint.score)))"
                + (hint.runnerUp.map { " · next closest \($0.roomName) (\(ReviewWords.score($0.score)))" } ?? ""),
            symbol: "arrow.turn.down.right"
        ) {
            Buttons(
                accept: "Accept",
                help: hint.inReview
                    ? "Move this item into \(hint.roomName)." : "Make a room called \(hint.roomName) for this item.",
                busy: review.busy, onAccept: { Task { await review.accept(hint) } },
                onDismiss: { review.dismiss(hint) })
        }
        .accessibilityIdentifier("brain-suggest-closest-\(hint.itemId)")
    }
}
