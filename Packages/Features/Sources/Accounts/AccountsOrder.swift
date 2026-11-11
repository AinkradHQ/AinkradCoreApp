import Foundation

/// The order agents try accounts in (N35): the default chain, seen as a list of seats, plus what each account spent this
/// month. The Core's words (pool, chain) stay in Advanced.
extension AccountsModel {
    var defaultChain: ChainItem? { chains.first { $0.isDefault } ?? chains.first }
    var orderSeats: [OrderSeat] { Placement.seats(chain: defaultChain, pools: pools, accounts: accounts) }

    /// The seat an account sits in, 0-based; nil when it is in no seat of the default chain.
    func seatIndex(of a: AccountItem) -> Int? {
        let mine = Set(pools(of: a).map(\.id))
        return orderSeats.firstIndex { $0.poolID.map(mine.contains) ?? false }
    }

    /// Accounts as the Accounts tab lists them: in the order agents try them, then the ones in no seat.
    var accountsInOrder: [AccountItem] {
        accounts.enumerated().sorted {
            (seatIndex(of: $0.element) ?? Int.max, $0.offset) < (seatIndex(of: $1.element) ?? Int.max, $1.offset)
        }
        .map(\.element)
    }

    /// The monthly budget of an account, if it has one.
    func monthBudget(of a: AccountItem) -> BudgetItem? {
        budgets.first { $0.kind == "account" && $0.subject == String(a.id) && $0.period == "month" }
    }

    /// Drag in the order list: the seat at `from` goes to `to` (0-based). One write, behind Touch ID, with Undo.
    func moveSeat(from: Int, to: Int) async {
        guard let c = defaultChain, c.entries.indices.contains(from), from != to else { return }
        var entries = c.entries.map { ChainEntryDraft(pool: $0.pool, model: $0.model) }
        let moved = entries.remove(at: from)
        entries.insert(moved, at: min(max(to, 0), entries.count))
        _ = await replace(c, name: c.name, entries: entries)
    }
}
