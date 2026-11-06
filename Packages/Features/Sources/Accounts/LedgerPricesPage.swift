import CoreUI
import SwiftUI

/// The ledger: every model call Core recorded, newest first and grouped by day, each as one line: when, which model and
/// account, tokens, and its cost (or "No price"). A row of account tiles filters it.
struct LedgerPage: View {
    @Bindable var model: AccountsModel
    @State private var only: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SpendHeader(
                model: model, title: "Ledger",
                detail: "Every model call, newest first. A call has no cost when no price covered its model then.",
                symbol: "list.bullet.rectangle.fill")
            if model.costsLoad == .ready {
                content
            } else {
                SpendState(model: model, state: model.costsLoad, what: "The ledger", scope: "admin") {
                    await model.reloadCosts()
                }
            }
        }
        .task { await model.reloadCosts() }
        .accessibilityIdentifier("ledger")
    }

    @ViewBuilder private var content: some View {
        let ids = Array(Set(model.costs.compactMap(\.accountID))).sorted()
        let rows = model.costs.filter { only == nil || $0.accountID == only }
        if model.costs.isEmpty {
            AccStateCard(
                symbol: "list.bullet", title: "No calls yet", text: "Each model call an agent makes lands here.")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    AccPick(
                        title: "All accounts", sub: "\(model.costs.count) calls", symbol: "tray.full",
                        hue: GlassInk.blue, on: only == nil
                    ) { only = nil }
                    .frame(width: 170)
                    ForEach(ids, id: \.self) { id in
                        AccPick(
                            title: model.label(ofAccount: id),
                            sub: "\(model.costs.filter { $0.accountID == id }.count) calls", symbol: "creditcard",
                            hue: model.account(id).map { ProviderLook.hue($0.provider) } ?? GlassInk.slate,
                            on: only == id
                        ) { only = id }
                        .frame(width: 170)
                    }
                }
            }
            let days = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.at) }.sorted { $0.key > $1.key }
            ForEach(days, id: \.key) { day, list in
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: MacTextSize.headline, weight: .semibold))
                        Spacer()
                        let spent = list.compactMap(\.costMicros).reduce(0, +)
                        Text("\(list.count) calls · \(CostWords.usd(spent))").foregroundStyle(GlassInk.secondary)
                    }
                    VStack(spacing: 1) {
                        ForEach(list) { c in LedgerRow(model: model, cost: c) }
                    }
                    .clipShape(coreShape(Radius.cardMac))
                }
            }
            Text(
                model.costs.count >= 100
                    ? "Showing the newest 100 calls. Costs and usage has the totals." : "That's every call Core has."
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
    }
}

private struct LedgerRow: View {
    let model: AccountsModel
    let cost: CostItem
    @State private var hovering = false

    var body: some View {
        let c = cost
        let b = CostWords.basis(c.basis)
        HStack(spacing: Space.s3) {
            Text(c.at.formatted(date: .omitted, time: .shortened)).font(
                .system(size: MacTextSize.body).monospacedDigit()
            )
            .foregroundStyle(GlassInk.secondary).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.model).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced)).lineLimit(1)
                Text(model.label(ofAccount: c.accountID)).font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
            }
            .frame(minWidth: 180, alignment: .leading)
            Spacer(minLength: Space.s2)
            Text(
                "\(CostWords.tokens(c.input)) in · \(CostWords.tokens(c.output)) out\(c.cache > 0 ? " · \(CostWords.tokens(c.cache)) cache" : "")"
            )
            .font(.system(size: MacTextSize.meta).monospacedDigit()).foregroundStyle(GlassInk.secondary)
            Text(b.title).font(.system(size: MacTextSize.meta, weight: .medium)).foregroundStyle(b.hue)
                .frame(width: 150, alignment: .trailing)
            Text(c.costMicros.map { (c.approximate ? "≈ " : "") + CostWords.usd($0) } ?? "—")
                .font(.system(size: MacTextSize.headline, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(c.costMicros == nil ? GlassInk.orange : GlassInk.primary)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3).frame(minHeight: 44)
        .background(hovering ? GlassInk.wellHover : GlassInk.well)
        .onHover { hovering = $0 }
        .help(
            "Session \(c.session) · \(c.provider)\(c.approximate ? " · interrupted, tokens are the last reading" : "")"
        )
        .accessibilityElement(children: .combine)
    }
}

