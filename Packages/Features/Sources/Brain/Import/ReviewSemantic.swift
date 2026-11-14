import Foundation

/// The local AI step of the review. The Core tidies the proposal by itself (duplicates out, small rooms folded) and the
/// review only shows what it did, with one Undo. Read in the background; it never blocks the list.
extension ReviewModel {
    /// `pending` while the model works, `ready` once it has answered, nil when it is off or this Core has no model.
    public var semanticState: String? {
        let s = semantic?.state ?? cards.compactMap(\.semantic).first
        return s == "pending" || s == "ready" ? s : nil
    }

    /// How far the model is, while it works. Nil on a Core that does not say.
    public var semanticProgress: SemanticProgress? {
        semanticState == "pending" ? semantic?.progress.flatMap { $0.total > 0 ? $0 : nil } : nil
    }

    /// What the Core tidied, once the step is done. Nil while it works, when it changed nothing, and after Undo.
    public var tidy: TidySummary? {
        guard semanticState == "ready", let t = semantic?.aiTidy, t.state != "undone" else { return nil }
        return t.summary
    }

    /// The person undid the tidy; Re-sort runs it again.
    public var tidyUndone: Bool { semanticState == "ready" && semantic?.aiTidy?.state == "undone" }

    /// Opens the list of changes in place of the rooms and reads it, with the items it names.
    public func openChanges() async {
        guard let run else { return }
        showingChanges = true
        await act {
            let all = try await routes.tidyChanges(run: run).changes
            await nameItems(all.compactMap(Self.namedItem))
            tidyChanges = all
        }
    }

    public func closeChanges() { showingChanges = false }

    /// The item a change is about, when the change names an item rather than a room.
    static func namedItem(_ c: TidyChange) -> String? {
        switch c.kind {
        case "duplicate": c.to
        case "move": c.itemIds.first
        default: nil
        }
    }

    /// Puts back everything the Core tidied, then reads the rooms again.
    public func undoTidy() async {
        guard let run else { return }
        await act {
            semantic = try await routes.undoTidy(run: run)
            showingChanges = false
            tidyChanges = nil
            await refresh()
        }
    }

    /// Reads the cards' item pages (never more than `maxPages` in all) until every id has a title.
    func nameItems(_ ids: [String], maxPages: Int = 40) async {
        guard let run else { return }
        var need = Set(ids).subtracting(itemTitles.keys)
        var pages = 0
        for card in visible where !need.isEmpty {
            var after: Int?
            while pages < maxPages, !need.isEmpty {
                pages += 1
                guard let page = try? await routes.items(run: run, proposal: card.id, after: after, limit: 100)
                else { break }
                for row in page.items where need.contains(row.id) {
                    itemTitles[row.id] = row.title
                    need.remove(row.id)
                }
                guard let next = page.next else { break }
                after = next
            }
        }
    }

    /// One read. A Core without the route (or a failed read) leaves the review as it was, without a notice.
    func readSemantic() async {
        guard let run, let v = try? await routes.semantic(run: run) else { return }
        let finished = semantic?.state == "pending" && v.state != "pending"
        semantic = v
        // The Core tidied the rooms when the step finished: the cards on screen are the old ones.
        if finished { await refresh() }
    }

    /// Reads now, and again every few seconds while the model works. Quiet: never sets a notice, never blocks.
    func watchSemantic() {
        watching?.cancel()
        watching = nil
        guard cards.contains(where: { $0.semantic == "pending" || $0.semantic == "ready" }) else {
            semantic = nil
            return
        }
        let wait = pollEvery
        watching = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.readSemantic()
                if self.semantic?.state != "pending" { break }
                try? await Task.sleep(for: wait)
            }
        }
    }

    public func stopWatching() {
        watching?.cancel()
        watching = nil
    }
}
