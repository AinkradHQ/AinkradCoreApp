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
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in
                    AppFilterTile(title: t.title, count: count(t.page), on: on(t.page), key: "⌘\(i + 1)") {
                        go(t.page)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .accessibilityIdentifier("nav-\(t.page.rawValue)")
                }
            } actions: {
                primary
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s5) {
                        AccNotice(notice: model.host.elevationNotice)
                        content
                    }
                    .coreFont(size: MacTextSize.body)
                    .foregroundStyle(GlassInk.primary)
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .focusable()
                .focused($paneFocus)
                .focusEffectDisabled()
                .onAppear { paneFocus = true }
                .retakeFocus(after: model.host.shell, pane: "accounts") { paneFocus = true }
                .onKeyPress(.downArrow) { AccountsKeys.move(model, 1, proxy) }
                .onKeyPress(.upArrow) { AccountsKeys.move(model, -1, proxy) }
                .coreSideKeys { AccountsKeys.side(model, $0, proxy) }
                .onKeyPress(.return) { AccountsKeys.open(model) }
                .onKeyPress(.escape) { AccountsKeys.back(model) }
                .onKeyPress(.delete) { AccountsKeys.letter(model, "⌫") }
                .onKeyPress(characters: .letters) { AccountsKeys.letter(model, $0.characters.lowercased()) }
            }
            footer
        }
        .paneLook(AccountsPrefs.shared.look)
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts-pane")
    }

    /// The pages as tiles. Spend holds Budgets, Costs, Ledger and Prices, which the Core does not fill yet.
    static let tabs: [(title: String, page: AccountsPage)] = [
        ("Accounts", .accounts), ("Spending", .spending), ("Connections", .connections),
    ]

    private var tabs: [(title: String, page: AccountsPage)] { Self.tabs }

    /// Pools and Chains (Advanced) belong to the Accounts tab; the four older spend pages to Spending.
    private func on(_ page: AccountsPage) -> Bool {
        switch page {
        case .accounts: [.accounts, .pools, .chains].contains(model.page)
        case .spending: model.page.isSpend
        default: model.page == page
        }
    }

    private func count(_ page: AccountsPage) -> Int {
        switch page {
        case .accounts: model.accounts.count
        case .spending: model.budgets.filter { $0.standing == .stopped }.count.nonZero ?? -1
        case .connections: model.connections.items.count
        default: -1
        }
    }

    private func go(_ page: AccountsPage) {
        withAnimation(.smooth(duration: 0.3)) {
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
        case .chains:
            AppActionTile(title: "Advanced…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue) {
                AccountDialogs.openChain(model, editing: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option]).disabled(model.readOnly)
            AppActionTile(title: "New chain", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                Task { await model.quickChain() }
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        case .spending, .budgets:
            AppActionTile(title: "New limit", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
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
        case .connections:
            AppActionTile(title: "Connect", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                ConnDialogs.openConnect(model.connections, kind: nil)
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.connections.service == nil)
        default:
            AppActionTile(title: "Advanced…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue) {
                AccountDialogs.openConnect(model, provider: nil, advanced: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .option]).disabled(model.readOnly)
            AppActionTile(title: "Add account", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openConnect(model, provider: nil)
            }
            .keyboardShortcut("n", modifiers: .command).disabled(model.readOnly)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s2) {
            AppStatChip("checkmark.seal.fill", "\(model.readyCount) ready", GlassInk.green)
            if !model.needLook.isEmpty {
                AppStatChip("exclamationmark.triangle.fill", "\(model.needLook.count) need a look", GlassInk.amber)
            }
            Spacer(minLength: 0)
            Text(AccountsKeys.hint(model)).coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    @ViewBuilder private var content: some View {
        if !model.isConnected {
            AccStateCard(
                symbol: "wifi.slash", title: "Not connected",
                text: "Accounts and pools come from your Core. This Mac is not connected to one right now.")
        } else if model.page == .connections {
            ConnectionsTab(model: model.connections).transition(.opacity)
        } else if model.page.isSpend {
            Group {
                switch model.page {
                case .spending: SpendingPage(model: model)
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
                    case .pools: PoolsPage(model: model)
                    case .chains: ChainsPage(model: model)
                    default: AccountsHome(model: model)
                    }
                }
                .transition(.opacity)
                .opacity(model.host.pausedReason == nil ? 1 : 0.55)
                .disabled(model.host.pausedReason != nil)
            case .failed(let code, let message):
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Could not load this",
                    text: "The Core answered with an error. \(message) Nothing was changed.", tone: .fail, code: code
                ) {
                    AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue) {
                        Task { await model.reload() }
                    }
                }
            case .forbidden:
                AccStateCard(
                    symbol: "lock", title: "This device is not allowed to read this",
                    text: "This Mac is not allowed to look at accounts. Use a Mac you allowed to read from the Core.",
                    code: "forbidden_scope")
            }
        }
    }
}

extension Int {
    /// Nil for 0, so a count of nothing shows no badge.
    var nonZero: Int? { self == 0 ? nil : self }
}
