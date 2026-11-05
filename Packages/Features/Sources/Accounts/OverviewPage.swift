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
                ForEach(need) { a in AlertRow(model: model, account: a).id("a-\(a.id)") }
                HStack(alignment: .top, spacing: Space.s3) {
                    TriedFirst(model: model)
                    NotYetCard(title: "Spent today")
                }
                HStack {
                    Text("Your accounts").font(.system(size: MacTextSize.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
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

/// One not-ready account as a tinted card: its provider tile, what it is doing, and a way to its page.
private struct AlertRow: View {
    let model: AccountsModel
    let account: AccountItem
    var body: some View {
        let on = model.cursor == "a-\(account.id)"
        let hue = account.phase.tone == .fail ? GlassInk.red : GlassInk.orange
        HStack(spacing: Space.s3) {
            AccTile(provider: account.provider)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(account.label).font(.system(size: MacTextSize.headline, weight: .semibold))
                    PhaseBadge(phase: account.phase)
                }
                Text(AccountsWords.why(account, now: model.now())).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            AccLink(title: "Open", symbol: "arrow.up.forward.app") {
                model.page = .accounts
                model.detail = account.id
            }
            .help("Open \(account.label)")
        }
        .padding(Space.s3)
        .background(hue.opacity(on ? 0.22 : 0.12), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(on ? 0.8 : 0.4), lineWidth: on ? 1.5 : 1) }
        .shadow(color: hue.opacity(on ? 0.4 : 0), radius: 12)
        .animation(.spring(duration: 0.3), value: on)
        .accessibilityElement(children: .contain)
    }
}

/// For each provider: the account its default pool tries first.
private struct TriedFirst: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        AccPanel(spacing: Space.s2) {
            Label("Tried first in each default pool", systemImage: "arrow.right.to.line").font(
                .system(size: MacTextSize.headline, weight: .semibold))
            ForEach(model.providers) { p in
                HStack(spacing: Space.s3) {
                    AccTile(provider: p.id)
                    Text(p.name).foregroundStyle(GlassInk.secondary).frame(width: Space.s8 * 4, alignment: .leading)
                    if let pool = model.defaultPool(p.id), let a = model.firstReady(in: pool) {
                        Button {
                            model.page = .accounts
                            model.detail = a.id
                        } label: {
                            HStack(spacing: Space.s2) {
                                Image(systemName: "1.square.fill").foregroundStyle(ProviderLook.hue(p.id))
                                Text(a.label).font(.system(size: MacTextSize.headline, weight: .semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary)
                            }
                            .padding(.horizontal, Space.s2).frame(minHeight: 32)
                            .background(GlassInk.well, in: coreShape(Radius.control))
                        }
                        .buttonStyle(.plain).help("Open \(a.label)")
                    } else {
                        Label(
                            model.defaultPool(p.id) == nil ? "No default pool" : "No ready account in the default pool",
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(GlassInk.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
        let hue = ProviderLook.hue(a.provider)
        let on = model.cursor == "a-\(a.id)"
        let state =
            a.phase.tone == .run
            ? GlassInk.green
            : a.phase.tone == .fail
                ? GlassInk.red
                : a.phase.tone == .warn
                    ? GlassInk.orange : GlassInk.slate
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AccTile(provider: a.provider).symbolEffect(.bounce, value: hovering)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.label).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    Text(model.providerName(a.provider)).font(.system(size: MacTextSize.meta))
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                PhaseBadge(phase: a.phase)
            }
            // The state as a bar: full and green when ready, part-filled in its tone otherwise.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    coreShape(2).fill(GlassInk.track)
                    coreShape(2).fill(state)
                        .frame(
                            width: shown
                                ? g.size.width * (a.phase == .active ? 1 : a.phase == .disabled ? 0.08 : 0.45) : 0
                        )
                        .shadow(color: state.opacity(0.6), radius: 4)
                }
            }
            .frame(height: 4)
            Text(
                model.usable(a)
                    ? "Ready for your agents."
                    : a.phase == .active
                        ? "Not in a pool yet, so agents can't use it." : AccountsWords.why(a, now: model.now())
            )
            .foregroundStyle(GlassInk.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
            on ? hue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(on ? hue.opacity(0.7) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
        }
        .shadow(color: hue.opacity(on ? 0.45 : hovering ? 0.25 : 0), radius: 16, y: 4)
        .opacity(a.phase == .disabled ? 0.7 : 1)
        .scaleEffect(hovering ? 1.02 : on ? 1.01 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(count: 2) { openIt() }
        .onTapGesture { withAnimation(.spring(duration: 0.25)) { model.cursor = "a-\(a.id)" } }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.25), value: hovering)
        .animation(.spring(duration: 0.3), value: on)
        .animation(.spring(duration: 0.7).delay(0.1 + Double(index) * 0.05), value: shown)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.label), \(model.providerName(a.provider)), \(a.phase.label)")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { openIt() }
        .accessibilityHint("Opens the account")
        .accessibilityIdentifier("account-\(a.id)")
    }

    private func openIt() {
        withAnimation(.spring(duration: 0.35)) {
            model.page = .accounts
            model.detail = account.id
            model.cursor = nil
        }
    }
}