/// Prices: per provider, each model's dollars per million tokens in, out and from cache, its version and when it was read.
/// Set price (⌘N) or a row's Change makes the next version; calls already recorded keep their price.
struct PricesPage: View {
    let model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SpendHeader(
                model: model, title: "Prices",
                detail:
                    "Dollars per million tokens. Each change is a new version; a call is priced with the one in force.",
                symbol: "tag.fill")
            if model.pricesLoad == .ready {
                content
            } else {
                SpendState(model: model, state: model.pricesLoad, what: "Prices", scope: "read") {
                    await model.reloadPrices()
                }
            }
        }
        .task { await model.reloadPrices() }
        .accessibilityIdentifier("prices")
    }

    @ViewBuilder private var content: some View {
        let groups = Dictionary(grouping: model.prices, by: \.provider).sorted { $0.key < $1.key }
        if groups.isEmpty {
            AccStateCard(
                symbol: "tag", title: "No prices yet",
                text: "Without a price, a model's calls count as tokens but not as spend. Set one with New price.")
        }
        ForEach(Array(groups.enumerated()), id: \.element.key) { i, g in
            GlassSection(
                model.providerName(g.key), sub: "\(g.value.count) model\(g.value.count == 1 ? "" : "s")",
                symbol: "tag.fill", hue: ProviderLook.hue(g.key), index: i
            ) {
                VStack(spacing: 1) {
                    HStack(spacing: Space.s3) {
                        Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                        Text("In").frame(width: 90, alignment: .trailing)
                        Text("Out").frame(width: 90, alignment: .trailing)
                        Text("Cache").frame(width: 90, alignment: .trailing)
                        Text("").frame(width: 170)
                    }
                    .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3).padding(.bottom, Space.s1)
                    ForEach(g.value.sorted { $0.model < $1.model }) { p in PriceRow(model: model, price: p) }
                }
            }
        }
    }
}

private struct PriceRow: View {
    let model: AccountsModel
    let price: PriceItem
    @State private var hovering = false

    var body: some View {
        let p = price
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.model).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                Text("Version \(p.version) · read \(p.pricedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach([p.input, p.output, p.cache], id: \.self) { v in
                Text(CostWords.usd(v)).font(.system(size: MacTextSize.headline, weight: .semibold).monospacedDigit())
                    .frame(width: 90, alignment: .trailing)
            }
            AppActionTile(title: "Change", symbol: "slider.horizontal.3", key: "", hue: GlassInk.blue) {
                AccountDialogs.openPrice(model, editing: p)
            }
            .opacity(hovering && !model.readOnly ? 1 : 0).allowsHitTesting(hovering && !model.readOnly)
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3).frame(minHeight: 48)
        .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control + 2))
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .accessibilityElement(children: .combine)
    }
}

/// A model's next price: provider, model id (exact, no alias), and dollars per million tokens in, out and from cache.
struct PriceDialog: View {
    let model: AccountsModel
    let editing: PriceItem?
    let close: () -> Void
    @State private var provider: String
    @State private var modelID: String
    @State private var input: String
    @State private var output: String
    @State private var cache: String
    @State private var busy = false

    init(model: AccountsModel, editing: PriceItem?, close: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.close = close
        func d(_ v: Int64?) -> String { v.map { String(format: "%.2f", Double($0) / 1_000_000) } ?? "" }
        _provider = State(initialValue: editing?.provider ?? model.providers.first?.id ?? "")
        _modelID = State(initialValue: editing?.model ?? "")
        _input = State(initialValue: d(editing?.input))
        _output = State(initialValue: d(editing?.output))
        _cache = State(initialValue: editing == nil ? "0.00" : d(editing?.cache))
    }

    private func micros(_ s: String) -> Int64? {
        let t = s.filter { !", $".contains($0) }
        return Double(t).flatMap { $0 >= 0 && $0 < 100_000 ? Int64(($0 * 1_000_000).rounded()) : nil }
    }
    private var issue: String? {
        if provider.isEmpty { return "Pick a provider." }
        if let m = CostWords.modelIssue(modelID) { return m }
        if micros(input) == nil || micros(output) == nil || micros(cache) == nil {
            return "Prices are dollars per million tokens, like 3 or 0.30."
        }
        return nil
    }

    var body: some View {
        CoreDialogPanel(editing.map { "Price: \($0.model)" } ?? "New price", width: Space.s8 * 19) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if editing == nil {
                    CoreFieldLabel("Provider")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Space.s2)], spacing: Space.s2) {
                        // A subscription isn't billed per token: nothing to price.
                        ForEach(model.providers.filter { !$0.loginMethods.contains("browser_code") }) { p in
                            AccPick(
                                title: p.name, sub: p.builtin ? "Built in" : "Custom", symbol: "tag",
                                hue: ProviderLook.hue(p.id), on: provider == p.id
                            ) { provider = p.id }
                        }
                    }
                    CoreTextField(
                        "Model", placeholder: "claude-sonnet-4-5-20250929", text: $modelID, mono: true, autofocus: true)
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField("In", placeholder: "3.00", text: $input, suffix: "$ / M", autofocus: editing != nil) {
                        go()
                    }
                    CoreTextField("Out", placeholder: "15.00", text: $output, suffix: "$ / M") { go() }
                    CoreTextField("Cache", placeholder: "0.30", text: $cache, suffix: "$ / M") { go() }
                }
                Text("Calls from now on are priced with it. Calls already recorded keep the price they had.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                if let i = issue, !modelID.isEmpty || editing != nil, !input.isEmpty { AccIssue(text: i) }
                if let e = model.writeError["price"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Save price", busy: busy, enabled: issue == nil, cancel: close) { go() }
            }
        }
        .accessibilityIdentifier("price-dialog")
    }

    private func go() {
        guard issue == nil, let i = micros(input), let o = micros(output), let c = micros(cache) else { return }
        busy = true
        let d = PriceDraft(
            provider: provider, model: modelID.trimmingCharacters(in: .whitespaces), input: i, output: o, cache: c,
            pricedAt: Date())
        Task {
            let ok = await model.savePrice(d)
            busy = false
            if ok { close() }
        }
    }
}
