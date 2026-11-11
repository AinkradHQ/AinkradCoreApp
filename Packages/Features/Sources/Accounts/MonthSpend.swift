import Foundation

/// What an account spent this calendar month against its monthly dollar cap, from the account's own fields
/// (`month_spend_usd_micros`, `month_limit_usd_micros`), with the month budget as the fallback while the Core does not send them.
struct MonthSpend: Equatable {
    var spent: Int64
    var cap: Int64?

    /// 0...1+; nil when there is no cap.
    var share: Double? { cap.map { $0 > 0 ? Double(spent) / Double($0) : 0 } }
    /// Within a fifth of the cap or over it.
    var low: Bool { (share ?? 0) >= 0.8 }

    /// nil when neither the account nor a budget says anything.
    static func of(_ a: AccountItem, budget: BudgetItem?) -> MonthSpend? {
        let spent = a.monthSpendUSDMicros ?? budget?.usdSpent
        let cap = a.monthLimitUSDMicros ?? budget?.usdCap.map { $0 + budget!.raisedUSD }
        guard let spent else { return cap.map { MonthSpend(spent: 0, cap: $0) } }
        return MonthSpend(spent: spent, cap: cap)
    }

    /// All accounts together, for the Spending summary: nil when no account reports a month figure.
    static func total(_ accounts: [AccountItem]) -> MonthSpend? {
        let seen = accounts.filter { $0.monthSpendUSDMicros != nil }
        guard !seen.isEmpty else { return nil }
        let caps = accounts.compactMap(\.monthLimitUSDMicros)
        return MonthSpend(
            spent: seen.compactMap(\.monthSpendUSDMicros).reduce(0, +), cap: caps.isEmpty ? nil : caps.reduce(0, +))
    }
}
