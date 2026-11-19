import CoreUI
import SwiftUI

/// What an account's Limits rows are on a 0.10 Core: its own budgets with a message cap. They are what the usage meter of
/// the AI order row reads, so a row here and the bar there always agree.
enum AccountLimitRules {
    /// The windows a person can pick, shortest first (the Core also has `total`, which stays on the Budgets page).
    static let windows: [(id: String, title: String)] = [
        ("hour5", "Every 5 hours"), ("day", "Every day"), ("week", "Every week"), ("month", "Every month"),
    ]

    /// The message-cap budgets of `account`, shortest window first.
    static func rows(_ budgets: [BudgetItem], account: Int64) -> [BudgetItem] {
        let rank = { (p: String) in windows.firstIndex { $0.id == p } ?? windows.count }
        return budgets.filter { $0.kind == "account" && $0.subject == String(account) && $0.messageCap != nil }
            .sorted { rank($0.period) < rank($1.period) }
    }

    /// The budget a row or a new limit writes: messages only, stopping at the cap.
    static func draft(account: Int64, period: String, messages: Int64, warn: Int64) -> BudgetDraft {
        BudgetDraft(
            kind: "account", subject: String(account), period: period, tokenCap: 0, usdCap: nil, warnAt: warn,
            hardStop: true, messageCap: messages)
    }
}

struct BudgetLimitRows: View {
    let model: AccountsModel
    let account: AccountItem
    @Binding var adding: Bool

    var body: some View {
        let rows = AccountLimitRules.rows(model.budgets, account: account.id)
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(rows) { b in
                BudgetLimitRow(model: model, account: account, existing: b) {}
                    .id("\(account.id)-\(b.period)-\(b.messageCap ?? 0)-\(b.warnAt)")
            }
            if rows.isEmpty && !adding {
                Text("No limit. Add one to cap the messages this account may use in a window.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if adding { BudgetLimitRow(model: model, account: account, existing: nil) { adding = false } }
            if let e = model.writeError["budget"] { AccIssue(text: e) }
        }
    }
}

/// One limit: how often it starts over, the most messages, where the warning starts. Return saves a changed number; a new
/// window saves at once; the cross removes it.
struct BudgetLimitRow: View {
    let model: AccountsModel
    let account: AccountItem
    let existing: BudgetItem?
    let done: () -> Void
    @State private var period: String
    @State private var cap: String
    @State private var warn: String

    init(model: AccountsModel, account: AccountItem, existing: BudgetItem?, done: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.existing = existing
        self.done = done
        _period = State(initialValue: existing?.period ?? "week")
        _cap = State(initialValue: existing?.messageCap.map { AccountsNumbers.grouped($0) } ?? "900")
        _warn = State(initialValue: String(existing?.warnAt ?? 80))
    }

    private var capValue: Int64? { UsageLimitWords.parseCap(cap) }
    private var warnValue: Int64? { Int64(warn).flatMap { (1...100).contains($0) ? $0 : nil } }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { period },
                        set: {
                            period = $0
                            if existing != nil { Task { await commit(moved: true) } }
                        }),
                    options: AccountLimitRules.windows.map { CoreSelectOption($0.id, $0.title) }
                )
                .frame(width: Space.s8 * 5)
                HStack(spacing: Space.s2) {
                    CoreTextField("", placeholder: "900", text: $cap, error: nil) { Task { await commit() } }
                    Text("messages").foregroundStyle(GlassInk.secondary)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: Space.s2) {
                    CoreTextField("", placeholder: "80", text: $warn, error: nil) { Task { await commit() } }
                    Text("%").foregroundStyle(GlassInk.secondary)
                }
                .frame(width: Space.s8 * 3)
                Button {
                    if let existing { Task { _ = await model.deleteBudget(existing) } } else { done() }
                } label: {
                    Image(systemName: "xmark").frame(width: Space.s6, height: Space.s6)
                }
                .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Remove limit")
                .accessibilityLabel("Remove limit")
            }
            if existing == nil {
                AccLink(title: "Save limit", symbol: "checkmark") { Task { await commit() } }
                    .disabled(capValue == nil || warnValue == nil)
            }
        }
    }

    /// A moved window is a new budget (the Core keys one by kind, subject and period): save the new, then drop the old.
    private func commit(moved: Bool = false) async {
        guard let n = capValue, let w = warnValue else { return }
        let ok = await model.saveBudget(
            AccountLimitRules.draft(account: account.id, period: period, messages: n, warn: w), editing: existing != nil)
        guard ok else { return }
        if moved, let existing, existing.period != period { _ = await model.deleteBudget(existing) }
        if existing == nil { done() }
    }
}
