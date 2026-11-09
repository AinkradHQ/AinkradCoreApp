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
                                f,
                                "\(f.rawValue) \(model.accounts.filter { f.matches($0, verdict: model.verdict($0)) }.count)",
                                symbol: f.symbol)
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
                if model.filter == .all {
                    Text("More you can connect").coreFont(size: MacTextSize.title, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: cardColumns, spacing: Space.s3) {
                        ForEach(model.spareProviders) { p in SpareCard(model: model, provider: p) }
                        AddProviderCard(model: model)
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
    @Environment(\.corePalette) private var palette
    var body: some View {
        let ready = model.readyCount
        let off = model.accounts.filter { model.verdict($0).kind == .turnedOff }.count
        let need = model.needLook.count
        let other = model.accounts.count - ready - off - need
        VStack(alignment: .leading, spacing: Space.s2) {
            // The counts sit directly above the bar they describe, each with its symbol: never colour alone.
            HStack(spacing: Space.s4) {
                legend("checkmark.circle", "\(ready) ready", .run)
                legend("exclamationmark.triangle", "\(need) need a look", .warn)
                legend("pause.circle", "\(off + other) turned off or other", .queue)
                Spacer(minLength: 0)
            }
            .coreFont(size: MacTextSize.meta, weight: .medium)
            GeometryReader { geo in
                let total = max(1, model.accounts.count)
                HStack(spacing: 3) {
                    seg(ready, palette.tone(.run).fill, geo.size.width, total)
                    seg(need, palette.tone(.warn).fill, geo.size.width, total)
                    seg(off + other, GlassInk.slate, geo.size.width, total)
                }
            }
            .frame(height: 8).accessibilityHidden(true)
        }
        .animation(.smooth(duration: 0.8), value: shown)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ready) ready, \(need) need a look, \(off + other) turned off or other")
    }

    private func legend(_ symbol: String, _ text: String, _ tone: Tone) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(palette.tone(tone).ink)
    }

    @ViewBuilder private func seg(_ n: Int, _ c: Color, _ width: CGFloat, _ total: Int) -> some View {
        if n > 0 {
            coreShape(4).fill(c)
                .frame(width: shown ? max(8, width * CGFloat(n) / CGFloat(total) - 3) : 8)
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
                    Text(provider.name).coreFont(size: MacTextSize.title, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "\(accounts.count) account\(accounts.count == 1 ? "" : "s")\(provider.builtin ? "" : " · custom, not usable by agents yet")"
                    )
                    .foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                AccLink(title: open ? "Hide details" : "About", symbol: open ? "chevron.up" : "info.circle") {
                    withAnimation(.smooth(duration: 0.35)) { open.toggle() }
                }
                if !provider.builtin {
                    AccLink(title: "Edit", symbol: "slider.horizontal.3") {
                        AccountDialogs.openProvider(model, editing: provider)
                    }
                    .disabled(model.readOnly)
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
                            Text("List prices read \(at)").coreFont(size: MacTextSize.meta).foregroundStyle(
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
                    Text(provider.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(
                        provider.loginMethods.contains("browser_code")
                            ? "Sign in with your Claude plan"
                            : provider.builtin ? "Add an API key" : "Your provider · no accounts yet"
                    )
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                if !provider.builtin {
                    AccLink(title: "Remove", symbol: "trash") { AccountDialogs.openDeleteProvider(model, provider) }
                        .disabled(model.readOnly)
                    AccLink(title: "Edit", symbol: "slider.horizontal.3") {
                        AccountDialogs.openProvider(model, editing: provider)
                    }
                    .disabled(model.readOnly)
                }
                AccLink(title: "Connect", symbol: "plus") { AccountDialogs.openConnect(model, provider: provider.id) }
                    .disabled(model.readOnly)
            }
        }
    }
}

/// The way back to a list, as a tile beside the page's icon (the Devices look): it nudges left on hover. Esc does the same.
struct BackTile: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
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
        .animation(.smooth(duration: 0.25), value: hovering)
        .help("All accounts (esc)")
        .accessibilityLabel("All accounts")
    }
}

/// Your own provider, such as OpenRouter: a definition Core checks, whose keys go through its gateway only.
private struct AddProviderCard: View {
    let model: AccountsModel
    @State private var hovering = false
    var body: some View {
        Button {
            AccountDialogs.openProvider(model, editing: nil)
        } label: {
            HStack(spacing: Space.s3) {
                IconTile("plus", hue: GlassInk.slate, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add a provider").coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text(
                        "OpenRouter or another API. Not usable by agents yet: its accounts can't join pools or chains."
                    )
                    .foregroundStyle(GlassInk.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    GlassInk.wellEdge, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain).focusEffectDisabled().disabled(model.readOnly)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
    }
}
