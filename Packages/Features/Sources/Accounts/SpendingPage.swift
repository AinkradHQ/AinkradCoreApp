import CoreUI
import SwiftUI

/// The Spending tab (N35): this month's spend, the limits with bars, the latest calls, and a line about prices. The four
/// older pages (Limits, Costs and usage, Ledger, Prices) stay one click away under "Advanced".
struct SpendingPage: View {
    @Bindable var model: AccountsModel
    @State private var only: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SpendHeader(
                model: model, title: "Spending",
                detail: "What your accounts spent this month, the limits that stop them, and the latest calls.",
                symbol: "dollarsign.circle.fill")
            summary
            limits
            activity
            prices
        }
        .task {
            await model.reloadBudgets()
            await model.reloadCosts()
        }
        .accessibilityIdentifier("spending")
    }

    // MARK: summary

    private var monthBudgets: [BudgetItem] {
        model.budgets.filter { $0.kind == "account" && $0.period == "month" && $0.usdCap != nil }
    }

    /// From the month budgets of the accounts: what the limits count. Without any, from the calls the ledger shows.
    private var monthSpent: Int64 {
        if let t = MonthSpend.total(model.accounts) { return t.spent }
        return monthBudgets.isEmpty
            ? ledgerThisMonth.compactMap(\.costMicros).reduce(0, +) : monthBudgets.reduce(0) { $0 + $1.usdSpent }
    }

    private var ledgerThisMonth: [CostItem] {
        let start = Calendar.current.dateInterval(of: .month, for: model.now())?.start ?? .distantPast
        return model.costs.filter { $0.at >= start }
    }

    private var summary: some View {
        let cap =
            MonthSpend.total(model.accounts).map { $0.cap ?? 0 }
            ?? monthBudgets.reduce(0) { $0 + ($1.usdCap ?? 0) + $1.raisedUSD }
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent this month").foregroundStyle(GlassInk.secondary)
                    Text(CostWords.usd(monthSpent)).coreFont(size: 34, weight: .bold, design: .rounded)
                        .monospacedDigit().contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if cap > 0 {
                    Text("of \(Placement.limitWords(cap)) in limits").foregroundStyle(GlassInk.secondary)
                }
            }
            DayBars(costs: model.costs, now: model.now())
        }
        .padding(Space.s4)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    // MARK: limits

    private var limits: some View {
        let mine = model.budgets.filter { ["account", "pool"].contains($0.kind) }
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Limits").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: 0)
                AccLink(title: "All limits", symbol: "slider.horizontal.3") {
                    withAnimation(.smooth(duration: 0.3)) { model.page = .budgets }
                }
            }
            if mine.isEmpty {
                Text("No limits yet. Without one, an account can spend without a stop.")
                    .foregroundStyle(GlassInk.secondary)
            }
            ForEach(mine) { b in
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack {
                        Text(model.budgetName(b)).fontWeight(.semibold)
                        Spacer(minLength: Space.s2)
                        Text(
                            b.usdCap.map {
                                "\(CostWords.usd(b.usdSpent)) / \(Placement.limitWords($0 + b.raisedUSD)) \(BudgetWords.period(b.period).lowercased())"
                            } ?? "\(BudgetWords.tokens(b.spent)) tokens"
                        )
                        .monospacedDigit().foregroundStyle(GlassInk.secondary)
                        if b.standing == .stopped || b.standing == .over {
                            AccLink(title: "Raise", symbol: "arrow.up.circle") { AccountDialogs.openRaise(model, b) }
                                .disabled(model.readOnly)
                        }
                    }
                    CoreMeter(b.share, low: b.standing != .fine, label: "\(model.budgetName(b)) limit")
                }
                .contentShape(Rectangle())
                .onTapGesture { if !model.readOnly { AccountDialogs.openBudget(model, editing: b) } }
            }
        }
        .padding(Space.s4)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    // MARK: activity

    @ViewBuilder private var activity: some View {
        let ids = Array(Set(model.costs.compactMap(\.accountID))).sorted()
        let rows = model.costs.filter { only == nil || $0.accountID == only }.prefix(8)
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Activity").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: 0)
                if !ids.isEmpty {
                    Menu(only.map { model.label(ofAccount: $0) } ?? "All accounts") {
                        Button("All accounts") { only = nil }
                        ForEach(ids, id: \.self) { id in Button(model.label(ofAccount: id)) { only = id } }
                    }
                    .fixedSize()
                }
                AccLink(title: "See all", symbol: "list.bullet") {
                    withAnimation(.smooth(duration: 0.3)) { model.page = .ledger }
                }
            }
            if model.costsLoad != .ready {
                Text(model.costsLoad == .loading ? "Reading the calls…" : "Core did not share the calls with this Mac.")
                    .foregroundStyle(GlassInk.secondary)
            } else if rows.isEmpty {
                Text("Each model call an agent makes lands here.").foregroundStyle(GlassInk.secondary)
            }
            ForEach(Array(rows)) { c in
                HStack(spacing: Space.s3) {
                    Text(c.at.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(GlassInk.secondary)
                        .frame(width: Space.s8 * 4, alignment: .leading)
                    Text(model.label(ofAccount: c.accountID)).lineLimit(1)
                        .frame(width: Space.s8 * 3, alignment: .leading)
                    Text(c.model).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(c.costMicros.map { CostWords.usd($0) } ?? "No price").monospacedDigit()
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .background(GlassInk.wellHover, in: coreShape(Radius.control))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.s4)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    // MARK: prices

    private var prices: some View {
        let n = model.providers.reduce(0) { $0 + $1.models.count }
        return HStack(spacing: Space.s3) {
            Image(systemName: "dollarsign.circle").foregroundStyle(GlassInk.blue).accessibilityHidden(true)
            Text(
                n > 0
                    ? "Prices are filled in by the Core release (\(n) models). Nothing to enter."
                    : "Prices come with the Core release. Nothing to enter.")
            Spacer(minLength: 0)
            AccLink(title: "Advanced", symbol: "tag") { withAnimation(.smooth(duration: 0.3)) { model.page = .prices } }
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }
}

/// The last 30 days as bars, from the calls the ledger shows (the newest 100). A bar is a day's cost; today is lit.
private struct DayBars: View {
    let costs: [CostItem]
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = (0..<30).compactMap { cal.date(byAdding: .day, value: -29 + $0, to: today) }
        let sums = days.map { d in
            costs.filter { cal.isDate($0.at, inSameDayAs: d) }.compactMap(\.costMicros).reduce(0, +)
        }
        let top = max(1, sums.max() ?? 1)
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(sums.enumerated()), id: \.offset) { i, v in
                    coreShape(2).fill(i == sums.count - 1 ? GlassInk.blue : GlassInk.blue.opacity(0.45))
                        .frame(height: max(3, 56 * CGFloat(v) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)
            Text("Last 30 days, from the newest 100 calls").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spend by day over the last 30 days")
    }
}
