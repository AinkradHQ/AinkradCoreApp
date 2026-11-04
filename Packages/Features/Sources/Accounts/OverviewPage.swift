import CoreUI
import SwiftUI

private let cardColumns = [GridItem(.adaptive(minimum: Space.s8 * 10), spacing: Space.s3, alignment: .top)]

/// What is usable, who is tried first, and what needs you.
struct OverviewPage: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let need = model.needLook
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(title: headline(need.count), detail: summary) {
                Button {
                    AccountDialogs.openConnect(model, provider: nil)
                } label: {
                    Label("Connect an account", systemImage: "plus")
                }
                .buttonStyle(.coreProminent).disabled(model.readOnly).help("Open a provider's own page to get a key")
            }
            if model.accounts.isEmpty {
                FirstAccount(model: model)
            } else {
                ForEach(need) { a in AlertRow(model: model, account: a) }
                HStack(alignment: .top, spacing: Space.s3) {
                    TriedFirst(model: model)
                    NotYetCard(title: "Spent today")
                }
                HStack {
                    Text("Your accounts").font(.system(size: MacTextSize.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    AccLink(title: "See all") { model.page = .accounts }
                }
                LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                    ForEach(model.accounts.filter { $0.phase != .disabled }.prefix(6)) { a in
                        AccountCard(model: model, account: a)
                    }
                }
            }
        }
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
                Button(p.name) { AccountDialogs.openConnect(model, provider: p.id) }.buttonStyle(.coreSecondary)
                    .disabled(model.readOnly)
            }
        }
        .accessibilityIdentifier("first-account")
    }
}

/// One not-ready account: what it is doing, and a way to its page.
private struct AlertRow: View {
    let model: AccountsModel
    let account: AccountItem
    var body: some View {
        AccBanner(
            symbol: account.phase.symbol, title: "\(account.label): \(account.phase.label)",
            text: AccountsWords.why(account, now: model.now()), tone: account.phase.tone
        ) {
            Button("Open") {
                model.page = .accounts
                model.detail = account.id
            }
            .buttonStyle(.coreSecondary).help("Open \(account.label)")
        }
    }
}

/// For each provider: the account its default pool tries first.
private struct TriedFirst: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        AccPanel(spacing: Space.s2) {
            Text("Tried first in each default pool").font(.system(size: MacTextSize.headline, weight: .semibold))
            ForEach(model.providers) { p in
                HStack(spacing: Space.s3) {
                    Text(p.name).foregroundStyle(palette.text2).frame(width: Space.s8 * 4, alignment: .leading)
                    if let pool = model.defaultPool(p.id), let a = model.firstReady(in: pool) {
                        Button {
                            model.page = .accounts
                            model.detail = a.id
                        } label: {
                            HStack(spacing: Space.s2) {
                                AccTile()
                                Text(a.label).font(.system(size: MacTextSize.headline, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .padding(Space.s1).background(palette.uDim, in: coreShape(Radius.control))
                        }
                        .buttonStyle(.plain).help("Open \(a.label)")
                    } else {
                        Label(
                            model.defaultPool(p.id) == nil ? "No default pool" : "No ready account in the default pool",
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(palette.tone(.warn).ink)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// An account at a glance. Limits and spend are not reported yet, and the card says so rather than showing a number.
struct AccountCard: View {
    let model: AccountsModel
    let account: AccountItem
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        let a = account
        Button {
            model.page = .accounts
            model.detail = a.id
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    AccTile()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.label).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(2)
                        Text(model.providerName(a.provider)).foregroundStyle(palette.text2).lineLimit(2)
                    }
                    Spacer(minLength: Space.s2)
                    PhaseBadge(phase: a.phase)
                }
                Text(
                    a.phase == .active
                        ? "Limits and spend are not available yet." : AccountsWords.why(a, now: model.now())
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Space.s8, alignment: .topLeading)
                HStack {
                    Text(AccountsWords.used(a.lastUsedAt, now: model.now()))
                    Spacer()
                    Text(AccountsWords.capWords(a.cap)).lineLimit(1)
                }
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            .padding(Space.s4)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused).focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.cardMac, palette: palette)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.label), \(model.providerName(a.provider)), \(a.phase.label)")
        .accessibilityHint("Opens the account")
        .accessibilityIdentifier("account-\(a.id)")
    }
}
