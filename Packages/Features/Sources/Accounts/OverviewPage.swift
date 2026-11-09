import CoreUI
import SwiftUI

private let cardColumns = [GridItem(.adaptive(minimum: Space.s8 * 11), spacing: Space.s3, alignment: .top)]

/// What is usable, who is tried first, and what needs you.
struct OverviewPage: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let need = model.needLook
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: headline(need.count), detail: summary,
                symbol: need.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                hue: need.isEmpty ? GlassInk.green : GlassInk.orange
            ) { EmptyView() }
            if model.accounts.isEmpty {
                FirstAccount(model: model)
            } else {
                // How it's going, at a glance: four figures that fill in as they appear.
                HStack(spacing: Space.s3) {
                    let total = max(model.accounts.count, 1)
                    let pooled = model.accounts.filter { !model.pools(of: $0).isEmpty }.count
                    StatTile(
                        "Ready", value: model.readyCount, of: total, symbol: "checkmark.seal.fill", hue: GlassInk.green)
                    StatTile(
                        "Need a look", value: need.count, of: total, symbol: "exclamationmark.triangle.fill",
                        hue: need.isEmpty ? GlassInk.slate : GlassInk.orange)
                    StatTile("In a pool", value: pooled, of: total, symbol: "square.grid.2x2.fill", hue: GlassInk.blue, bar: false)
                    if model.chainsAllowed {
                        StatTile(
                            "Agents bound", value: model.chainBindings.count, of: max(model.chainBindings.count, 1),
                            symbol: "link", hue: GlassInk.blue, bar: false)
                    }
                }
                if !need.isEmpty {
                    section("Needs you", "hand.raised.fill", GlassInk.orange)
                    LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                        ForEach(need) { a in AlertRow(model: model, account: a).id("a-\(a.id)") }
                    }
                }
                TriedFirst(model: model)
                HStack {
                    section("Your accounts", "creditcard.fill", GlassInk.blue)
                    Spacer()
                    AccLink(title: "See all", symbol: "arrow.right") { model.page = .accounts }
                }
                LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                    ForEach(
                        Array(model.accounts.filter { $0.phase != .disabled }.prefix(6).enumerated()), id: \.element.id
                    ) {
                        i, a in
                        AccountCard(model: model, account: a, index: i).id(
                            need.contains(a) ? "card-\(a.id)" : "a-\(a.id)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview")
    }

    private func section(_ title: String, _ symbol: String, _ hue: Color) -> some View {
        Label {
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold))
        } icon: {
            Image(systemName: symbol).foregroundStyle(hue)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func headline(_ need: Int) -> String {
        if model.accounts.isEmpty { return "Add your first account" }
        if need == 0 { return "Everything is working" }
        return need == 1 ? "One account needs a look" : "\(need) accounts need a look"
    }

    private var summary: String {
        model.accounts.isEmpty
            ? "Your agents need an account to run on."
            : "\(model.readyCount) of \(model.accounts.count) accounts are ready."
    }
}

/// The empty Core: a way to the first account, with the provider pages it can start from.
struct FirstAccount: View {
    let model: AccountsModel
    var body: some View {
        AccStateCard(
            symbol: "creditcard", title: "No accounts yet",
            text:
                "An account is one provider key that Core keeps for your agents. Pick a provider to open its own page and get a key. This app never takes a key itself."
        ) {
            ForEach(model.providers.filter { ProviderSites.page($0.id) != nil }) { p in
                AppActionTile(title: p.name, symbol: ProviderLook.symbol(p.id), key: "", hue: ProviderLook.hue(p.id)) {
                    AccountDialogs.openConnect(model, provider: p.id)
                }
                .disabled(model.readOnly)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-account")
    }
}

/// One not-ready account as a tinted tile: its provider tile and state, why in two lines, and Open.
private struct AlertRow: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var hovering = false
    var body: some View {
        let on = model.cursor == "a-\(account.id)"
        let verdict = model.verdict(account)
        let hue = verdict.tone == .fail ? GlassInk.red : GlassInk.orange
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                AccTile(provider: account.provider)
                Text(account.label).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                Spacer(minLength: Space.s2)
                VerdictBadge(verdict: model.verdict(account))
            }
            Text(verdict.line(account, limits: model.limits(of: account), budgets: model.budgets, now: model.now()))
                .foregroundStyle(GlassInk.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        }
        .padding(Space.s3)
        .background(hue.opacity(on || hovering ? 0.2 : 0.12), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(on ? 0.8 : 0.4), lineWidth: on ? 1.5 : 1) }
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) {
                model.page = .accounts
                model.detail = account.id
            }
        }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .animation(.smooth(duration: 0.2), value: on)
        .help("Open \(account.label)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A figure with its share as a bar that fills in: Ready 3 of 6.
private struct StatTile: View {
    let title: String
    let value: Int
    let of: Int
    let symbol: String
    let hue: Color
    /// False for a figure that is not a share of the total (nothing to measure, so no bar).
    let bar: Bool
    @State private var shown = false
    init(_ title: String, value: Int, of: Int, symbol: String, hue: Color, bar: Bool = true) {
        self.bar = bar
        self.title = title
        self.value = value
        self.of = of
        self.symbol = symbol
        self.hue = hue
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Image(systemName: symbol).foregroundStyle(hue)
                Text(title).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
            }
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).contentTransition(.numericText())
            if bar {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        coreShape(3).fill(GlassInk.track)
                        coreShape(3).fill(GlassInk.blue)
                            .frame(width: shown ? g.size.width * CGFloat(value) / CGFloat(max(of, 1)) : 0)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .animation(.smooth(duration: 0.8), value: shown)
        .animation(.smooth(duration: 0.4), value: value)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar ? "\(title): \(value) of \(of)" : "\(title): \(value)")
    }
}

