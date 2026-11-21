import CoreUI
import SwiftUI

/// One card of the account page: a quiet well with its title and what sits at its right.
struct DetailCard<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s2)
                trailing.coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            content
        }
        .padding(.horizontal, Space.s5).padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}

/// A quiet link at the right of a card title, with its key.
struct DetailLinkButton: View {
    let title: String
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command
    let keycap: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .keyboardShortcut(key, modifiers: modifiers).environment(\.coreKeycap, keycap)
    }
}

/// One meter: its name, the big percent, the bar with the time-gone tick, when it resets and the pace.
struct DetailMeter: View {
    let label: String
    let percent: Int
    let value: Double
    let tick: Double?
    let left: Text
    let right: String
    var warn = false
    var unit = "% used"
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(label).coreFont(size: MacTextSize.body, weight: .semibold)
                Spacer(minLength: Space.s2)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(percent)").coreFont(size: 22, weight: .bold).monospacedDigit()
                        .contentTransition(.numericText(value: Double(percent)))
                    Text(unit).coreFont(size: MacTextSize.body, weight: .medium).foregroundStyle(GlassInk.secondary)
                }
            }
            DetailBar(value: value, tick: tick, tint: warn ? palette.warning : nil)
            HStack(spacing: Space.s2) {
                left
                Spacer(minLength: Space.s2)
                Text(right)
            }
            .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A plan's windows as Claude last reported them, each with how much of its time is gone.
struct PlanWindowsCard: View {
    let model: AccountsModel
    let account: AccountItem
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var accent

