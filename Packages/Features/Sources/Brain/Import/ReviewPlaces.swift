import Foundation

/// Sort as a review (Ahmed, 2026-11-21: review before filing). The Core prepared the places; the person renames, merges or
/// sends a place to Unsorted, then approves the lot. Every change is one existing route; nothing is filed before Approve.
extension ReviewModel {
    /// The places Approve files: live, not empty, Unsorted aside. In the Core's order (by name).
    public var places: [ProposalCard] {
        visible.filter { !$0.isUnsorted && $0.itemCount > 0 && ["proposed", "accepted", "held"].contains($0.state) }
    }

    /// Unsorted, when it holds anything. Shown last.
    public var unsortedCard: ProposalCard? { visible.first { $0.isUnsorted && $0.itemCount > 0 } }

    /// Nothing to file and nothing waiting in Unsorted.
    public var nothingToReview: Bool { places.isEmpty && unsortedCard == nil }

    /// Why Approve cannot run yet: a place that mixes two employers (the Core refuses to file it).
    public var approveBlock: String? {
        places.first(where: \.isMixed).map { "Two employers are in \($0.name). Open it and split it first." }
    }

    /// The places `id` can merge into.
    public func mergeTargets(for id: String) -> [ProposalCard] { places.filter { $0.id != id } }

    /// The place the keys act on: the chosen one while it is still listed, else the first.
    public var focused: ProposalCard? { places.first { $0.id == focus } ?? places.first }

    /// ↑ ↓ between the places.
    public func moveFocus(_ by: Int) {
        guard !places.isEmpty else { return }
        let i = places.firstIndex { $0.id == focused?.id } ?? 0
        focus = places[min(max(i + by, 0), places.count - 1)].id
    }

    /// Inline rename, saved on Return. An empty or unchanged name just closes the field.
    public func saveRename(_ id: String, _ name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !n.isEmpty, n != cards.first(where: { $0.id == id })?.name else { return }
        await rename(id, to: n)
    }

    /// Merge from the picker: everything in `id` moves into `into`.
    public func mergePlace(_ id: String, into: String) async {
        mergingFor = nil
        await merge(id, into: into)
        if focus == id { focus = into }
    }

    /// Every item of `id` goes to Unsorted (the Core never merges into Unsorted, so the items are moved). The empty place
    /// is then not filed on Approve.
    public func moveToUnsorted(_ id: String) async {
        guard let run else { return }
        await act {
            var ids: [String] = []
            var after: Int?
            repeat {
                let page = try await routes.items(run: run, proposal: id, after: after, limit: 200)
                ids += page.items.map(\.id)
                after = page.next
            } while after != nil
            // ponytail: one call per 5,000 items, the Core's cap per PATCH.
            for start in stride(from: 0, to: ids.count, by: 5000) {
                try await routes.moveItems(
                    run: run, ids: Array(ids[start..<min(start + 5000, ids.count)]), to: ProposalCard.unsortedID)
            }
            await refresh()
        }
    }

    /// Ignore (2026-11-23): the place stays out of the Brain, none of its items are kept, and once the import is approved
    /// its folders are skipped in later imports (the Core writes the refuse rule, see Sources > Rules).
    public func ignore(_ id: String) async {
        guard let run else { return }
        await act {
            _ = try await routes.refuse(run: run, proposal: id)
            await refresh()
        }
    }

    /// What the Core already did, in one line ("Merged 7 into 3 places, 12 small ones to Unsorted"); nil when it does not
    /// say. Read from the tidy summary: the local model's, or (Core 0.10.2, no model) the one by names and sizes.
    public var prepared: String? {
        guard let v = semantic, v.state != "pending", let a = v.aiTidy, a.state != "undone", a.state != "declined",
            let t = a.summary
        else { return nil }
        var parts: [String] = []
        if let b = t.roomsBefore, let a = t.roomsAfter, b > a {
            parts.append("Merged \(b) into \(BrainWords.plural(a, "place", "places"))")
        } else if let m = t.roomsMerged, m > 0 {
            parts.append("Merged \(BrainWords.plural(m, "place", "places"))")
        }
        if let f = t.roomsFolded, f > 0 {
            parts.append("\(f) small \(f == 1 ? "one" : "ones") to Unsorted or a close place")
        }
        if let d = t.duplicatesMerged, d > 0 {
            parts.append(BrainWords.plural(d, "duplicate", "duplicates") + " dropped")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
