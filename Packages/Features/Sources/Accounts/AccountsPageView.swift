import CoreUI
import SwiftUI

private let cardColumns = [GridItem(.adaptive(minimum: Space.s8 * 10), spacing: Space.s3, alignment: .top)]

/// Accounts by provider, and one account per page. A key is write-only: nothing here can show one.
struct AccountsPageView: View {
    let model: AccountsModel

    var body: some View {
        if let id = model.detail, let a = model.account(id) {
            AccountDetailView(model: model, account: a)
        } else {
            AccountsList(model: model)
        }
    }
}

private struct AccountsList: View {
    @Bindable var model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Accounts",
                detail: "Your provider keys, by provider. Core keeps each one, and your agents share it."
            ) {
                Button {
                    AccountDialogs.openConnect(model, provider: nil)
                } label: {
                    Label("Connect an account", systemImage: "plus")
                }
                .buttonStyle(.coreProminent).disabled(model.readOnly)
                .help("Open a provider's own page to get a key")
            }
            if model.accounts.isEmpty {
                FirstAccount(model: model)
            } else {
                CoreSegmented(
                    "Show",
                    segments: AccountFilter.allCases.map { f in
                        CoreSegment(f, "\(f.rawValue) \(model.accounts.filter { f.matches($0) }.count)")
                    }, selection: $model.filter
                )
                .frame(maxWidth: Space.s8 * 14, alignment: .leading)
                SummaryBar(model: model)
                if model.providersByUse.isEmpty {
                    Text("Nothing here. All your accounts are fine.").foregroundStyle(palette.text2)
                }
                ForEach(model.providersByUse, id: \.0.id) { p, group in
                    ProviderSection(model: model, provider: p, accounts: group)
                }
                if model.filter == .all, !model.spareProviders.isEmpty {
                    Text("More you can connect").font(.system(size: MacTextSize.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                        ForEach(model.spareProviders) { p in SpareCard(model: model, provider: p) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts-list")
    }
}

/// Ready, needs a look, turned off: a bar in proportion and the same three counts in words.
private struct SummaryBar: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette
    var body: some View {
        let ready = model.readyCount
        let off = model.accounts.filter { $0.phase == .disabled }.count
        let need = model.needLook.count
        let other = model.accounts.count - ready - off - need
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                let total = max(1, model.accounts.count)
                HStack(spacing: Space.s1 / 2) {
                    seg(ready, .run, geo.size.width, total)
                    seg(need, .warn, geo.size.width, total)
                    seg(off + other, .queue, geo.size.width, total)
                }
            }
            .frame(height: Space.s1).accessibilityHidden(true)
            HStack(spacing: Space.s4) {
                Label("\(ready) ready", systemImage: "checkmark.circle")
                if need > 0 {
                    Label("\(need) \(need == 1 ? "needs" : "need") a look", systemImage: "exclamationmark.triangle")
                }
                if off + other > 0 { Label("\(off + other) turned off or other", systemImage: "pause.circle") }
            }
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func seg(_ n: Int, _ tone: Tone, _ width: CGFloat, _ total: Int) -> some View {
        if n > 0 {
            coreShape(Space.s1 / 2).fill(tone == .queue ? palette.track : palette.tone(tone).ink)
                .frame(width: max(Space.s1, width * CGFloat(n) / CGFloat(total) - Space.s1))
        }
    }
}

private struct ProviderSection: View {
    let model: AccountsModel
    let provider: ProviderItem
    let accounts: [AccountItem]
    @State private var open = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                AccTile()
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.name).font(.system(size: MacTextSize.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "\(accounts.count) account\(accounts.count == 1 ? "" : "s")\(provider.builtin ? "" : " · custom")"
                    )
                    .foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s3)
                Button("Connect another") { AccountDialogs.openConnect(model, provider: provider.id) }
                    .buttonStyle(.coreSecondary).disabled(model.readOnly)
                    .help("Open \(provider.name)'s own page to get a key")
            }
            ProviderAbout(provider: provider, open: $open)
            LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                ForEach(accounts) { a in AccountCard(model: model, account: a) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.name)
    }
}

/// What the Core knows about a provider, folded away until asked for.
struct ProviderAbout: View {
    let provider: ProviderItem
    @Binding var open: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            AccPanel(spacing: Space.s2) {
                AccFact(label: "Sign-in") {
                    Text(
                        provider.loginMethods.isEmpty ? "Not available" : provider.loginMethods.joined(separator: ", "))
                }
                AccFact(label: "Delivery") { Text(provider.delivery.joined(separator: ", ")) }
                AccFact(label: "Harness") { Text(provider.harness) }
                AccFact(label: "Variable") { AccChip(text: provider.authVar, mono: true) }
                AccFact(label: "Address") { AccChip(text: provider.baseURL, mono: true) }
                AccFact(label: "Models") {
                    if provider.models.isEmpty {
                        Text("None").foregroundStyle(palette.text2)
                    } else {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            ForEach(provider.models, id: \.id) { m in
                                HStack(spacing: Space.s2) {
                                    AccChip(text: m.id, mono: true)
                                    Text(m.words).foregroundStyle(palette.text2)
                                }
                            }
                            if let at = provider.pricedAt {
                                Text("List prices read \(at)").font(.system(size: MacTextSize.meta)).foregroundStyle(
                                    palette.text2)
                            }
                        }
                    }
                }
            }
            .padding(.top, Space.s2)
        } label: {
            Text("About \(provider.name)").foregroundStyle(palette.primary)
        }
        .accessibilityIdentifier("about-\(provider.id)")
    }
}

