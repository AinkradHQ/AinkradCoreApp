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
                detail: "Your provider keys, by provider. Core keeps each one, and your agents share it.",
                symbol: "creditcard.fill", hue: GlassInk.blue
            ) {
                if !model.accounts.isEmpty {
                    CoreSegmented(
                        "Show",
                        segments: AccountFilter.allCases.map { f in
                            CoreSegment(
                                f, "\(f.rawValue) \(model.accounts.filter { f.matches($0) }.count)", symbol: f.symbol)
                        }, selection: $model.filter
                    )
                    .fixedSize()
                }
            }
            if model.accounts.isEmpty {
                FirstAccount(model: model)
            } else {
                SummaryBar(model: model)
                if model.providersByUse.isEmpty {
                    Label("Nothing here. All your accounts are fine.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(GlassInk.green)
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

/// Ready, needs a look, turned off: a bar in proportion that grows in, counted in the app's foot.
private struct SummaryBar: View {
    let model: AccountsModel
    @State private var shown = false
    var body: some View {
        let ready = model.readyCount
        let off = model.accounts.filter { $0.phase == .disabled }.count
        let need = model.needLook.count
        let other = model.accounts.count - ready - off - need
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                let total = max(1, model.accounts.count)
                HStack(spacing: 3) {
                    seg(ready, GlassInk.green, geo.size.width, total)
                    seg(need, GlassInk.orange, geo.size.width, total)
                    seg(off + other, GlassInk.slate, geo.size.width, total)
                }
            }
            .frame(height: 8).accessibilityHidden(true)
        }
        .animation(.spring(duration: 0.8, bounce: 0.2), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ready) ready, \(need) need a look, \(off + other) turned off or other")
    }

    @ViewBuilder private func seg(_ n: Int, _ c: Color, _ width: CGFloat, _ total: Int) -> some View {
        if n > 0 {
            coreShape(4).fill(c.gradient)
                .frame(width: shown ? max(8, width * CGFloat(n) / CGFloat(total) - 3) : 8)
                .shadow(color: c.opacity(0.5), radius: 4)
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
                AccTile(provider: provider.id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.name).font(.system(size: MacTextSize.title, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "\(accounts.count) account\(accounts.count == 1 ? "" : "s")\(provider.builtin ? "" : " · custom")"
                    )
                    .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                AccLink(title: open ? "Hide details" : "About", symbol: open ? "chevron.up" : "info.circle") {
                    withAnimation(.spring(duration: 0.35)) { open.toggle() }
                }
                AccLink(title: "Connect another", symbol: "plus") {
                    AccountDialogs.openConnect(model, provider: provider.id)
                }
                .disabled(model.readOnly).help("Open \(provider.name)'s own page to get a key")
            }
            if open { ProviderAbout(provider: provider).transition(.opacity.combined(with: .move(edge: .top))) }
            LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { i, a in
                    AccountCard(model: model, account: a, index: i).id("a-\(a.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.name)
    }
}

/// What the Core knows about a provider, shown when asked for (About).
struct ProviderAbout: View {
    let provider: ProviderItem
    @Environment(\.corePalette) private var palette

    var body: some View {
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
                AccTile(provider: provider.id)
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text("Add an API key").foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                AccLink(title: "Connect", symbol: "plus") { AccountDialogs.openConnect(model, provider: provider.id) }
                    .disabled(model.readOnly)
            }
        }
    }
}

/// One account: its state, its sign-in (a key that cannot be read back), its limit, its pools.
struct AccountDetailView: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var tech = false

    var body: some View {
        let a = account
        let ro = model.readOnly
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .center, spacing: Space.s3) {
                BackTile { model.detail = nil }
                AccTile(large: true, provider: a.provider)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s2) {
                        Text(a.label).font(.system(size: MacTextSize.large, weight: .bold)).accessibilityAddTraits(
                            .isHeader)
                        PhaseBadge(phase: a.phase)
                    }
                    Text("\(model.providerName(a.provider)) · \(AccountsWords.why(a, now: model.now()))")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                HStack(spacing: Space.s2) {
                    AppActionTile(title: "Remove", symbol: "trash", key: "⌫", hue: GlassInk.red) {
                        AccountDialogs.openDelete(model, a)
                    }
                    .disabled(ro)
                    AppActionTile(
                        title: "Limit", symbol: "gauge.with.dots.needle.67percent", key: "L", hue: GlassInk.violet
                    ) {
                        AccountDialogs.openCap(model, a)
                    }
                    .disabled(ro)
                    AppActionTile(title: "New key", symbol: "key.fill", key: "K", hue: GlassInk.orange) {
                        AccountDialogs.openConnect(model, provider: a.provider, replacing: a)
                    }
                    .disabled(ro)
                    AppActionTile(
                        title: a.phase == .disabled ? "Turn on" : "Turn off",
                        symbol: a.phase == .disabled ? "play.fill" : "pause.fill", key: "T",
                        hue: a.phase == .disabled ? GlassInk.green : GlassInk.slate, prominent: a.phase == .disabled
                    ) {
                        Task { await model.setEnabled(a, a.phase == .disabled) }
                    }
                    .disabled(ro || model.busy != nil)
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
                    Label("Sign-in", systemImage: "lock.shield.fill").font(
                        .system(size: MacTextSize.headline, weight: .semibold))
                    Text(a.maskedTail.isEmpty ? "Key saved" : "•••• \(a.maskedTail)").font(
                        .system(size: MacTextSize.title, design: .monospaced))
                    Text("Saved safely in Core. It can never be shown again, and this app has no place to type one.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                AccPanel(spacing: Space.s2) {
                    Label("Right now", systemImage: "gauge.with.dots.needle.67percent").font(
                        .system(size: MacTextSize.headline, weight: .semibold))
                    Text(AccountsWords.capWords(a.cap))
                    Label(AccountsWords.used(a.lastUsedAt, now: model.now()), systemImage: "clock")
                        .foregroundStyle(GlassInk.secondary)
                }
                AccPanel(spacing: Space.s2) {
                    Label("Used by", systemImage: "square.grid.2x2.fill").font(
                        .system(size: MacTextSize.headline, weight: .semibold))
                    let pools = model.pools(of: a)
                    if pools.isEmpty {
                        Text("Not in a pool yet, so agents cannot use it.").foregroundStyle(GlassInk.orange)
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
            AccLink(
                title: tech ? "Hide technical details" : "Technical details",
                symbol: tech ? "chevron.up" : "chevron.down"
            ) {
                withAnimation(.spring(duration: 0.35)) { tech.toggle() }
            }
            if tech {
                AccPanel(spacing: Space.s2) {
                    AccFact(label: "State") { AccChip(text: a.state, mono: true) }
                    AccFact(label: "Address") { AccChip(text: a.baseURL, mono: true) }
                    AccFact(label: "Added") { Text(a.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                    AccFact(label: "Core id") { AccChip(text: String(a.id), mono: true) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-detail")
    }
}

/// The way back to a list, as a tile beside the page's icon (the Devices look): it nudges left on hover. Esc does the same.
struct BackTile: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .offset(x: hovering ? -2 : 0)
                .frame(width: 36, height: 56)
                .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(10))
                .overlay { coreShape(10).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                .contentShape(coreShape(10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.4), value: hovering)
        .help("All accounts (esc)")
        .accessibilityLabel("All accounts")
    }
}
