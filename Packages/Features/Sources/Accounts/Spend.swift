import CoreKit
import CoreUI
import SwiftUI

/// A budget and where it stands in the period that contains now (`GET /budgets`). Tokens and millionths of a dollar.
struct BudgetItem: Identifiable, Equatable, Sendable {
    let id: Int64
    /// `account`, `pool`, `agent`, `company`, `department`, `project`, `sprint` or `issue`.
    let kind: String
    let subject: String
    let company: String?
    /// `day`, `week`, `month` or `total`.
    let period: String
    let periodKey: String
    let tokenCap: Int64
    let usdCap: Int64?
    let spent: Int64
    let usdSpent: Int64
    let held: Int64
    let raised: Int64
    let raisedUSD: Int64
    let warnAt: Int64
    let hardStop: Bool
    let exhausted: Bool

    /// Used against the cap plus what was raised, 0...1+ (nil when there is no such cap).
    var tokenShare: Double? { tokenCap > 0 ? Double(spent) / Double(tokenCap + raised) : nil }
    var usdShare: Double? { usdCap.map { Double(usdSpent) / Double(max(1, $0 + raisedUSD)) } }
    var share: Double { max(tokenShare ?? 0, usdShare ?? 0) }

    enum Standing: Equatable { case fine, warning, over, stopped }
    var standing: Standing {
        if exhausted || share >= 1 { return hardStop ? .stopped : .over }
        return share * 100 >= Double(warnAt) ? .warning : .fine
    }
}

/// What `PUT /budgets` takes: create, or change the caps of the budget with that kind, subject and period.
struct BudgetDraft: Equatable, Sendable {
    var kind: String
    var subject: String
    var period: String
    var tokenCap: Int64
    var usdCap: Int64?
    var warnAt: Int64
    var hardStop: Bool
}

enum BudgetWords {
    static let periods: [(id: String, title: String)] = [
        ("day", "Each day"), ("week", "Each week"), ("month", "Each month"), ("total", "In total"),
    ]

    static func period(_ p: String) -> String {
        switch p {
        case "day": "Today"
        case "week": "This week"
        case "month": "This month"
        case "total": "In total"
        default: p
        }
    }

    static func kind(_ k: String) -> String {
        switch k {
        case "account": "Account"
        case "pool": "Pool"
        case "agent": "AI session"
        case "company": "Company"
        case "department": "Department"
        case "project": "Project"
        case "sprint": "Sprint"
        case "issue": "Issue"
        default: k.capitalized
        }
    }

    static func symbol(_ k: String) -> String {
        switch k {
        case "account": "creditcard.fill"
        case "pool": "square.grid.2x2.fill"
        case "agent": "person.fill"
        case "company": "building.2.fill"
        case "department": "person.3.fill"
        case "project": "folder.fill"
        case "sprint": "flag.checkered"
        default: "circle.grid.2x1.fill"
        }
    }

    static func standing(_ b: BudgetItem) -> (title: String, hue: Color, symbol: String) {
        switch b.standing {
        case .fine: ("Within budget", GlassInk.green, "checkmark.circle.fill")
        case .warning: ("Past \(b.warnAt)%", GlassInk.amber, "exclamationmark.triangle.fill")
        case .over: ("Over, warning only", GlassInk.amber, "exclamationmark.octagon.fill")
        case .stopped: ("Stopped", GlassInk.red, "stop.circle.fill")
        }
    }

    static func tokens(_ n: Int64) -> String { AccountsNumbers.amount(n) }
}

extension AccountsModel {
    func reloadBudgets() async {
        guard let service else { return }
        if budgets.isEmpty { spendLoad = .loading }
        do {
            budgets = try await service.budgets()
            spendLoad = .ready
        } catch { spendLoad = state(for: error) }
    }

    /// The budget's subject in words: an account's or pool's name, else the owner's id.
    func budgetName(_ b: BudgetItem) -> String {
        switch b.kind {
        case "account": Int64(b.subject).flatMap(account)?.label ?? "Account \(b.subject)"
        case "pool":
            Int64(b.subject).flatMap(pool).map { "\($0.name) · \(providerName($0.provider))" } ?? "Pool \(b.subject)"
        default: b.subject
        }
    }

    func saveBudget(_ d: BudgetDraft, editing: Bool) async -> Bool {
        let ok = await write(
            "budget", reason: editing ? "Change a budget." : "Create a budget.",
            done: editing ? "Budget saved" : "Budget created", keepsEdit: true
        ) { try await $0.setBudget(d) }
        if ok { await reloadBudgets() }
        return ok
    }

    func deleteBudget(_ b: BudgetItem) async -> Bool {
        let ok = await write(
            "budget-\(b.id)", reason: "Remove the budget for \(budgetName(b)). It runs without a cap after.",
            done: "Budget removed"
        ) { try await $0.deleteBudget(b.id) }
        if ok { await reloadBudgets() }
        return ok
    }

    func raiseBudget(_ b: BudgetItem, tokens: Int64?, usdMicros: Int64?) async -> Bool {
        let ok = await write(
            "raise-\(b.id)",
            reason: "Give \(budgetName(b)) more room for \(BudgetWords.period(b.period).lowercased()).",
            done: "Budget raised", keepsEdit: true
        ) { try await $0.raiseBudget(b.id, periodKey: b.periodKey, tokens: tokens, usdMicros: usdMicros) }
        if ok { await reloadBudgets() }
        return ok
    }
}
