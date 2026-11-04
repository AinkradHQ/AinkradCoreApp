import CoreUI
import SwiftUI

/// The Core pane: a section list on the left, the selected page on the right.
struct AccountsView: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AccountsNav(model: model).frame(width: Space.s8 * 6 + Space.s4)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    AccNotice(notice: model.host.elevationNotice)
                    content
                }
                .font(.system(size: MacTextSize.body))
                .foregroundStyle(palette.text)
                .padding(.horizontal, Space.s5).padding(.bottom, Space.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts-pane")
    }

    @ViewBuilder private var content: some View {
        if !model.isConnected {
            AccStateCard(
                symbol: "wifi.slash", title: "Not connected",
                text: "Accounts, pools and bindings come from your Core. This Mac is not connected to one right now.")
        } else if model.page.notYet {
            NotYetPage(model: model, page: model.page)
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
                    case .pools: PoolsPage(model: model)
                    default: BindingsPage(model: model)
                    }
                }
                .opacity(model.host.pausedReason == nil ? 1 : 0.55)
                .disabled(model.host.pausedReason != nil)
            case .failed(let code, let message):
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Could not load this",
                    text: "The Core answered with an error. \(message) Nothing was changed.", tone: .fail, code: code
                ) { Button("Try again") { Task { await model.reload() } }.buttonStyle(.coreProminent) }
            case .forbidden:
                AccStateCard(
                    symbol: "lock", title: "This device is not allowed to read this",
                    text: "Accounts need the read scope (forbidden_scope). Use a device that holds it.",
                    code: "forbidden_scope")
            }
        }
    }
}

/// The page list: Overview, Accounts (with a count of those needing a look), Spend pages the Core cannot fill yet, Activity.
struct AccountsNav: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(AccountsPage.groups.enumerated()), id: \.offset) { _, group in
                if let heading = group.0 {
                    Text(heading).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                        palette.text2
                    )
                    .padding(.horizontal, Space.s3).padding(.top, Space.s3).padding(.bottom, Space.s1)
                    .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.1) { page in NavButton(model: model, page: page) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Core")
    }
}

private struct NavButton: View {
    let model: AccountsModel
    let page: AccountsPage
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        let on = model.page == page
        let count = page == .accounts ? model.needLook.count : 0
        Button {
            model.page = page
            model.detail = nil
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: page.symbol).frame(width: Space.s5).accessibilityHidden(true)
                Text(page.title)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").font(.system(size: MacTextSize.meta, weight: .semibold))
                        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                        .background(palette.tone(.warn).fill, in: coreShape(Radius.chip))
                        .foregroundStyle(palette.tone(.warn).ink)
                        .accessibilityLabel("\(count) need a look")
                }
            }
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlLg)
            .foregroundStyle(on ? palette.navActiveInk : palette.text)
            .background(on ? palette.navActive : .clear, in: coreShape(Radius.control))
            .overlay { if on { coreShape(Radius.control).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused).focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.control, palette: palette)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("nav-\(page.rawValue)")
    }
}

/// Budgets, Costs and usage, Ledger, Prices and Activity: what the Core has not got yet, said plainly.
struct NotYetPage: View {
    let model: AccountsModel
    let page: AccountsPage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(title: page.title, detail: detail) { EmptyView() }
            AccStateCard(
                symbol: page == .activity ? "text.alignleft" : "hourglass", title: "Not available yet", text: text
            ) {
                if page == .activity {
                    Button("Open Audit") { model.openAudit() }.buttonStyle(.coreProminent)
                }
            }
        }
        .accessibilityIdentifier("not-yet-\(page.rawValue)")
    }

    private var detail: String {
        switch page {
        case .budgets: "What each key may spend per day and month."
        case .costs: "Tokens and cost, by account and by agent."
        case .ledger: "Every charge, one line each."
        case .prices: "List prices behind the cost figures."
        default: "Events on your accounts."
        }
    }

    private var text: String {
        page == .activity
            ? "Core keeps account events in its audit log: Settings, Security, Audit lists every account, pool and binding change."
            : "Core does not report \(page.title.lowercased()) yet, and nothing here is estimated."
    }
}
