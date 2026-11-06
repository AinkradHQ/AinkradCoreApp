import CoreUI
import SwiftUI

/// The Spend pages' shared head: the page's own title, and Budgets · Costs · Ledger · Prices at the top right.
struct SpendHeader: View {
    @Bindable var model: AccountsModel
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        AccHeader(title: title, detail: detail, symbol: symbol, hue: GlassInk.blue) {
            CoreSegmented(
                "Spend",
                segments: [AccountsPage.budgets, .costs, .ledger, .prices].map {
                    CoreSegment($0, $0 == .costs ? "Costs" : $0.title, symbol: $0.symbol)
                },
                selection: Binding(
                    get: { model.page },
                    set: { p in
                        withAnimation(Motion.out(Motion.ui)) {
                            model.page = p
                            model.cursor = nil
                        }
                    })
            )
            .fixedSize()
        }
    }
}

/// Budgets (Ahmed's prototype, `accounts-3.js`): one verdict first (all have room, or which one stopped), then a card per
/// budget with tokens and dollars used against its cap, grouped by what it caps. ↑↓ move, E edit, R raise, ⌫ remove.
struct BudgetsPage: View {
    let model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SpendHeader(
                model: model, title: "Budgets",
                detail:
                    "Caps on what an account, pool, agent or project may spend. A hard stop also ends work already running.",
                symbol: "dollarsign.square.fill")
            switch model.spendLoad {
            case .loading: AccSkeleton()
            case .forbidden:
                // Budgets need the same access as accounts. When accounts load, a refusal here means the Core has no
                // budgets yet (an older Core answers a route it doesn't know with a refusal).
                if model.load == .ready {
                    OlderCoreCard(what: "Budgets")
                } else {
                    AccStateCard(
                        symbol: "lock", title: "This device can't see budgets",
                        text: "Budgets need a device that can see everything. Use one that can."
                    )
                    .help("forbidden_scope")
                }
            case .failed(let code, let message):
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Could not load budgets",
                    text: "Your Core couldn't answer that. Nothing was changed.", tone: .fail
                ) {
                    AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.blue) {
                        Task { await model.reloadBudgets() }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
                .help("\(message) (\(code))")
            case .ready:
                verdict
                let mine = model.budgets.filter { ["account", "pool"].contains($0.kind) }
                let theirs = model.budgets.filter { !["account", "pool"].contains($0.kind) }
                if !mine.isEmpty { section("Accounts and pools", "creditcard.fill", GlassInk.blue, mine, 0) }
                if !theirs.isEmpty {
                    section("Agents, companies and projects", "person.3.fill", GlassInk.blue, theirs, 1)
                }
            }
        }
        .task { await model.reloadBudgets() }
        .accessibilityIdentifier("budgets")
    }

    private var verdict: some View {
        let stopped = model.budgets.filter { $0.standing == .stopped }
        let warn = model.budgets.filter { $0.standing == .warning || $0.standing == .over }
        let none = model.budgets.isEmpty
        let hue =
            !stopped.isEmpty ? GlassInk.red : !warn.isEmpty ? GlassInk.orange : none ? GlassInk.slate : GlassInk.green
        let title =
            if let s = stopped.first {
                stopped.count == 1 ? "\(model.budgetName(s)) is stopped" : "\(stopped.count) budgets are stopped"
            } else if !warn.isEmpty {
                warn.count == 1
                    ? "\(model.budgetName(warn[0])) is nearly spent" : "\(warn.count) budgets are nearly spent"
            } else if none {
                "No budgets yet"
            } else {
                "Every budget has room"
            }
        let line =
            !stopped.isEmpty
            ? "Its cap is spent, so work it covers waits. Raise it for this period, or wait for the next one."
            : !warn.isEmpty
                ? "Past the point where Core warns you. Work goes on until the cap."
                : none
                    ? "Without one, agents can spend without a limit."
                    : "\(model.budgets.count) budget\(model.budgets.count == 1 ? "" : "s"), all under their warning point."
        return HStack(spacing: Space.s4) {
            IconTile(
                !stopped.isEmpty
                    ? "stop.fill"
                    : !warn.isEmpty
                        ? "exclamationmark.triangle.fill"
                        : none ? "dollarsign.square" : "checkmark.seal.fill", hue: hue, size: 56, bounce: stopped.count
            )
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).foregroundStyle(hue)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if let s = stopped.first {
                AppActionTile(title: "Raise", symbol: "arrow.up.square", key: "R", hue: GlassInk.red, prominent: true) {
                    AccountDialogs.openRaise(model, s)
                }
                .disabled(model.readOnly)
            }
        }
        .padding(Space.s4)
        .background(hue.opacity(0.1))
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
        .animation(Motion.out(Motion.move), value: title)
    }

    private func section(_ title: String, _ symbol: String, _ hue: Color, _ list: [BudgetItem], _ i: Int) -> some View {
        GlassSection(
            title, sub: "\(list.count) budget\(list.count == 1 ? "" : "s")", symbol: symbol, hue: hue, index: i
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 14), spacing: Space.s3, alignment: .top)],
                spacing: Space.s3
            ) {
                ForEach(list) { b in
                    BudgetCard(model: model, budget: b, selected: model.cursor == "g-\(b.id)").id("g-\(b.id)")
                }
            }
        }
    }
}

