import CoreUI
import SwiftUI

/// What the Limits tab speaks of: a provider (all its accounts together, the mockup's picker) or one account.
enum LimitTarget: Hashable, Sendable {
    case account(Int64)
    case provider(String)

    /// The budget `kind` and `subject` this target writes (`PUT /budgets`).
    var kind: String {
        switch self {
        case .account: "account"
        case .provider: "provider"
        }
    }
    var subject: String {
        switch self {
        case .account(let id): String(id)
        case .provider(let id): id
        }
    }
}

/// What a Limits row is on a 0.10 Core: a budget of the target with a message cap. Accounts' budgets are what the usage
/// meter of the AI order row reads, so a row here and the bar there always agree.
enum AccountLimitRules {
    /// The windows a person can pick, shortest first (the Core also has `total`, which stays on the Budgets page).
    static let windows: [(id: String, title: String)] = [
        ("hour5", "Every 5 hours"), ("day", "Every day"), ("week", "Every week"), ("month", "Every month"),
    ]

    /// The message-cap budgets of `target`, shortest window first.
    static func rows(_ budgets: [BudgetItem], target: LimitTarget) -> [BudgetItem] {
        let rank = { (p: String) in windows.firstIndex { $0.id == p } ?? windows.count }
        return budgets.filter { $0.kind == target.kind && $0.subject == target.subject && $0.messageCap != nil }
            .sorted { rank($0.period) < rank($1.period) }
    }
    static func rows(_ budgets: [BudgetItem], account: Int64) -> [BudgetItem] {
        rows(budgets, target: .account(account))
    }

    /// The budget a row or a new limit writes: messages only, stopping at the cap.
    static func draft(target: LimitTarget, period: String, messages: Int64, warn: Int64) -> BudgetDraft {
        BudgetDraft(
            kind: target.kind, subject: target.subject, period: period, tokenCap: 0, usdCap: nil, warnAt: warn,
            hardStop: true, messageCap: messages)
    }
    static func draft(account: Int64, period: String, messages: Int64, warn: Int64) -> BudgetDraft {
        draft(target: .account(account), period: period, messages: messages, warn: warn)
    }

    /// The providers of the accounts, in the AI order, each once: the Limits picker's choices.
    static func providers(of accounts: [AccountItem]) -> [String] {
        var seen = Set<String>()
        return accounts.map(\.provider).filter { seen.insert($0).inserted }
    }
}

extension AccountsModel {
    /// The providers of the accounts in the AI order.
    var limitProviders: [String] { AccountLimitRules.providers(of: orderIDs.compactMap { account($0) }) }

    /// What the tab shows: the chosen target, else the first provider. An account target stays only while it exists.
    var limitTarget: LimitTarget? {
        if case .account(let id)? = limitsTarget, account(id) != nil { return limitsTarget }
        if case .provider(let p)? = limitsTarget, limitProviders.contains(p) { return limitsTarget }
        return limitProviders.first.map(LimitTarget.provider)
    }

    func limitTargetName(_ t: LimitTarget) -> String {
        switch t {
        case .provider(let p): ProviderCatalog.name(p, fallback: providerName(p))
        case .account(let id): account(id).map { "\(ProviderCatalog.name($0.provider, fallback: providerName($0.provider))) · \($0.label)" }
                ?? "Account \(id)"
        }
    }

    /// The picker: every provider, and the one account when Limits… was opened from its row.
    var limitOptions: [CoreSelectOption<LimitTarget>] {
        var all = limitProviders.map { CoreSelectOption(LimitTarget.provider($0), limitTargetName(.provider($0))) }
        if case .account? = limitTarget, let t = limitTarget { all.insert(CoreSelectOption(t, limitTargetName(t)), at: 0) }
        return all
    }
}

struct BudgetLimitRows: View {
    let model: AccountsModel
    let target: LimitTarget
    @Binding var adding: Bool

    var body: some View {
        let rows = AccountLimitRules.rows(model.budgets, target: target)
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(rows) { b in
                BudgetLimitRow(model: model, target: target, existing: b) {}
                    .id("\(target.kind)-\(target.subject)-\(b.period)-\(b.messageCap ?? 0)-\(b.warnAt)")
            }
            if rows.isEmpty && !adding {
                Text(
                    target.kind == "provider"
                        ? "No limit. Add one to cap the messages all accounts of this provider may use in a window."
                        : "No limit. Add one to cap the messages this account may use in a window.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if adding { BudgetLimitRow(model: model, target: target, existing: nil) { adding = false } }
            if let e = model.writeError["budget"] { AccIssue(text: e) }
        }
    }
}

/// One limit: how often it starts over, the most messages, where the warning starts. Return saves a changed number; a new
/// window saves at once; the cross removes it.
struct BudgetLimitRow: View {
    let model: AccountsModel
    let target: LimitTarget
    let existing: BudgetItem?
    let done: () -> Void
    @State private var period: String
    @State private var cap: String
    @State private var warn: String

    init(model: AccountsModel, target: LimitTarget, existing: BudgetItem?, done: @escaping () -> Void) {
        self.model = model
        self.target = target
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
            AccountLimitRules.draft(target: target, period: period, messages: n, warn: w), editing: existing != nil)
        guard ok else { return }
        if moved, let existing, existing.period != period { _ = await model.deleteBudget(existing) }
        if existing == nil { done() }
    }
}
