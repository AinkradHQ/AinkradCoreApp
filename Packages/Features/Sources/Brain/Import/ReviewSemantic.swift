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

    /// What the Core tidied, once the step is done. Nil when it changed nothing.
    public var tidy: TidyView? {
        semanticState == "ready" ? semantic?.tidy.flatMap { $0.changes.isEmpty ? nil : $0 } : nil
    }

    /// Puts back everything the Core tidied, then reads the rooms and the step again.
    public func undoTidy() async {
        guard let run else { return }
        await act {
            try await routes.undoTidy(run: run)
            showingChanges = false
            await refresh()
            await readSemantic()
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