/// One budget: what it caps, its standing, tokens and dollars used as bars, and its actions at the top right (they fade
/// in on hover or with the cursor, in place).
private struct BudgetCard: View {
    let model: AccountsModel
    let budget: BudgetItem
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let b = budget
        let s = BudgetWords.standing(b)
        let shows = (selected || hovering) && !model.readOnly
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile(BudgetWords.symbol(b.kind), hue: s.hue, size: 36)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(model.budgetName(b)).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Text("\(BudgetWords.kind(b.kind)) · \(BudgetWords.period(b.period))")
                        .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                Label(s.title, systemImage: s.symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
                    .foregroundStyle(s.hue).padding(.horizontal, Space.s2).frame(height: MacSize.controlSm)
                    .background(s.hue.opacity(0.14), in: coreShape(Radius.chip))
            }
            if let t = b.tokenShare {
                bar(
                    "Tokens", "\(BudgetWords.tokens(b.spent)) of \(BudgetWords.tokens(b.tokenCap + b.raised))", t, b)
            }
            if let u = b.usdShare, let cap = b.usdCap {
                bar("Dollars", "\(ModelPriceItem.usd(b.usdSpent)) of \(ModelPriceItem.usd(cap + b.raisedUSD))", u, b)
            } else {
                Text("No dollar cap").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            HStack(spacing: Space.s2) {
                Label(
                    b.hardStop ? "Hard stop" : "Warns only", systemImage: b.hardStop ? "hand.raised.fill" : "bell.fill")
                if b.raised > 0 || b.raisedUSD > 0 { Label("Raised this period", systemImage: "arrow.up.square") }
                if b.held > 0 {
                    Label("\(BudgetWords.tokens(b.held)) held by running work", systemImage: "hourglass")
                }
                Spacer(minLength: 0)
                HStack(spacing: Space.s1) {
                    if b.standing == .stopped || b.standing == .over {
                        AppActionTile(
                            title: "Raise", symbol: "arrow.up.square", key: selected ? "R" : "", hue: GlassInk.red
                        ) {
                            AccountDialogs.openRaise(model, b)
                        }
                    }
                    AppActionTile(
                        title: "Edit", symbol: "slider.horizontal.3", key: selected ? "E" : "", hue: GlassInk.blue
                    ) { AccountDialogs.openBudget(model, editing: b) }
                    AppActionTile(title: "Remove", symbol: "trash", key: selected ? "⌫" : "", hue: GlassInk.slate) {
                        AccountDialogs.openDeleteBudget(model, b)
                    }
                }
                .opacity(shows ? 1 : 0).allowsHitTesting(shows)
            }
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, active: selected || hovering)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { withAnimation(Motion.out(Motion.ui)) { model.cursor = "g-\(b.id)" } }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.ui), value: shows)
        .help("\(b.kind) \(b.subject), \(b.period) \(b.periodKey)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.budgetName(b)), \(s.title)")
    }

    private func bar(_ what: String, _ words: String, _ share: Double, _ b: BudgetItem) -> some View {
        let hue = share >= 1 ? GlassInk.red : share * 100 >= Double(b.warnAt) ? GlassInk.orange : GlassInk.green
        return VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text(what).foregroundStyle(GlassInk.secondary)
                Spacer()
                Text(words).font(.system(size: MacTextSize.body, weight: .semibold).monospacedDigit())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    coreShape(3).fill(GlassInk.track.opacity(0.6))
                    coreShape(3)
                        .fill(
                            LinearGradient(colors: [hue.opacity(0.55), hue], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: g.size.width * min(1, share))
                    // The warning point, as a notch on the track.
                    coreShape(1).fill(GlassInk.secondary.opacity(0.7)).frame(width: 2, height: 10)
                        .offset(x: g.size.width * Double(b.warnAt) / 100 - 1)
                }
            }
            .frame(height: 6)
        }
    }
}

