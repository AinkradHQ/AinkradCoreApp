import CoreUI
import SwiftUI

/// The Core (Accounts) app, in the shape of every other app (Ahmed, 2026-11-05): its page tiles and action tiles in one
/// header, its own surface inside the pane's glass rim, the page under it, status chips and the keys at the foot. The
/// keyboard drives all of it: ⌘1–⌘5 pages, arrows move the cursor tile, Return opens, and each page's letters act.
struct AccountsView: View {
    let model: AccountsModel
    @FocusState private var paneFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                ForEach(Array(Self.tabs.enumerated()), id: \.offset) { i, t in
                    AppFilterTile(title: t.title, count: count(t.page), on: on(t.page), key: "⌘\(i + 1)") {
                        go(t.page)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .accessibilityIdentifier("nav-\(t.page.rawValue)")
                }
            } actions: {
                AppActionTile(title: "Audit", symbol: "text.alignleft", key: "⌘J", hue: GlassInk.slate) {
                    model.openAudit()
                }
                .keyboardShortcut("j", modifiers: .command)
                primary
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s5) {
                        AccNotice(notice: model.host.elevationNotice)
                        content
                    }
                    .font(.system(size: MacTextSize.body))
                    .foregroundStyle(GlassInk.primary)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .focusable()
                .focused($paneFocus)
                .focusEffectDisabled()
                .onAppear { paneFocus = true }
                .onKeyPress(.downArrow) { AccountsKeys.move(model, 1, proxy) }
                .onKeyPress(.upArrow) { AccountsKeys.move(model, -1, proxy) }
                .onKeyPress(.rightArrow) { AccountsKeys.side(model, 1, proxy) }
                .onKeyPress(.leftArrow) { AccountsKeys.side(model, -1, proxy) }
                .onKeyPress(.return) { AccountsKeys.open(model) }
                .onKeyPress(.escape) { AccountsKeys.back(model) }
                .onKeyPress(.delete) { AccountsKeys.letter(model, "⌫") }
                .onKeyPress(characters: .letters) { AccountsKeys.letter(model, $0.characters.lowercased()) }
            }
            footer
        }
        .background { AccountsSurface() }
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts-pane")
    }

    /// The pages as tiles. Spend holds Budgets, Costs, Ledger and Prices, which the Core does not fill yet.
    static let tabs: [(title: String, page: AccountsPage)] = [
        ("Overview", .overview), ("Accounts", .accounts), ("Pools", .pools), ("Spend", .budgets),
    ]

    private func on(_ page: AccountsPage) -> Bool {
        page == .budgets ? model.page.isSpend : model.page == page
    }

    private func count(_ page: AccountsPage) -> Int {
        switch page {
        case .overview: model.needLook.count
        case .accounts: model.accounts.count
        case .pools: model.pools.count
        case .budgets: model.budgets.filter { $0.standing == .stopped }.count.nonZero ?? -1
        default: -1
        }
    }

    private func go(_ page: AccountsPage) {
        withAnimation(Motion.out(Motion.ui)) {
            model.page = page
            model.detail = nil
            model.cursor = nil
        }
        paneFocus = true
    }

    /// The page's one main action at the far right, ⌘N.
    @ViewBuilder private var primary: some View {
        switch model.page {
        case .pools:
            AppActionTile(title: "Advanced…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue) {
                AccountDialogs.openNewPool(model)
            }
            .keyboardShortcut("n", modifiers: [.command, .option]).disabled(model.readOnly)
            AppActionTile(title: "New pool", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                Task { await model.quickPool() }
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        case .budgets:
            AppActionTile(title: "New budget", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openBudget(model, editing: nil)
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        case .prices:
            AppActionTile(title: "New price", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openPrice(model, editing: nil)
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        case .costs, .ledger:
            AppActionTile(title: "Read now", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.blue) {
                Task { await model.reloadCosts() }
            }
            .keyboardShortcut("r", modifiers: .command)
        default:
            AppActionTile(title: "Connect", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openConnect(model, provider: nil)
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s2) {
            AppStatChip("checkmark.seal.fill", "\(model.readyCount) ready", GlassInk.green)
            if !model.needLook.isEmpty {
                AppStatChip("exclamationmark.triangle.fill", "\(model.needLook.count) need a look", GlassInk.orange)
            }
            AppStatChip("square.grid.2x2.fill", "\(model.pools.count) pools", GlassInk.blue)
            Spacer(minLength: 0)
            Text(AccountsKeys.hint(model)).font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    @ViewBuilder private var content: some View {
        if !model.isConnected {
            AccStateCard(
                symbol: "wifi.slash", title: "Not connected",
                text: "Accounts and pools come from your Core. This Mac is not connected to one right now.")
        } else if model.page.isSpend {
            Group {
                switch model.page {
                case .costs: CostsPage(model: model)
                case .ledger: LedgerPage(model: model)
                case .prices: PricesPage(model: model)
                default: BudgetsPage(model: model)
                }
            }
            .transition(.opacity)
        } else {
            switch model.load {
            case .loading: AccSkeleton()
            case .ready:
                Group {
                    ReadOnlyBanner(model: model)
                    GateBanner(model: model)
                    switch model.page {
                    case .overview: OverviewPage(model: model)
                    case .accounts: AccountsPageView(model: model)
                    default: PoolsPage(model: model)
                    }
                }
                .transition(.opacity)
                .opacity(model.host.pausedReason == nil ? 1 : 0.55)
                .disabled(model.host.pausedReason != nil)
            case .failed(let code, let message):
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Could not load this",
                    text: "Your Core couldn't answer that. Nothing was changed.", tone: .fail
                ) {
                    AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "⌘R", hue: GlassInk.blue) {
                        Task { await model.reload() }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
                .help("\(message) (\(code))")
            case .forbidden:
                AccStateCard(
                    symbol: "lock", title: "This device is not allowed to read this",
                    text: "Accounts need a device that can see everything. Use one that can."
                )
                .help("forbidden_scope")
            }
        }
    }
}

extension Int {
    /// Nil for 0, so a count of nothing shows no badge.
    var nonZero: Int? { self == 0 ? nil : self }
}
