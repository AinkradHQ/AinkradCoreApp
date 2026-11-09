import CoreUI
import Foundation

/// The one answer to "can my agents use this account": worked out once from the account's state, its key test, its
/// usage limits and its budgets, and shown the same on cards, the account page, Overview and "Tried first".
struct AccountVerdict: Equatable, Sendable {
    /// Worst first: the first that holds is the verdict.
    enum Kind: Int, Equatable, Sendable {
        case turnedOff, keyRefused, unhealthy, budgetStopped, limitReached, resting, limited, budgetNear, limitNear
        case noPool, ready, other
    }

    /// Where the cause lives, so the verdict can open it.
    enum Cause: Equatable, Sendable { case keyTest, limits, budgets, state, pools }

    let kind: Kind
    let tone: Tone
    let label: String
    let symbol: String
    let cause: Cause?
    let other: String?

    var isReady: Bool { kind == .ready }
    /// Agents can draw on it now.
    var usable: Bool { kind == .ready }
    /// Worth the person's attention (counted as "needs a look").
    var needsLook: Bool {
        switch kind {
        case .turnedOff, .ready, .other, .noPool: false
        default: true
        }
    }

    private init(_ kind: Kind, _ label: String, _ tone: Tone, _ symbol: String, _ cause: Cause?, other: String? = nil) {
        self.kind = kind
        self.label = label
        self.tone = tone
        self.symbol = symbol
        self.cause = cause
        self.other = other
    }

    static func of(
        _ a: AccountItem, limits: [LimitItem] = [], budgets: [BudgetItem] = [], inPool: Bool = true
    ) -> AccountVerdict {
        let mine = budgets.filter { $0.kind == "account" && $0.subject == String(a.id) }
        if a.phase == .disabled { return .init(.turnedOff, "Turned off", .queue, "pause.circle", .state) }
        if a.lastTest?.result == "auth_failed" {
            return .init(.keyRefused, "Key refused", .fail, "key.slash", .keyTest)
        }
        if a.phase == .unhealthy { return .init(.unhealthy, "Needs a look", .fail, "exclamationmark.triangle", .state) }
        if mine.contains(where: { $0.standing == .stopped }) {
            return .init(.budgetStopped, "Budget spent", .fail, "dollarsign.circle", .budgets)
        }
        if limits.contains(where: { $0.standing == .reached }) {
            return .init(.limitReached, "At its limit", .fail, "gauge.with.dots.needle.100percent", .limits)
        }
        if a.phase == .cooling { return .init(.resting, "Resting", .warn, "clock", .state) }
        if a.phase == .limited {
            return .init(.limited, "Limited", .warn, "gauge.with.dots.needle.100percent", .state)
        }
        if mine.contains(where: { $0.standing == .warning || $0.standing == .over }) {
            return .init(.budgetNear, "Budget nearly spent", .warn, "dollarsign.circle", .budgets)
        }
        if limits.contains(where: { $0.standing == .warning }) {
            return .init(.limitNear, "Near its limit", .warn, "gauge.with.dots.needle.67percent", .limits)
        }
        if case .other(let raw) = a.phase { return .init(.other, raw, .queue, "questionmark.circle", nil, other: raw) }
        if !inPool { return .init(.noPool, "Not in a pool", .queue, "square.grid.2x2", .pools) }
        return .init(.ready, "Ready", .run, "checkmark.circle", nil)
    }

    /// One plain sentence for the cause, with the numbers it has.
    func line(_ a: AccountItem, limits: [LimitItem], budgets: [BudgetItem], now: Date) -> String {
        switch kind {
        case .keyRefused: "The provider refused this key. Core checks it again and turns the account off if it is refused again."
        case .budgetStopped, .budgetNear:
            "Its budget is \(kind == .budgetStopped ? "spent, so new work is stopped" : "nearly spent")."
        case .limitReached:
            limits.first { $0.standing == .reached }.map {
                "It reached \(UsageLimitWords.amount($0.cap, unit: $0.unit)) \(UsageLimitWords.window($0.windowSecs).lowercased()). New work waits until the window moves on."
            } ?? "A usage limit is reached."
        case .limitNear: "It is close to a usage limit."
        case .noPool: "Agents only use accounts that are in a pool. Add it to one and it's ready."
        case .ready: "Agents can use it now."
        default: AccountsWords.why(a, now: now)
        }
    }
}

extension AccountsModel {
    func verdict(_ a: AccountItem) -> AccountVerdict {
        AccountVerdict.of(a, limits: limits(of: a), budgets: budgets, inPool: !pools(of: a).isEmpty)
    }
    /// Counted by the same verdict that every card shows.
    var readyAccounts: Int { accounts.filter { verdict($0).isReady }.count }
    var needLookAccounts: [AccountItem] { accounts.filter { verdict($0).needsLook } }
}
