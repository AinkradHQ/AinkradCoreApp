import CoreUI
import SwiftUI

/// The Accounts tab (N35): what needs a look as one banner, a card for each account, and the order agents try them in.
/// The Core's words (pool, chain) stay behind Advanced.
struct AccountsHome: View {
    @Bindable var model: AccountsModel

    var body: some View {
        if let id = model.detail, let a = model.account(id) {
            AccountDetailView(model: model, account: a)
        } else if model.accounts.isEmpty {
            EmptyAccounts(model: model)
        } else {
            VStack(alignment: .leading, spacing: Space.s4) {
                AccountsBanner(model: model)
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(spacing: Space.s3) {
                        ForEach(Array(model.accountsInOrder.enumerated()), id: \.element.id) { i, a in
                            AccountRow(model: model, account: a, index: i).id("a-\(a.id)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if model.chainsAllowed {
                        VStack(spacing: Space.s3) {
                            OrderList(model: model)
                        }
                        .frame(width: Space.s8 * 11)
                    }
                }
                AdvancedRow(model: model)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("accounts-list")
        }
    }
}

/// "1 account needs a look" with its reason and the one thing to do about it. Replaces the old Overview tab.
enum AccountsBannerWords {
    static func headline(need: Int) -> String {
        need == 1 ? "1 account needs a look." : "\(need) accounts need a look."
    }
}

private struct AccountsBanner: View {
    let model: AccountsModel

    var body: some View {
        let need = model.needLook
        if let first = need.first {
            let v = model.verdict(first)
            let stopped = model.budgets.first {
                $0.kind == "account" && $0.subject == String(first.id) && $0.standing != .fine
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "bell.fill").foregroundStyle(GlassInk.orange).accessibilityHidden(true)
                (Text(AccountsBannerWords.headline(need: need.count)).fontWeight(.semibold) + Text(" ")
                    + Text(
                        "\(first.label): \(v.line(first, limits: model.limits(of: first), budgets: model.budgets, now: model.now()))"
                    ))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s3)
                if let stopped, stopped.standing != .warning {
                    AccLink(title: "Raise limit", symbol: "arrow.up.circle") {
                        AccountDialogs.openRaise(model, stopped)
                    }
                    .disabled(model.readOnly)
                }
                AccLink(title: "Open", symbol: "arrow.right") {
                    withAnimation(.smooth(duration: 0.3)) { model.detail = first.id }
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(GlassInk.orange.opacity(0.14), in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.orange.opacity(0.35), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("accounts-banner")
        }
    }
}

/// One account: its mark and name, its state, where it sits in the order, what it spent this month against its limit.
private struct AccountRow: View {
    let model: AccountsModel
    let account: AccountItem
    let index: Int
    @State private var hovering = false
    @State private var shown = false

    var body: some View {
        let a = account
        let v = model.verdict(a)
        let on = model.cursor == "a-\(a.id)"
        let used = Placement.usedWords(seat: model.seatIndex(of: a))
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                AccTile(provider: a.provider)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.label).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(model.providerName(a.provider)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    VerdictBadge(verdict: v)
                    if let used { Text(used).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
                }
            }
            spend
            HStack {
                Label(AccountsWords.used(a.lastUsedAt, now: model.now()), systemImage: "clock")
                Spacer(minLength: 0)
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3)
        .background(
            on ? GlassInk.blue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                on ? GlassInk.blue.opacity(0.7) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
        }
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { openIt() }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.label), \(model.providerName(a.provider)), \(v.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openIt() }
        .accessibilityHint("Opens the account")
        .accessibilityIdentifier("account-\(a.id)")
    }

    /// A plan costs no money per call, so it shows no bar. Other accounts show the month against the limit (K2).
    @ViewBuilder private var spend: some View {
        if account.isPlan {
            Text("Included in your Claude plan").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        } else if let m = MonthSpend.of(account, budget: model.monthBudget(of: account)), let cap = m.cap {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Text("\(ModelPriceItem.usd(m.spent)) of \(Placement.limitWords(cap))")
                        .monospacedDigit().fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Text("this month").foregroundStyle(GlassInk.secondary)
                }
                .coreFont(size: MacTextSize.meta)
                CoreMeter(min(1, m.share ?? 0), low: m.low, label: "Spent this month")
            }
        } else {
            Text("No monthly limit").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
    }

    private func openIt() {
        withAnimation(.smooth(duration: 0.35)) {
            model.detail = account.id
            model.cursor = nil
        }
    }
}

/// "AI sessions try these accounts in this order": the default chain as a drag list. Accounts of one provider that share a
/// place are shown together on it (that is the pool).
private struct OrderList: View {
    let model: AccountsModel
    @State private var dragging: String?

