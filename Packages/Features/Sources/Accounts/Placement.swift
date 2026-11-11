import Foundation

/// Where a new account goes (N35 addition, N22 step "Where does it go?"). Pure rules, no Core calls: the wizard and the
/// Accounts order list both use them, and the tests pin them.
///
/// The Core's model: an account sits in a **pool** (accounts of one provider that share the work); a **chain** is an
/// ordered list of pools (its seats); agents try the seats in order. The words "pool" and "chain" only show where the
/// person asks for them (the wizard's "Where does it go?" and Advanced).
enum PoolPick: Equatable, Sendable {
    /// The provider's default pool. The Core makes it when it is missing.
    case standard
    case existing(Int64)
    case new(String)
}

enum ChainPick: Equatable, Sendable {
    /// The default chain. The Core makes it when it is missing.
    case standard
    case existing(Int64)
    case new(String)
}

/// What `createAccount` takes beyond the label and the key: where it goes and its monthly limit.
struct AccountPlacement: Equatable, Sendable {
    var pool: PoolPick = .standard
    var chain: ChainPick = .standard
    /// The 0-based seat in the chain; nil is the end of it.
    var position: Int?
    /// Millionths of a dollar a month; 0 is no limit (the Core's own meaning). The Core's default is $20 (K2).
    var monthlyLimitMicros: Int64 = Placement.defaultLimitMicros
}

/// One seat of a chain, as the person reads it: the accounts that share it.
struct OrderSeat: Equatable, Identifiable, Sendable {
    let id: String
    var labels: [String]
    var provider: String
    var poolID: Int64?
    var isNew = false
    var isPlan: Bool { provider == "claude-sub" }
    /// `tech`, or `creative + other` when accounts share the seat.
    var title: String { labels.joined(separator: " + ") }
}

enum Placement {
    /// K2: a new account gets a monthly limit of $20 until the person changes it.
    static let defaultLimitMicros: Int64 = 20_000_000

    /// The seats of `chain` in order (none when there is no chain yet).
    static func seats(chain: ChainItem?, pools: [PoolItem], accounts: [AccountItem]) -> [OrderSeat] {
        guard let chain else { return [] }
        return chain.entries.enumerated().map { i, e in
            let pool = pools.first { $0.id == e.pool }
            let labels = (pool?.members ?? []).compactMap { id in accounts.first { $0.id == id }?.label }
            return OrderSeat(
                id: "seat-\(i)-\(e.pool)", labels: labels.isEmpty ? [pool?.name ?? "empty"] : labels,
                provider: e.provider, poolID: e.pool)
        }
    }

    /// The seats with the new account in them. An account that joins a pool already in the chain shares that seat and the
    /// position does not matter. Otherwise it gets a seat at `position` (nil or too big: the end).
    static func inserting(_ new: OrderSeat, into seats: [OrderSeat], at position: Int?) -> [OrderSeat] {
        if let id = new.poolID, let i = seats.firstIndex(where: { $0.poolID == id }) {
            var out = seats
            out[i].labels += new.labels
            return out
        }
        var out = seats
        out.insert(new, at: min(max(position ?? seats.count, 0), seats.count))
        return out
    }

    /// `Agents will try: 1. tech → 2. creative`; nothing to try when the order is empty.
    static func preview(_ seats: [OrderSeat]) -> String {
        guard !seats.isEmpty else { return "Agents will try: nothing yet" }
        return "Agents will try: "
            + seats.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: " → ")
    }

    /// "Used first", "Used second"… for an account's place in the order (nil: not in the order).
    static func usedWords(seat index: Int?) -> String? {
        guard let index else { return nil }
        let words = ["first", "second", "third", "fourth"]
        return "Used \(index < words.count ? words[index] : "\(index + 1)th")"
    }

    /// The word for a seat the wizard offers: "first", "after tech", "last".
    static func positionWords(_ index: Int, in seats: [OrderSeat]) -> String {
        if index <= 0 { return "First" }
        if index >= seats.count { return "Last" }
        return "After \(seats[index - 1].title)"
    }

    /// Moves `id` to `index` (0-based, in the list without it). Unknown ids change nothing.
    static func reordered<T: Equatable>(_ items: [T], moving item: T, to index: Int) -> [T] {
        guard let from = items.firstIndex(of: item) else { return items }
        var out = items
        out.remove(at: from)
        out.insert(item, at: min(max(index, 0), out.count))
        return out
    }

    /// Why the account cannot go there, or nil. The Core refuses a fifth seat and a second Claude plan in one chain.
    static func issue(adding new: OrderSeat, to seats: [OrderSeat]) -> String? {
        if new.poolID != nil, seats.contains(where: { $0.poolID == new.poolID }) { return nil }
        if seats.count >= ChainItem.maxEntries {
            return
                "An order holds up to \(ChainItem.maxEntries) places. Put this account in a pool that is already in it, or choose another order."
        }
        if new.isPlan, seats.contains(where: \.isPlan) {
            return "An order holds only one Claude plan. Choose another order for this one."
        }
        return nil
    }

    /// Dollars the person typed ("20", "$20", "0" or empty for none) as millionths; nil when it is not a number.
    static func limitMicros(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        if t.isEmpty { return 0 }
        guard let d = Double(t.replacingOccurrences(of: ",", with: ".")), d >= 0, d < 1_000_000 else { return nil }
        return Int64((d * 1_000_000).rounded())
    }

    /// `$20`, or "No limit" for 0.
    static func limitWords(_ micros: Int64) -> String {
        micros == 0 ? "No limit" : ModelPriceItem.usd(micros).replacingOccurrences(of: ".00", with: "")
    }
}
