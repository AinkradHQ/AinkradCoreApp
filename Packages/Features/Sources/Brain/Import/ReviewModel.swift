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
    /// The local model's suggestions, read from `/semantic`; nil until the first read or on a Core without it.
    public internal(set) var semantic: SemanticView?
    /// The list of what the local AI tidied is open in place of the rooms.
    public internal(set) var showingChanges = false
    /// The tidy's changes, read when the person opens them; nil until then.
    public internal(set) var tidyChanges: [TidyChange]?
    /// Titles of the items a change names (the kept copy, a moved item), read from the cards' item pages.
    public internal(set) var itemTitles: [String: String] = [:]
    /// The connected Core remembers "Same project as…" (API minor 72). Set by the pane.
    public internal(set) var canSameProject = false
    /// The room whose "Same project as…" picker is open in place of the rooms.
    public internal(set) var sameProjectFor: String?
    /// The room whose "…" menu is open; its row draws above the rows under it so the menu is not covered.
    public var menuFor: String?
    /// Rooms the person unticked. Every room starts ticked; ticking is local until Import, which sends the ticked ones.
    public internal(set) var unchecked: Set<String> = []
    /// Called after every tick, so the run's resume state keeps the selection.
    @ObservationIgnored var onSelection: (Set<String>) -> Void = { _ in }
    /// The connected Core takes the ticked rooms in the commit itself (API minor 73). Set by the pane.
    public internal(set) var keepsInCommit = false
    /// How long to wait between two reads while the model works.
    var pollEvery: Duration = .seconds(5)
    var watching: Task<Void, Never>?
    /// The time left at the local model's measured pace while it reads; nil until two readings apart show a pace.
    public internal(set) var readingLeft: Duration?
    @ObservationIgnored var pace: (at: ContinuousClock.Instant, done: Int)?
    /// Sort (review before filing): the place being renamed inline, the one whose merge target is being picked, and the
    /// place the keys act on.
    public var renaming: String?
    public var mergingFor: String?
    public var focus: String?
    /// Sort on the calm Core: read the tidy summary even with the local model off (it tidies by names then).
    public var readsPrepared = false

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
    public var opened: ProposalCard? { cards.first { $0.id == openID } }
    /// The rooms still to decide on: an imported one has no box.
    public var open: [ProposalCard] { visible.filter { $0.state != "committed" } }
    /// The ticked rooms, Unsorted not counted: what Import makes.
    public var kept: [ProposalCard] { open.filter { !$0.isUnsorted && isChecked($0) } }
    /// The unticked rooms, Unsorted too: what Import deletes.
    public var dropped: [ProposalCard] { open.filter { !isChecked($0) } }
    /// Unsorted's items wait in No room yet unless its box is unticked.
    public var keepUnsorted: Bool { open.first(where: \.isUnsorted).map(isChecked) ?? true }
    /// Import n rooms: at least one ticked (a room that mixes two employers cannot be ticked; the Core checks again).
    public var canCommit: Bool { !kept.isEmpty && !busy }

    /// Why this room's box cannot be ticked, if it cannot.
    public func checkBlock(_ c: ProposalCard) -> String? {
        !c.isUnsorted && c.isMixed ? "Two employers are in this room. Split it first." : nil
    }
    public func isChecked(_ c: ProposalCard) -> Bool { checkBlock(c) == nil && !unchecked.contains(c.id) }
    /// Local only: nothing is sent until Import.
    public func setChecked(_ id: String, _ on: Bool) {
        if on { unchecked.remove(id) } else { unchecked.insert(id) }
        onSelection(unchecked)
    }

    // MARK: loading

    func load(run: String) async throws {
        self.run = run
        cards = try await routes.proposals(run: run)
        watchSemantic()
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

    func act(_ work: () async throws -> Void) async {
        busy = true
        notice = nil
        defer { busy = false }
        do { try await work() } catch { await failed(error) }
    }

    /// A failed action in words. When the answer never came (a timeout, the link dropped) the Core may have done it,
    /// so the cards are read again and the notice says so, never "Nothing was changed". A 404 or 409 means the cards
    /// on screen are old (the tidy moved them): they are read again too.
    func failed(_ error: Error) async {
        if BrainWords.unsure(error) {
            await refresh()
            notice = BrainWords.noAnswer(error)
            return
        }
        if let e = error as? BrainHTTPError, [404, 409].contains(e.status) { await refresh() }
        notice = BrainWords.failure(error)
    }

    /// For a Core older than API minor 73: the ticked rooms are accepted and the others taken back out, one call each,
    /// before the plain commit. Unticked rooms are left out, not refused.
    func acceptTicked() async throws {
        guard let run else { return }
        for c in open where !c.isUnsorted {
            let want = isChecked(c)
            if want != c.isAccepted {
                replace(
                    try await routes.patch(
                        run: run, proposal: c.id, ProposalPatchBody(state: want ? "accepted" : "proposed")))
            }
        }
    }
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
