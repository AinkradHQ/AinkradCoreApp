import Foundation

/// One place's page (2026-11-23 redesign): its lists by area, what it read and what Brain learned from each source. The
/// lists need the place filter of API minor 101; an older Core answers nil and the page hides them.
extension BrainCalmModel {
    /// The place's newest or best records of one area, at most `limit`, and how many there are in all.
    func placeRecords(_ area: String, room: String, type: String? = nil, limit: Int) async -> BrainAreaPageWire? {
        #if DEBUG
        if routes == nil, let demo = demoRecords[area] {
            let all = demo.filter { $0.room == room && (type == nil || $0.type == type) }
            return BrainAreaPageWire(records: Array(all.prefix(limit)), total: all.count, lockedRooms: 0)
        }
        #endif
        guard v101, let routes else { return nil }
        return try? await routes.area(area, room: room, type: type, limit: limit)
    }

    /// Opens Rules, Knowledge or Timeline narrowed to one place (`type` picks facts or decisions on Knowledge).
    public func openFiltered(_ p: Page, room: String, type: String? = nil) async {
        page = p
        picked = nil
        topic = nil
        filterText = ""
        records = []
        if p == .rules { ruleRoom = room } else { topicRoom = room }
        if p == .knowledge, let type { knowledgeType = type }
        await loadRecords()
    }

    /// The place's newest sources (up to 100, the Core's cap), newest first.
    func placeSources(room: String) async -> RoomLatest? {
        #if DEBUG
        if let d = demoLatest { return d }
        #endif
        if let routes, let l = try? await routes.latest(room: room, limit: 100) { return l }
        return try? await service?.latest(room: room)
    }

    func placeSearch(room: String, _ q: String) async -> [SearchHit] {
        #if DEBUG
        if let d = demoLatest {
            return d.items.filter { $0.title.localizedCaseInsensitiveContains(q) }.map {
                SearchHit(
                    itemID: $0.itemID, sourceKind: $0.sourceKind, title: $0.title, snippet: "", startedAt: $0.startedAt)
            }
        }
        #endif
        return (try? await service?.search(room: room, query: q)) ?? []
    }

    /// The start of a source's text and what Brain learned from it.
    func trace(room: String, item: String) async -> SourceTraceWire? {
        #if DEBUG
        if routes == nil, let d = demoTrace { return d }
        #endif
        guard let routes else { return nil }
        return try? await routes.trace(room: room, item: item)
    }

    /// Archives every record Brain learned from one source; answers the ids it took out (for Undo).
    func forgetLearned(room: String, ids: [String]) async -> [String] {
        #if DEBUG
        if routes == nil {
            demoTrace?.records.removeAll { ids.contains($0.id) }
            return ids
        }
        #endif
        guard let routes else { return [] }
        var done: [String] = []
        for id in ids {
            do {
                try await routes.archiveRecord(room: room, id: id)
                done.append(id)
            } catch { notice = BrainWords.failure(error) }
        }
        return done
    }

    func restore(room: String, ids: [String]) async {
        #if DEBUG
        if routes == nil { return }
        #endif
        for id in ids { await restore(room: room, id: id) }
    }
}
