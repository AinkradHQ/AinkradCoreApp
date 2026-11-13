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
    /// Only hints whose item is known by name: a nameless suggestion tells the person nothing.
    public var closestHints: [ClosestHint] {
        (semantic?.closest ?? []).filter { hintItems[$0.itemId] != nil && !dismissed.contains(Self.key($0)) }
    }
    public func hintItem(_ h: ClosestHint) -> ItemRow? { hintItems[h.itemId] }
    public var hasHints: Bool {
        !roomHints.isEmpty || !copyHints.isEmpty || !mergeHints.isEmpty || !closestHints.isEmpty
    }

    static func key(_ h: RoomHint) -> String { "room:\(h.name)" }
    static func key(_ h: DuplicateHint) -> String { "copies:\(h.keep)" }
    static func key(_ h: ClosestHint) -> String { "closest:\(h.itemId)" }
    static func key(_ h: MergeHint) -> String { "merge:\(h.from)>\(h.to)" }

    public func dismiss(_ h: RoomHint) { dismissed.insert(Self.key(h)) }
    public func dismiss(_ h: DuplicateHint) { dismissed.insert(Self.key(h)) }
    public func dismiss(_ h: ClosestHint) { dismissed.insert(Self.key(h)) }
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

    /// A room of this run takes the item by a move; a room filed earlier gets it as a new room named after it, the same
    /// route as a topic. Never done by itself.
    public func accept(_ h: ClosestHint) async {
        guard let run else { return }
        await act {
            if h.inReview {
                try await routes.moveItems(run: run, ids: [h.itemId], to: h.roomId)
            } else {
                _ = try await routes.split(
                    run: run, proposal: ProposalCard.unsortedID, itemIDs: [h.itemId], name: h.roomName)
            }
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
        await nameHintItems(v.closest.map(\.itemId))
    }

    /// Reads the Unsorted card's items page by page (never more than `maxPages`) until every id is named. One pass per id.
    func nameHintItems(_ ids: [String], maxPages: Int = 30) async {
        guard let run else { return }
        var need = Set(ids).subtracting(hintItems.keys).subtracting(hintLooked)
        guard !need.isEmpty else { return }
        hintLooked.formUnion(need)
        var after: Int?
        for _ in 0..<maxPages {
            guard
                let page = try? await routes.items(
                    run: run, proposal: ProposalCard.unsortedID, after: after, limit: 100)
            else { return }
            for row in page.items where need.contains(row.id) {
                hintItems[row.id] = row
                need.remove(row.id)
            }
            guard !need.isEmpty, let next = page.next else { return }
            after = next
        }
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
