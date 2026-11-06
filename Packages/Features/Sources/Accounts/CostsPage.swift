import CoreUI
import SwiftUI

/// Costs and usage: three figures for the window (spend, tokens, messages), a note when tokens had no price, then accounts
/// ranked by spend with a bar each, and the same by company. The window is the choice at the top right of the figures.
struct CostsPage: View {
    @Bindable var model: AccountsModel
    @State private var window = SpendWindow.sevenDays

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            SpendHeader(
                model: model, title: "Costs and usage",
                detail: "What your accounts spent and used, from Core's ledger. Nothing here is estimated.",
                symbol: "chart.bar.fill")
            if model.costsLoad == .ready {
                content
            } else {
                SpendState(model: model, state: model.costsLoad, what: "Costs", scope: "admin") {
                    await model.reloadCosts()
                }
            }
        }
        .task { await model.reloadCosts() }
        .accessibilityIdentifier("costs")
    }

    @ViewBuilder private var content: some View {
        let total = model.usage.reduce(UsageWindowItem.zero) { $0 + window.of($1) }
        HStack(spacing: Space.s3) {
            Spacer(minLength: 0)
            CoreSegmented(
                "Window", segments: SpendWindow.allCases.map { CoreSegment($0, $0.rawValue) }, selection: $window
            )
            .fixedSize()
        }
        HStack(spacing: Space.s3) {
            figure("Spent", CostWords.usd(total.costMicros), "dollarsign.square.fill", GlassInk.blue)
            figure("Tokens", CostWords.tokens(total.tokens), "text.word.spacing", GlassInk.blue)
            figure("Messages", total.messages.formatted(), "bubble.left.and.bubble.right.fill", GlassInk.blue)
        }
        if model.unpricedTokens > 0 { unpriced }
        if model.usage.isEmpty {
            AccStateCard(
                symbol: "chart.bar", title: "Nothing spent yet",
                text: "Once agents use an account, its tokens and spend show here.")
        } else {
            accounts(total)
            companies
        }
    }

    private func figure(_ title: String, _ value: String, _ symbol: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                IconTile(symbol, hue: hue, size: 28)
                Text(title).font(.system(size: MacTextSize.body, weight: .semibold)).foregroundStyle(GlassInk.secondary)
            }
            Text(value).font(.system(size: MacTextSize.large, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
            Text(window.rawValue.lowercased()).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
        .animation(Motion.out(Motion.move), value: value)
        .accessibilityElement(children: .combine)
    }

    private var unpriced: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "tag.slash.fill").font(.system(size: MacTextSize.title, weight: .semibold))
                .foregroundStyle(
                    GlassInk.orange)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text("\(CostWords.tokens(model.unpricedTokens)) tokens had no price")
                    .font(.system(size: MacTextSize.headline, weight: .semibold))
                Text("They count as tokens but not as spend. Set a price for their model to count them from now on.")
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            AppActionTile(title: "Open prices", symbol: "tag", key: "", hue: GlassInk.orange) {
                withAnimation(Motion.out(Motion.ui)) { model.page = .prices }
            }
        }
        .padding(Space.s3)
        .background(GlassInk.orange.opacity(0.1))
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
    }

    private func accounts(_ total: UsageWindowItem) -> some View {
        let rows = model.usage.sorted { window.of($0).costMicros > window.of($1).costMicros }
        let top = max(1, rows.first.map { window.of($0).costMicros } ?? 1)
        return GlassSection(
            "By account", sub: "Ranked by spend, \(window.rawValue.lowercased())", symbol: "creditcard.fill",
            hue: GlassInk.blue
        ) {
            VStack(spacing: Space.s2) {
                ForEach(rows, id: \.accountID) { u in
                    AccountSpendRow(model: model, usage: u, window: window, top: top)
                }
            }
        }
    }

    @ViewBuilder private var companies: some View {
        let all = Dictionary(grouping: model.usage.flatMap(\.companies), by: \.company)
            .map { k, v in (k, v.reduce(UsageWindowItem.zero) { $0 + window.of($1) }) }
            .sorted { $0.1.costMicros > $1.1.costMicros }
        if !all.isEmpty {
            let top = max(1, all.first?.1.costMicros ?? 1)
            GlassSection(
                "By company", sub: "Who the spend was for", symbol: "building.2.fill", hue: GlassInk.blue, index: 1
            ) {
                VStack(spacing: Space.s2) {
                    ForEach(all, id: \.0) { c, w in
                        SpendBarRow(
                            title: c, sub: "\(CostWords.tokens(w.tokens)) tokens", value: CostWords.usd(w.costMicros),
                            share: Double(w.costMicros) / Double(top), hue: GlassInk.blue, symbol: "building.2")
                    }
                }
            }
        }
    }
}

/// An account's spend in the window as a bar against the top spender, its tokens and messages, and how close its tightest
/// provider limit is.
private struct AccountSpendRow: View {
    let model: AccountsModel
    let usage: UsageItem
    let window: SpendWindow
    let top: Int64

    var body: some View {
        let w = window.of(usage)
        let a = model.account(usage.accountID)
        let limit =
            usage.hasLimits
            ? usage.limitsExhausted ? " · limit reached" : " · limit \(Int((usage.limitShare * 100).rounded()))% used"
            : ""
        let drops = usage.drops > 0 ? " · \(usage.drops) dropped in the last hour" : ""
        SpendBarRow(
            title: model.label(ofAccount: usage.accountID),
            sub: "\(CostWords.tokens(w.tokens)) tokens · \(w.messages.formatted()) messages\(limit)\(drops)",
            value: CostWords.usd(w.costMicros), share: Double(w.costMicros) / Double(top),
            hue: a.map { ProviderLook.hue($0.provider) } ?? GlassInk.slate, symbol: "creditcard",
            warn: usage.limitsExhausted || usage.limitShare >= 0.8 || usage.drops > 0
        )
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture {
            guard a != nil else { return }
            withAnimation(Motion.out(Motion.move)) {
                model.page = .accounts
                model.detail = usage.accountID
            }
        }
        .help("Open \(model.label(ofAccount: usage.accountID))")
    }
}

/// One ranked row: a tile, the name and a line, the value at the right, and a bar under it in proportion.
struct SpendBarRow: View {
    let title: String
    let sub: String
    let value: String
    let share: Double
    let hue: Color
    let symbol: String
    var warn = false
    @State private var shown = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                IconTile(symbol, hue: hue, size: 30)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(
                        warn ? GlassInk.orange : GlassInk.secondary
                    )
                    .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Text(value).font(
                    .system(size: MacTextSize.title, weight: .semibold, design: .rounded).monospacedDigit()
                )
                .contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    coreShape(3).fill(GlassInk.track.opacity(0.5))
                    coreShape(3)
                        .fill(
                            LinearGradient(colors: [hue.opacity(0.5), hue], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(4, g.size.width * min(1, share) * (shown ? 1 : 0)))
                }
            }
            .frame(height: 6)
        }
        .padding(Space.s3)
        .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .onHover { hovering = $0 }
        .onAppear { withAnimation(Motion.out(Motion.move)) { shown = true } }
        .animation(Motion.out(Motion.move), value: share)
        .accessibilityElement(children: .combine)
    }
}