/// New budget, or new caps for one: what it caps and over which period (fixed once made), then the caps.
struct BudgetDialog: View {
    let model: AccountsModel
    let editing: BudgetItem?
    let close: () -> Void
    @State private var kind: String
    @State private var subject: String
    @State private var period: String
    @State private var tokens: String
    @State private var dollars: String
    @State private var warn: String
    @State private var hardStop: Bool
    @State private var busy = false

    init(model: AccountsModel, editing: BudgetItem?, close: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.close = close
        _kind = State(initialValue: editing?.kind ?? "account")
        _subject = State(initialValue: editing?.subject ?? "")
        _period = State(initialValue: editing?.period ?? "month")
        _tokens = State(initialValue: editing.map { $0.tokenCap > 0 ? String($0.tokenCap) : "" } ?? "")
        _dollars = State(
            initialValue: editing?.usdCap.map { String(format: "%.2f", Double($0) / 1_000_000) } ?? "")
        _warn = State(initialValue: String(editing?.warnAt ?? 80))
        _hardStop = State(initialValue: editing?.hardStop ?? true)
    }

    private static func clean(_ s: String) -> String { s.filter { !",_ $".contains($0) } }
    private var tokenCap: Int64? {
        let t = Self.clean(tokens)
        return t.isEmpty ? 0 : Int64(t).flatMap { $0 > 0 ? $0 : nil }
    }
    private var usdCap: Int64?? {
        let t = Self.clean(dollars)
        if t.isEmpty { return .some(nil) }
        guard let d = Double(t), d > 0 else { return nil }
        return .some(Int64((d * 1_000_000).rounded()))
    }
    private var warnAt: Int64? {
        Int64(warn.trimmingCharacters(in: .whitespaces)).flatMap { (1...100).contains($0) ? $0 : nil }
    }
    private var subjectOK: Bool {
        let s = subject.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && s.count <= 128
    }
    private var issue: String? {
        guard subjectOK else { return "Pick what this budget caps." }
        guard let t = tokenCap, let u = usdCap else { return "Caps are whole tokens and dollar amounts." }
        guard t > 0 || u != nil else { return "Set a token cap, a dollar cap, or both." }
        guard warnAt != nil else { return "Warn at a percent from 1 to 100." }
        return nil
    }

    var body: some View {
        CoreDialogPanel(editing.map { "Budget: \(model.budgetName($0))" } ?? "New budget", width: Space.s8 * 21) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if editing == nil {
                    CoreFieldLabel("What it caps")
                    CoreSegmented(
                        "What it caps",
                        segments: ["account", "pool", "agent", "company", "project"].map {
                            CoreSegment($0, BudgetWords.kind($0), symbol: BudgetWords.symbol($0))
                        },
                        selection: Binding(
                            get: { kind },
                            set: {
                                kind = $0
                                subject = ""
                            }), fill: true)
                    subjectPicker
                    CoreFieldLabel("Period")
                    CoreSegmented(
                        "Period", segments: BudgetWords.periods.map { CoreSegment($0.id, $0.title) },
                        selection: $period, fill: true)
                } else if let e = editing {
                    Text(
                        "\(BudgetWords.kind(e.kind)) · \(BudgetWords.periods.first { $0.id == e.period }?.title ?? e.period)"
                    )
                    .foregroundStyle(GlassInk.secondary)
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "Token cap", placeholder: "None", text: $tokens, suffix: "tokens", autofocus: editing != nil
                    ) { go() }
                    CoreTextField("Dollar cap", placeholder: "None", text: $dollars, suffix: "$") { go() }
                    CoreTextField("Warn at", placeholder: "80", text: $warn, suffix: "%") { go() }
                        .frame(width: Space.s8 * 4)
                }
                GlassToggleTile(
                    "Hard stop", sub: "At the cap, new work waits and work already running ends. Off, Core only warns.",
                    symbol: "bell", onSymbol: "hand.raised.fill", isOn: $hardStop, fill: true)
                if let i = issue, !(tokens.isEmpty && dollars.isEmpty && subject.isEmpty) { AccIssue(text: i) }
                if let e = model.writeError["budget"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                CoreDialogFooter(
                    confirm: editing == nil ? "Create budget" : "Save", busy: busy, enabled: issue == nil, cancel: close
                ) { go() }
            }
        }
        .accessibilityIdentifier("budget-dialog")
    }

    /// Accounts or pools as tiles; anything else is the owner's id, typed.
    @ViewBuilder private var subjectPicker: some View {
        let grid = [GridItem(.adaptive(minimum: 170), spacing: Space.s2)]
        switch kind {
        case "account":
            LazyVGrid(columns: grid, spacing: Space.s2) {
                ForEach(model.accounts) { a in
                    AccPick(
                        title: a.label, sub: model.providerName(a.provider), symbol: "creditcard",
                        hue: ProviderLook.hue(a.provider), on: subject == String(a.id)
                    ) { subject = String(a.id) }
                }
            }
        case "pool":
            LazyVGrid(columns: grid, spacing: Space.s2) {
                ForEach(model.pools) { p in
                    AccPick(
                        title: p.name, sub: model.providerName(p.provider), symbol: "square.grid.2x2",
                        hue: ProviderLook.hue(p.provider), on: subject == String(p.id)
                    ) { subject = String(p.id) }
                }
            }
        default:
            CoreTextField(
                "\(BudgetWords.kind(kind)) id", placeholder: kind == "agent" ? "atlas" : "its id", text: $subject,
                mono: true)
        }
    }

    private func go() {
        guard issue == nil, let t = tokenCap, let u = usdCap, let w = warnAt else { return }
        busy = true
        let d = BudgetDraft(
            kind: kind, subject: subject.trimmingCharacters(in: .whitespaces), period: period, tokenCap: t, usdCap: u,
            warnAt: w, hardStop: hardStop)
        Task {
            let ok = await model.saveBudget(d, editing: editing != nil)
            busy = false
            if ok { close() }
        }
    }
}

