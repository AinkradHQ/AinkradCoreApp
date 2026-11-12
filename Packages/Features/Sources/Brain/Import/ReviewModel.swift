import Admin
import Foundation
import Observation

/// Step 3: the proposed rooms. Every action is one route and the card the Core answers with replaces the one on screen, so
/// the screen never shows a state the Core did not confirm.
@MainActor @Observable
public final class ReviewModel {
    let host: any AdminHost
    let routes: BrainRoutes
    var run: String?

    public private(set) var cards: [ProposalCard] = []
    /// The card opened for a closer look, and its items so far.
    public private(set) var openID: String?
    public private(set) var items: [ItemRow] = []
    public private(set) var more: Int?
    public var selected: Set<String> = []
    public internal(set) var notice: String?
    public private(set) var busy = false

    public init(host: any AdminHost, routes: BrainRoutes) {
        self.host = host
        self.routes = routes
    }

    // MARK: derived

    /// A merged room is gone from the list; Unsorted is always last.
    public var visible: [ProposalCard] {
        let live = cards.filter { $0.state != "merged" }
        return live.filter { !$0.isUnsorted } + live.filter(\.isUnsorted)
    }
    public var accepted: [ProposalCard] { cards.filter(\.isAccepted) }
    public var refusedCount: Int { cards.filter { $0.state == "refused" }.count }
    public var opened: ProposalCard? { cards.first { $0.id == openID } }
    /// Import accepted rooms (n): at least one, and none that mixes two employers (the Core checks again).
    public var canCommit: Bool { !accepted.isEmpty && !accepted.contains(where: \.isMixed) && !busy }

    /// Whether Accept works on this card, and if not, why.
    public func acceptBlock(_ c: ProposalCard) -> String? {
        if c.isUnsorted { return "Unsorted is not a room. Move its items to one first." }
        if c.isMixed { return "Two employers are in this room. Split it first." }
        if c.state == "refused" { return "This room was refused." }
        return nil
    }

    // MARK: loading

    func load(run: String) async throws {
        self.run = run
        cards = try await routes.proposals(run: run)
    }

    /// Re-reads the cards after an action that touches more than one (merge, split, refuse, commit).
    func refresh() async {
        guard let run, let fresh = try? await routes.proposals(run: run) else { return }
        cards = fresh
    }

    func replace(_ card: ProposalCard) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card } else { cards.append(card) }
    }

    // MARK: actions

    private func act(_ work: () async throws -> Void) async {
        busy = true
        notice = nil
        defer { busy = false }
        do { try await work() } catch { notice = BrainWords.failure(error) }
    }

    public func accept(_ id: String) async {
        guard let c = cards.first(where: { $0.id == id }) else { return }
        if let why = acceptBlock(c) {
            notice = why
            return
        }
        await patch(id, ProposalPatchBody(state: "accepted"))
    }

    public func unaccept(_ id: String) async { await patch(id, ProposalPatchBody(state: "proposed")) }
    public func rename(_ id: String, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        await patch(id, ProposalPatchBody(name: n))
    }
    public func setKind(_ id: String, _ kind: String) async { await patch(id, ProposalPatchBody(kind: kind)) }
    public func setConfig(_ id: String, _ config: RoomConfigWire) async {
        await patch(id, ProposalPatchBody(config: config))
    }

    private func patch(_ id: String, _ body: ProposalPatchBody) async {
        guard let run else { return }
        await act { replace(try await routes.patch(run: run, proposal: id, body)) }
    }

    /// Everything in `id` moves into `into`; both rooms are reviewed again, so the cards are re-read.
    public func merge(_ id: String, into: String) async {
        guard let run else { return }
        await act {
            _ = try await routes.merge(run: run, proposal: id, into: into)
            await refresh()
            if openID == id { closeCard() }
        }
    }

    /// The selected items become a new room.
    public func splitSelected(from id: String, name: String?) async {
        guard let run, !selected.isEmpty else { return }
        let ids = Array(selected)
        await act {
            _ = try await routes.split(run: run, proposal: id, itemIDs: ids, name: name?.isEmpty == true ? nil : name)
            selected = []
            await refresh()
            await reopen(id)
        }
    }

    /// Refusing writes a draft rule on the Core, so the same material is refused next time.
    public func refuse(_ id: String) async {
        guard let run else { return }
        await act {
            replace(try await routes.refuse(run: run, proposal: id))
            if openID == id { closeCard() }
        }
    }

    /// `mark` is `needed`, `refused` or `clear`, for the selected items.
    public func markSelected(_ mark: String) async {
        guard let run, !selected.isEmpty else { return }
        let ids = Array(selected)
        await act {
            try await routes.markItems(run: run, ids: ids, mark: mark)
            let value: String? = mark == "clear" ? nil : mark
            for i in items.indices where selected.contains(items[i].id) { items[i].mark = value }
            selected = []
        }
    }

    // MARK: one card's items

    public func openCard(_ id: String) async {
        openID = id
        items = []
        more = nil
        selected = []
        await loadMore()
    }

    func reopen(_ id: String) async { await openCard(id) }

    public func closeCard() {
        openID = nil
        items = []
        more = nil
        selected = []
    }

    public func loadMore(limit: Int = 100) async {
        guard let run, let id = openID else { return }
        let after = items.isEmpty ? nil : more
        if !items.isEmpty, more == nil { return }
        await act {
            let page = try await routes.items(run: run, proposal: id, after: after, limit: limit)
            guard openID == id else { return }
            items += page.items
            more = page.next
        }
    }

    /// The opened card's items grouped by source, in the order the sources first appear.
    public var itemsBySource: [(source: String, rows: [ItemRow])] {
        var order: [String] = []
        for r in items where !order.contains(r.sourceKind) { order.append(r.sourceKind) }
        return order.map { s in (s, items.filter { $0.sourceKind == s }) }
    }
}