    var body: some View {
        let seats = model.orderSeats
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI sessions try these accounts in this order").coreFont(
                    size: MacTextSize.headline, weight: .semibold)
                Text("Drag to change it. If one is over its limit or fails, the next one takes over.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if seats.isEmpty {
                Text("The order starts when you add an account.").foregroundStyle(GlassInk.secondary)
            }
            ForEach(Array(seats.enumerated()), id: \.element.id) { i, seat in
                seatRow(i, seat)
            }
            Text("Accounts of the same provider share the work. New accounts go to the end of the list.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !seats.isEmpty {
                Text(Placement.preview(seats)).fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassInk.wellHover, in: coreShape(Radius.control))
            }
        }
        .padding(Space.s4)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-order")
    }

    private func seatRow(_ i: Int, _ seat: OrderSeat) -> some View {
        let skipped =
            seat.poolID.flatMap { id in model.pool(id) }.map { p in
                !p.members.isEmpty && model.members(of: p).allSatisfy { !model.verdict($0).usable }
            } ?? false
        return HStack(spacing: Space.s2) {
            Image(systemName: "line.3.horizontal").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text("\(i + 1)").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(GlassInk.blue, in: coreShape(6))
            AccTile(provider: seat.provider)
                .scaleEffect(0.75).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(seat.title).fontWeight(.semibold).lineLimit(1)
                Text(model.providerName(seat.provider)).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if skipped { StateBadge("Skipped", tone: .warn, symbol: "forward.end") }
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .background(
            dragging == seat.id ? GlassInk.blue.opacity(0.18) : GlassInk.wellHover, in: coreShape(Radius.control)
        )
        .opacity(dragging == seat.id ? 0.6 : 1)
        .draggable(seat.id) {
            Text(seat.title).padding(Space.s2).background(GlassInk.well, in: coreShape(Radius.control))
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let from = model.orderSeats.firstIndex(where: { $0.id == id }) else {
                return false
            }
            Task { await model.moveSeat(from: from, to: i) }
            return true
        }
        .contextMenu {
            Button("Use earlier") { Task { await model.moveSeat(from: i, to: i - 1) } }.disabled(i == 0)
            Button("Use later") { Task { await model.moveSeat(from: i, to: i + 1) } }
                .disabled(i == model.orderSeats.count - 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(i + 1). \(seat.title)")
        .accessibilityAction(named: "Use earlier") { Task { await model.moveSeat(from: i, to: i - 1) } }
        .accessibilityAction(named: "Use later") { Task { await model.moveSeat(from: i, to: i + 1) } }
    }
}

/// Everything the Core can do that most people never need: other orders, pools, agents bound to an order, your own
/// providers. Collapsed, so nothing is lost for a power user and nothing is in the way of everyone else.
private struct AdvancedRow: View {
    @Bindable var model: AccountsModel
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { open.toggle() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").frame(width: 14)
                    Text("Advanced").fontWeight(.semibold)
                    Text("More than one order, pool details, your own providers · admins only")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false)
            .accessibilityLabel("Advanced")
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                HStack(spacing: Space.s2) {
                    if model.chainsAllowed {
                        AccLink(title: "Orders (\(model.chains.count))", symbol: "link") {
                            withAnimation(.smooth(duration: 0.3)) { model.page = .chains }
                        }
                        AccLink(title: "Agents and orders", symbol: "person.2") { model.openChainBinding() }
                    }
                    AccLink(title: "Pools (\(model.pools.count))", symbol: "square.grid.2x2") {
                        withAnimation(.smooth(duration: 0.3)) { model.page = .pools }
                    }
                    AccLink(title: "Add a provider…", symbol: "plus") {
                        AccountDialogs.openProvider(model, editing: nil)
                    }
                    .disabled(model.readOnly)
                    Spacer(minLength: 0)
                }
                ForEach(model.providers.filter { !$0.builtin }) { p in
                    HStack(spacing: Space.s2) {
                        AccTile(provider: p.id)
                        Text("\(p.name) · your own provider, not usable by agents yet")
                            .foregroundStyle(GlassInk.secondary)
                        Spacer(minLength: 0)
                        AccLink(title: "Edit", symbol: "slider.horizontal.3") {
                            AccountDialogs.openProvider(model, editing: p)
                        }
                        .disabled(model.readOnly)
                        AccLink(title: "Remove", symbol: "trash", danger: true) {
                            AccountDialogs.openDeleteProvider(model, p)
                        }
                        .disabled(model.readOnly)
                    }
                }
            }
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityIdentifier("accounts-advanced")
    }
}

private struct EmptyAccounts: View {
    let model: AccountsModel
    var body: some View {
        AccStateCard(
            symbol: "key.fill", title: "No accounts yet",
            text:
                "Add your first account to let agents work. It gets a monthly limit of $20 and a place in the order for you."
        ) {
            AppActionTile(title: "Add account", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                AccountDialogs.openConnect(model, provider: nil)
            }
            .disabled(model.readOnly)
        }
        .accessibilityIdentifier("first-account")
    }
}

/// The Connections tab: the same page as the Connections pane, inside Accounts.
struct ConnectionsTab: View {
    let model: ConnectionsModel
    var body: some View {
        Group {
            if model.service == nil {
                AccStateCard(
                    symbol: "link", title: "Not connected to a Core",
                    text: "Connect this Mac to your Core first. Then you sign in to GitHub, Jira and others here.")
            } else {
                switch model.load {
                case .loading: AccSkeleton()
                case .ready: ConnListPage(model: model)
                default:
                    AccStateCard(
                        symbol: "exclamationmark.triangle", title: "Couldn't load connections",
                        text: "Your Core didn't answer. Nothing was changed.", tone: .fail
                    ) {
                        AppActionTile(title: "Try again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue) {
                            Task { await model.reload() }
                        }
                    }
                }
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("connections-tab")
    }
}