/// More room for this period only: tokens, dollars or both. The next period starts from the cap again.
struct RaiseDialog: View {
    let model: AccountsModel
    let budget: BudgetItem
    let close: () -> Void
    @State private var tokens = ""
    @State private var dollars = ""
    @State private var busy = false

    private var t: Int64?? {
        let s = tokens.filter { !", _".contains($0) }
        return s.isEmpty ? .some(nil) : Int64(s).flatMap { $0 > 0 ? .some($0) : nil }
    }
    private var u: Int64?? {
        let s = dollars.filter { !", _$".contains($0) }
        if s.isEmpty { return .some(nil) }
        return Double(s).flatMap { $0 > 0 ? .some(Int64(($0 * 1_000_000).rounded())) : nil }
    }
    private var ok: Bool {
        guard let t, let u else { return false }
        return t != nil || u != nil
    }

    var body: some View {
        CoreDialogPanel("Raise \(model.budgetName(budget))", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "Adds room for \(BudgetWords.period(budget.period).lowercased()) only, and clears its alert. The next period starts from the cap again."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "More tokens", placeholder: "None", text: $tokens, suffix: "tokens",
                        autofocus: budget.tokenCap > 0
                    ) {
                        go()
                    }
                    .disabled(budget.tokenCap == 0)
                    CoreTextField(
                        "More dollars", placeholder: "None", text: $dollars, suffix: "$",
                        autofocus: budget.tokenCap == 0
                    ) { go() }
                    .disabled(budget.usdCap == nil)
                }
                if let e = model.writeError["raise-\(budget.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                CoreDialogFooter(confirm: "Raise", busy: busy, enabled: ok, cancel: close) { go() }
            }
        }
        .accessibilityIdentifier("budget-raise")
    }

    private func go() {
        guard ok, let tv = t, let uv = u else { return }
        busy = true
        Task {
            let done = await model.raiseBudget(budget, tokens: tv, usdMicros: uv)
            busy = false
            if done { close() }
        }
    }
}

struct DeleteBudgetDialog: View {
    let model: AccountsModel
    let budget: BudgetItem
    let close: () -> Void
    @State private var busy = false

    var body: some View {
        CoreDialogPanel("Remove the budget for \(model.budgetName(budget))?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("It runs without a cap after this. Spend already recorded stays in the ledger.")
                    .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["budget-\(budget.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                CoreDialogFooter(confirm: "Remove budget", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let ok = await model.deleteBudget(budget)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("budget-delete")
    }
}

/// The Core refused a page this device's scopes allow: it is older than the page.
struct OlderCoreCard: View {
    let what: String
    var body: some View {
        AccStateCard(
            symbol: "arrow.down.app", title: "Your Core doesn't have \(what.lowercased()) yet",
            text: "This Mac is newer than your Core. Update Core, then open this page again. Nothing was changed."
        )
        .help("The Core refused a route this device's access allows (forbidden_scope), so the route is missing.")
    }
}