    var body: some View {
        let state = model.detailState(account)
        let stale = state == .signedOut || state == .off
        let windows = model.windowFacts(account)
        let now = model.now()
        DetailCard(title: "Plan windows") {
            if stale, let at = account.health?.lastSuccessAt {
                Text("Last known \(DetailFacts.clock(at))")
            } else {
                Text("From Claude, after each answer")
            }
        } content: {
            if windows.isEmpty {
                Text("Claude has not said how full the windows are yet. It does after the next answer.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(windows, id: \.name) { w in
                let five = w.name == "five_hour"
                let full = w.used >= 1
                DetailMeter(
                    label: five ? "5-hour window" : "Weekly window", percent: Int((min(1, w.used) * 100).rounded()),
                    value: w.used, tick: w.gone,
                    left: full
                        ? Text("Full · back at \(w.resetsAt.map(DetailFacts.clock) ?? "the reset")").foregroundStyle(
                            palette.warning
                        ).fontWeight(.semibold)
                        : Text("Resets ")
                            + Text(w.resetsAt.map { DetailFacts.reset($0, now: now) } ?? "soon").foregroundStyle(
                                GlassInk.primary
                            ).fontWeight(.semibold),
                    right: stale
                        ? ""
                        : full
                            ? (model.laneRows.first { $0.chip == .inUse }.map { "\($0.title) has the work" } ?? "")
                            : DetailFacts.pace(
                                used: w.used, gone: w.gone, resetsAt: w.resetsAt,
                                length: five ? DetailFacts.fiveHours : DetailFacts.week, now: now, short: five),
                    warn: full
                )
                .opacity(stale ? 0.5 : 1)
            }
            if !windows.isEmpty {
                HStack(spacing: Space.s4) {
                    Label {
                        Text("Used")
                    } icon: {
                        coreShape(1).fill(GlassInk.accent(accent)).frame(width: 10, height: 4)
                    }
                    Label {
                        Text("Time gone in the window")
                    } icon: {
                        coreShape(1).fill(GlassInk.primary.opacity(0.75)).frame(width: 2, height: 10)
                    }
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}

/// An API key's month: spend against its budget with today's tick and the pace, and the split by model.
struct SpendCard: View {
    let model: AccountsModel
    let account: AccountItem

    var body: some View {
        let spend = account.monthSpendUSDMicros ?? 0
        let m = DetailFacts.month(model.now())
        let models = byModel
        let top = models.first?.1 ?? 1
        DetailCard(title: "Spend this month") {
            HStack(spacing: Space.s2) {
                if let l = account.monthLimitUSDMicros {
                    Text(
                        "Budget \(DetailFacts.dollars(l)) · resets \(m.last.addingTimeInterval(1).formatted(.dateTime.day().month(.abbreviated)))"
                    )
                } else {
                    Text("No monthly budget")
                }
                DetailLinkButton(title: "Change…", key: "b", keycap: "⌘B") { model.openBudget(account) }
                    .disabled(model.readOnly)
            }
        } content: {
            if let l = account.monthLimitUSDMicros, l > 0 {
                let p = Double(spend) / Double(l)
                let proj = DetailFacts.projected(spend: spend, gone: m.gone)
                DetailMeter(
                    label: "\(DetailFacts.dollars(spend)) of \(DetailFacts.dollars(l))",
                    percent: Int((min(1, p) * 100).rounded()), value: p, tick: m.gone,
                    left: Text(proj > l ? "Over pace: about " : "On track: about ")
                        + Text(DetailFacts.dollars(proj / 1_000_000 * 1_000_000)).foregroundStyle(GlassInk.primary)
                        .fontWeight(.semibold)
                        + Text(" by \(m.last.formatted(.dateTime.day().month(.abbreviated)))"),
                    right: "The tick is today: \(Int((m.gone * 100).rounded()))% of the month gone", warn: p >= 1,
                    unit: "%")
            } else {
                Text(DetailFacts.dollars(spend)).coreFont(size: 22, weight: .bold).monospacedDigit()
            }
            if !models.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s2) {
                    ForEach(models, id: \.0) { name, micros in
                        GridRow {
                            Text(name).lineLimit(1).frame(width: 92, alignment: .leading)
                            DetailBar(value: Double(micros) / Double(max(top, 1)), height: 6)
                            Text(AccountsNumbers.usd(micros)).monospacedDigit().frame(width: 64, alignment: .trailing)
                        }
                    }
                }
                .coreFont(size: MacTextSize.meta + 1)
            }
        }
    }

    /// This month's dollars by model, most first, from the account's priced cost events.
    private var byModel: [(String, Int64)] {
        let start = Calendar.current.dateInterval(of: .month, for: model.now())?.start ?? .distantPast
        var sum: [String: Int64] = [:]
        for e in model.costs where e.accountID == account.id && e.at >= start {
            if let c = e.costMicros { sum[ModelNames.short(e.model), default: 0] += c }
        }
        return sum.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value) }
    }
}

/// The last 7 days as columns: tokens for a plan, dollars for a key. Today is the full accent and carries its value;
/// hovering a column shows its day and value.
struct WeekChart: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var hover: Int?
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.detailReduce) private var reduce
    @Environment(\.detailShown) private var shown

    var body: some View {
        let data = model.detailData[account.id]
        let days = data?.days ?? []
        let dollars = !account.isPlan
        let values = days.map { dollars ? Double($0.usdMicros) : Double($0.tokens) }
        let top = max(values.max() ?? 0, 1)
        let stale = [.signedOut, .off].contains(model.detailState(account))
        DetailCard(title: "Last 7 days") {
            HStack(spacing: Space.s2) {
                if !days.isEmpty {
                    Text(total(values, dollars)).fontWeight(.semibold).foregroundStyle(GlassInk.primary)
                        .monospacedDigit()
                }
                DetailLinkButton(title: "Open Costs", key: "y", keycap: "⌘Y") { model.go(.costs) }
            }
        } content: {
            if days.isEmpty {
                Text(data == nil ? "Reading the last 7 days…" : "The Core keeps no daily totals this device may read.")
                    .foregroundStyle(GlassInk.secondary)
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: Space.s3) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        column(i, d, values[i] / top, dollars: dollars, today: i == days.count - 1)
                    }
                }
                .frame(minHeight: 150)
                .opacity(stale ? 0.5 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Use per day, last 7 days")
                .accessibilityValue(
                    days.enumerated().map {
                        "\(day(days[$0.offset].day, today: false)) \(label(values[$0.offset], dollars))"
                    }
                    .joined(separator: ", "))
                if data?.daysOfProvider == true {
                    Text(
                        "Every \(model.kindName(account)) account together. This Core can't split the days by account yet."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }

    private func column(_ i: Int, _ d: AccountDayItem, _ h: Double, dollars: Bool, today: Bool) -> some View {
        let v = dollars ? Double(d.usdMicros) : Double(d.tokens)
        return VStack(spacing: Space.s2) {
            Text(hover == i ? label(v, dollars) : today ? short(v, dollars) : " ")
                .coreFont(size: MacTextSize.meta + 1, weight: .semibold).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(hover == i ? GlassInk.secondary : GlassInk.primary)
            GeometryReader { g in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    coreShape(4)
                        .fill(
                            hover == i
                                ? GlassInk.accentInk(accent)
                                : today ? GlassInk.accent(accent) : GlassInk.accent(accent).opacity(0.5)
                        )
                        .frame(height: max(3, g.size.height * (shown || reduce ? h : 0.04)))
                        .animation(reduce ? nil : Motion.out(0.5).delay(Double(i) * 0.035), value: shown)
                }
            }
            Text(day(d.day, today: today)).coreFont(size: MacTextSize.meta, weight: today ? .semibold : .regular)
                .foregroundStyle(today ? GlassInk.primary : GlassInk.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hover = $0 ? i : (hover == i ? nil : hover) }
    }

    private func day(_ d: Date, today: Bool) -> String {
        today ? "Today" : d.formatted(Date.FormatStyle(timeZone: AccountDetailWire.utc.timeZone).weekday(.abbreviated))
    }
    private func short(_ v: Double, _ dollars: Bool) -> String {
        dollars ? AccountsNumbers.usd(Int64(v)) : DetailFacts.compact(Int64(v))
    }
    private func label(_ v: Double, _ dollars: Bool) -> String {
        dollars ? AccountsNumbers.usd(Int64(v)) : "\(DetailFacts.compact(Int64(v))) tokens"
    }
    private func total(_ values: [Double], _ dollars: Bool) -> String { label(values.reduce(0, +), dollars) }
}

/// "claude-opus-4-1" reads "Opus"; anything else stays as the Core names it.
enum ModelNames {
    static func short(_ id: String) -> String {
        for (key, name) in [("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")]
        where id.lowercased().contains(key) {
            return name
        }
        return id
    }
}

extension AccountsModel {
    /// Leaves the account page for one of the Accounts pages.
    func go(_ page: AccountsPage) {
        withAnimation(.smooth(duration: 0.3)) {
            self.page = page
            detail = nil
        }
    }

    /// The account's message limits and monthly budget, in Advanced (0.10); the Budgets page on an older Core.
    func openBudget(_ a: AccountItem) {
        guard aiOrderOn else { return go(.budgets) }
        limitsAccount = a.id
        limitsTarget = .account(a.id)
        advancedTab = .limits
        advancedOpen = true
        go(.accounts)
    }
}