private struct SpareCard: View {
    let model: AccountsModel
    let provider: ProviderItem
    @Environment(\.corePalette) private var palette
    var body: some View {
        AccPanel(spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                AccTile()
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text("Add an API key").foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s2)
                Button("Connect") { AccountDialogs.openConnect(model, provider: provider.id) }
                    .buttonStyle(.coreSecondary).disabled(model.readOnly)
            }
        }
    }
}

/// One account: its state, its sign-in (a key that cannot be read back), its limit, its pools.
struct AccountDetailView: View {
    let model: AccountsModel
    let account: AccountItem
    @Environment(\.corePalette) private var palette

    var body: some View {
        let a = account
        let ro = model.readOnly
        VStack(alignment: .leading, spacing: Space.s5) {
            AccLink(title: "All accounts", symbol: "chevron.left") { model.detail = nil }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            HStack(alignment: .top, spacing: Space.s4) {
                AccTile(large: true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(a.label).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(
                        .isHeader)
                    Text(model.providerName(a.provider)).foregroundStyle(palette.text2)
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        PhaseBadge(phase: a.phase)
                        Text(AccountsWords.why(a, now: model.now())).foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s3)
                if a.phase == .disabled {
                    Button {
                        Task { await model.setEnabled(a, true) }
                    } label: {
                        Label("Turn on", systemImage: "play")
                    }
                    .buttonStyle(.coreProminent).disabled(ro || model.busy != nil)
                } else {
                    Button {
                        Task { await model.setEnabled(a, false) }
                    } label: {
                        Label("Turn off", systemImage: "pause")
                    }
                    .buttonStyle(.coreSecondary).disabled(ro || model.busy != nil)
                }
            }
            if let e = model.writeError["account-\(a.id)"] { AccIssue(text: e) }
            NotYetCard(
                title: "How much is left",
                text:
                    "Limits and budget are not available yet. Core does not report them yet.")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 9), spacing: Space.s3, alignment: .top)],
                spacing: Space.s3
            ) {
                AccPanel(spacing: Space.s2) {
                    Text("Sign-in").font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(a.maskedTail.isEmpty ? "Key saved" : "•••• \(a.maskedTail)").font(
                        .system(size: MacTextSize.title, design: .monospaced))
                    Text("Saved safely in Core. It can never be shown again, and this app has no place to type one.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s3) {
                        AccLink(title: "Use a new key…", symbol: ro ? "lock" : nil) {
                            AccountDialogs.openConnect(model, provider: a.provider, replacing: a)
                        }
                        .disabled(ro)
                        AccLink(title: "Remove account…", symbol: ro ? "lock" : nil, danger: true) {
                            AccountDialogs.openDelete(model, a)
                        }
                        .disabled(ro)
                    }
                }
                AccPanel(spacing: Space.s2) {
                    Text("Right now").font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(AccountsWords.capWords(a.cap))
                    Text(AccountsWords.used(a.lastUsedAt, now: model.now())).foregroundStyle(palette.text2)
                    AccLink(title: "Set a limit…", symbol: ro ? "lock" : nil) { AccountDialogs.openCap(model, a) }
                        .disabled(ro)
                }
                AccPanel(spacing: Space.s2) {
                    Text("Used by").font(.system(size: MacTextSize.headline, weight: .semibold))
                    let pools = model.pools(of: a)
                    if pools.isEmpty {
                        Text("Not in a pool yet, so agents cannot use it.").foregroundStyle(palette.text2)
                    }
                    ForEach(pools) { p in
                        AccLink(title: "\(p.name) pool", symbol: "square.grid.2x2") {
                            model.poolSelection = p.id
                            model.page = .pools
                        }
                    }
                }
            }
            NotYetCard(
                title: "Last 12 hours",
                text:
                    "Usage is not available yet. Core does not report tokens, messages or cost yet."
            )
            DisclosureGroup("Technical details") {
                AccPanel(spacing: Space.s2) {
                    AccFact(label: "State") { AccChip(text: a.state, mono: true) }
                    AccFact(label: "Address") { AccChip(text: a.baseURL, mono: true) }
                    AccFact(label: "Added") { Text(a.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                    AccFact(label: "Core id") { AccChip(text: String(a.id), mono: true) }
                }
                .padding(.top, Space.s2)
            }
            .foregroundStyle(palette.primary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-detail")
    }
}
