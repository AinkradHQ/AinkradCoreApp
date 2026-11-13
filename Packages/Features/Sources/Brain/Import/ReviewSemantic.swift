import Foundation

/// The local AI's suggestions in the review. They are read in the background and never block the list; accepting one
/// uses the same routes as doing it by hand, and nothing applies until the person says so.
extension ReviewModel {
    /// `pending` while the model works, `ready` once it has answered, nil when it is off or this Core has no model.
    public var semanticState: String? {
        let s = semantic?.state ?? cards.compactMap(\.semantic).first
        return s == "pending" || s == "ready" ? s : nil
    }

    public var roomHints: [RoomHint] {
        (semantic?.rooms ?? []).filter { !dismissed.contains(Self.key($0)) }
    }
    public var copyHints: [DuplicateHint] {
        (semantic?.duplicates ?? []).filter { !dismissed.contains(Self.key($0)) }
    }
    /// Only rooms that exist as cards can merge, and a pair the cards already hint at is not shown twice.
    public var mergeHints: [MergeHint] {
        (semantic?.merges ?? []).filter { m in
            guard m.fromName != nil, m.toName != nil, !dismissed.contains(Self.key(m)),
                let from = cards.first(where: { $0.id == m.from }), from.state == "proposed"
            else { return false }
            return from.suggestMerge?.into != m.to
        }
    }
    public var hasHints: Bool { !roomHints.isEmpty || !copyHints.isEmpty || !mergeHints.isEmpty }

    static func key(_ h: RoomHint) -> String { "room:\(h.name)" }
    static func key(_ h: DuplicateHint) -> String { "copies:\(h.keep)" }
    static func key(_ h: MergeHint) -> String { "merge:\(h.from)>\(h.to)" }

    public func dismiss(_ h: RoomHint) { dismissed.insert(Self.key(h)) }
    public func dismiss(_ h: DuplicateHint) { dismissed.insert(Self.key(h)) }
    public func dismiss(_ h: MergeHint) { dismissed.insert(Self.key(h)) }

    /// Unsorted gives the topic's items to a new room.
    public func accept(_ h: RoomHint) async {
        guard let run else { return }
        await act {
            _ = try await routes.split(
                run: run, proposal: ProposalCard.unsortedID, itemIDs: h.itemIds, name: h.name)
            await refresh()
            await readSemantic()
        }
    }

    /// The newest stays; the others are refused, like a Refused mark by hand.
    public func accept(_ h: DuplicateHint) async {
        guard let run else { return }
        await act {
            try await routes.markItems(run: run, ids: h.itemIds.filter { $0 != h.keep }, mark: "refused")
            await refresh()
            await readSemantic()
        }
    }

    public func accept(_ h: MergeHint) async {
        await merge(h.from, into: h.to)
        await readSemantic()
    }

    /// One read. A Core without the route (or a failed read) leaves the review as it was, without a notice.
    func readSemantic() async {
        guard let run, let v = try? await routes.semantic(run: run) else { return }
        semantic = v
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
