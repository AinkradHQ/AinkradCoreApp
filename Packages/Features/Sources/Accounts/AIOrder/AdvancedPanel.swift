import CoreUI
import SwiftUI

/// "Advanced" under the AI order: Limits, Models and prices, Per-agent order. Most people never open it.
struct AdvancedPanel: View {
    @Bindable var model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                CoreSegmented(
                    "Advanced", segments: AdvancedTab.allCases.map { CoreSegment($0, $0.title) },
                    selection: $model.advancedTab)
                Spacer(minLength: Space.s2)
                Text("Most people never need this.").coreFont(size: MacTextSize.meta).foregroundStyle(
                    GlassInk.secondary)
            }
            switch model.advancedTab {
            case .limits: LimitsTab(model: model)
            case .models: ModelsTab(model: model)
            case .agents: AgentsTab(model: model)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-order-advanced")
    }
}

/// The account the Limits and Models tabs speak of.
private func chosen(_ m: AccountsModel) -> AccountItem? {
    (m.limitsAccount ?? m.orderIDs.first).flatMap { m.account($0) }
}

private func accountOptions(_ m: AccountsModel) -> [CoreSelectOption<Int64>] {
    m.orderRows.map { CoreSelectOption($0.id, $0.title) }
}

struct LimitsTab: View {
    @Bindable var model: AccountsModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let a = chosen(model) {
                CoreSelect(
                    "Limits for",
                    selection: Binding(
                        get: { a.id },
                        set: {
                            model.limitsAccount = $0
                            adding = false
                        }),
                    options: accountOptions(model))
                HStack(spacing: Space.s3) {
                    header("Window").frame(width: Space.s8 * 5, alignment: .leading)
                    header("Stop at").frame(maxWidth: .infinity, alignment: .leading)
                    header("Warn me at").frame(width: Space.s8 * 3, alignment: .leading)
                    Color.clear.frame(width: Space.s6, height: 1)
                }
                if model.aiOrderOn {
                    BudgetLimitRows(model: model, account: a, adding: $adding)
                } else {
                    legacyRows(a)
                }
                HStack(spacing: Space.s2) {
                    AccLink(title: "Add a limit", symbol: "plus") { adding = true }
                        .disabled(model.readOnly || adding)
                    Spacer(minLength: Space.s2)
                    AccLink(title: "Budgets, costs and ledger", symbol: "dollarsign.circle") {
                        withAnimation(.smooth(duration: 0.3)) { model.page = .spending }
                    }
                }
            } else {
                Text("Add an account first. Limits belong to an account.").foregroundStyle(GlassInk.secondary)
            }
        }
        .task {
            await model.reloadLimits()
            await model.reloadBudgets()
        }
    }

    /// A Core below 0.10: the usage limits it has always had.
    @ViewBuilder private func legacyRows(_ a: AccountItem) -> some View {
        let rows = model.limits(of: a)
        ForEach(rows) { l in
            LimitEditRow(model: model, account: a, existing: l, done: {}).id(
                "\(a.id)-\(l.id)-\(l.cap)-\(l.warnPercent)")
        }
        if rows.isEmpty && !adding {
            Text("No limit. Add one to cap the messages or tokens this account may use in a window.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        if adding { LimitEditRow(model: model, account: a, existing: nil) { adding = false } }
        if model.limitsLoad == .ready, let e = model.writeError["limit-\(a.id)"] { AccIssue(text: e) }
    }

    private func header(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
    }
}

/// One limit: how often it starts over, the most it may use, where the warning starts. Return saves a changed number; a new
/// window saves at once; Remove asks Core to drop it.
struct LimitEditRow: View {
    let model: AccountsModel
    let account: AccountItem
    let existing: LimitItem?
    let done: () -> Void
    @State private var window: Int64
    @State private var unit: String
    @State private var cap: String
    @State private var warn: String

    init(model: AccountsModel, account: AccountItem, existing: LimitItem?, done: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.existing = existing
        self.done = done
        _window = State(initialValue: existing?.windowSecs ?? 86_400)
        _unit = State(initialValue: existing?.unit ?? "messages")
        _cap = State(initialValue: existing.map { AccountsNumbers.grouped($0.cap) } ?? "100")
        _warn = State(initialValue: String(existing?.warnPercent ?? 80))
    }

    private var capValue: Int64? { UsageLimitWords.parseCap(cap) }
    private var warnValue: Int64? { Int64(warn).flatMap { (1...100).contains($0) ? $0 : nil } }
    private var windows: [CoreSelectOption<Int64>] {
        var all = UsageLimitWords.windows.map { CoreSelectOption($0.secs, $0.title) }
        if !all.contains(where: { $0.value == window }) {
            all.append(CoreSelectOption(window, UsageLimitWords.window(window)))
        }
        return all
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s2) {
            fields
            if existing == nil { save }
        }
    }

    private var fields: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            CoreSelect(
                nil,
                selection: Binding(
                    get: { window },
                    set: {
                        window = $0
                        if existing != nil { Task { await commit(moved: true) } }
                    }), options: windows
            )
            .frame(width: Space.s8 * 5)
            HStack(spacing: Space.s2) {
                CoreTextField("", placeholder: "100", text: $cap, error: nil) { Task { await commit() } }
                if existing == nil {
                    CoreSelect(
                        nil, selection: $unit,
                        options: [CoreSelectOption("messages", "messages"), CoreSelectOption("tokens", "tokens")]
                    )
                    .frame(width: Space.s8 * 4)
                } else {
                    Text(unit).foregroundStyle(GlassInk.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: Space.s2) {
                CoreTextField("", placeholder: "80", text: $warn, error: nil) { Task { await commit() } }
                Text("%").foregroundStyle(GlassInk.secondary)
            }
            .frame(width: Space.s8 * 3)
            Button {
                if let existing { AccountDialogs.openClearLimit(model, account, existing) } else { done() }
            } label: {
                Image(systemName: "xmark").frame(width: Space.s6, height: Space.s6)
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Remove limit")
            .accessibilityLabel("Remove limit")
        }
    }

    private var save: some View {
        AccLink(title: "Save limit", symbol: "checkmark") { Task { await commit() } }
            .disabled(capValue == nil || warnValue == nil)
    }

    /// A moved window is a new limit (the Core keys a limit by unit and window): save the new, then drop the old.
    private func commit(moved: Bool = false) async {
        guard let n = capValue, let w = warnValue else { return }
        let ok = await model.setLimit(account, LimitDraft(unit: unit, windowSecs: window, cap: n, warnPercent: w))
        guard ok else { return }
        if moved, let existing, existing.windowSecs != window { _ = await model.clearLimit(account, existing) }
        if existing == nil { done() }
    }
}