/// For each provider, the account its default pool tries first, as chips you can open.
private struct TriedFirst: View {
    let model: AccountsModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label {
                Text("Tried first").font(.system(size: MacTextSize.title, weight: .semibold))
            } icon: {
                Image(systemName: "arrow.right.to.line").foregroundStyle(GlassInk.blue)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 9), spacing: Space.s2, alignment: .leading)],
                spacing: Space.s2
            ) {
                ForEach(model.providers) { p in chip(p) }
            }
        }
    }

    private func chip(_ p: ProviderItem) -> some View {
        let first = model.defaultPool(p.id).flatMap { model.firstReady(in: $0) }
        return HStack(spacing: Space.s2) {
            AccTile(provider: p.id).scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 0) {
                Text(ProviderLook.short(p.id, p.name) + (p.loginMethods.contains("browser_code") ? " · plan" : ""))
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                Text(first?.label ?? (model.defaultPool(p.id) == nil ? "No default pool" : "None ready"))
                    .font(.system(size: MacTextSize.body, weight: .semibold))
                    .foregroundStyle(first == nil ? GlassInk.orangeInk : GlassInk.primary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2).frame(minHeight: 44)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
        .contentShape(coreShape(Radius.control + 2))
        .onTapGesture {
            if let first {
                withAnimation(.smooth(duration: 0.3)) {
                    model.page = .accounts
                    model.detail = first.id
                }
            }
        }
    }
}

/// An account at a glance, as a tile (the terminal-tile look): its provider's tile and colour, its state, why, and when
/// it was last used. Hover lifts it; the keyboard's cursor glows in the provider's colour. Limits and spend are not
/// reported yet, and the card says so rather than showing a number.
struct AccountCard: View {
    let model: AccountsModel
    let account: AccountItem
    var index = 0
    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        let a = account
        let on = model.cursor == "a-\(a.id)"
        let verdict = model.verdict(a)
        let usable = verdict.usable
        // The bar says whether agents can use it: full green only when ready and in a pool, part-filled in its tone
        // otherwise. The same verdict as the badge, the account page and Overview.
        let state =
            usable
            ? GlassInk.green
            : verdict.tone == .fail ? GlassInk.red : verdict.tone == .queue ? GlassInk.slate : GlassInk.orange
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AccTile(provider: a.provider)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.label).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Text(model.providerName(a.provider)).font(.system(size: MacTextSize.meta))
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VerdictBadge(verdict: verdict)
            }
            // Readiness as a bar (see `state`).
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    coreShape(2).fill(GlassInk.track)
                    coreShape(2).fill(state)
                        .frame(
                            width: shown
                                ? g.size.width
                                    * (usable ? 1 : verdict.kind == .turnedOff ? 0.08 : verdict.tone == .fail ? 0.2 : 0.5)
                                : 0
                        )
                }
            }
            .frame(height: 4)
            Text(
                usable
                    ? "Ready for your agents."
                    : verdict.line(a, limits: model.limits(of: a), budgets: model.budgets, now: model.now())
            )
            .foregroundStyle(GlassInk.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if let h = a.health {
                let line = AccountHealthWords.line(h, now: model.now())
                VStack(alignment: .leading, spacing: 2) {
                    Label(line.text, systemImage: line.symbol).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(
                            line.tone == .run
                                ? GlassInk.green
                                : line.tone == .fail
                                    ? GlassInk.redInk : line.tone == .warn ? GlassInk.orangeInk : GlassInk.secondary
                        )
                        .help(line.help)
                    if let n = AccountHealthWords.live(a.live) {
                        Label(n, systemImage: "waveform").foregroundStyle(GlassInk.secondary)
                    }
                }
                .font(.system(size: MacTextSize.meta, weight: .medium))
            }
            HStack {
                Label(AccountsWords.used(a.lastUsedAt, now: model.now()), systemImage: "clock")
                Spacer()
                Text(AccountsWords.capWords(a.cap)).lineLimit(1)
            }
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s3)
        .background(
            on ? GlassInk.blue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(on ? GlassInk.blue.opacity(0.7) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
        }
        .opacity(verdict.kind == .turnedOff ? 0.7 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { openIt() }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.3), value: hovering)
        .animation(.smooth(duration: 0.3), value: on)
        .animation(.smooth(duration: 0.7).delay(0.1 + Double(index) * 0.05), value: shown)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.label), \(model.providerName(a.provider)), \(verdict.label)")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { openIt() }
        .accessibilityHint("Opens the account")
        .accessibilityIdentifier("account-\(a.id)")
    }

    private func openIt() {
        withAnimation(.smooth(duration: 0.35)) {
            model.page = .accounts
            model.detail = account.id
            model.cursor = nil
        }
    }
}
