import CoreUI
import SwiftUI

/// One account (Ahmed, 2026-11-05: visual, easy to understand). The page answers one question first: can my agents use
/// it, and if not, what is missing. A stage with the account's tile, state and that answer; a path of the three things
/// an account needs (key saved, turned on, in a pool) with the missing one offering its fix; then three tiles: the key,
/// how many sessions at once, and the pools it is in. What Core does not report yet is one quiet line, not a card.
struct AccountDetailView: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var tech = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    var body: some View {
        let a = account
        let ro = model.readOnly
        let pools = model.pools(of: a)
        let on = a.phase != .disabled
        let verdict = model.verdict(a)
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .center, spacing: Space.s3) {
                    BackTile { model.detail = nil }
                    AccTile(large: true, provider: a.provider)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Space.s2) {
                            Text(a.label).font(.system(size: MacTextSize.large, weight: .bold)).lineLimit(1)
                                .accessibilityAddTraits(.isHeader)
                            VerdictBadge(verdict: verdict)
                        }
                        Text(model.providerName(a.provider)).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Space.s3)
                    HStack(spacing: Space.s2) {
                        AppActionTile(title: "Remove", symbol: "trash", key: "⌫", hue: GlassInk.red) {
                            AccountDialogs.openDelete(model, a)
                        }
                        .disabled(ro)
                        AppActionTile(title: "New key", symbol: "key.fill", key: "K", hue: GlassInk.blue) {
                            AccountDialogs.openConnect(model, provider: a.provider, replacing: a)
                        }
                        .disabled(ro)
                        AppActionTile(
                            title: on ? "Turn off" : "Turn on", symbol: on ? "pause.fill" : "play.fill", key: "T",
                            hue: on ? GlassInk.slate : GlassInk.green, prominent: !on
                        ) {
                            Task { await model.setEnabled(a, !on) }
                        }
                        .disabled(ro || model.busy != nil)
                    }
                }
                .id("top")
                banner(a, verdict: verdict, pools: pools, proxy: proxy)
                if let e = model.writeError["account-\(a.id)"] { AccIssue(text: e) }
                if a.lastTest?.result == "auth_failed", a.phase != .disabled { confirming }
                HStack(alignment: .top, spacing: Space.s3) {
                    keyTile(a)
                    tile("Key test", "checkmark.shield.fill") { TestTile(model: model, account: a, hue: GlassInk.blue) }
                        .id("keytest")
                    poolsTile(a, pools).id("pools")
                }
                .fixedSize(horizontal: false, vertical: true)
                AccountLimitsSection(model: model, account: a, hue: GlassInk.blue).id("limits")
                AccountSlice(model: model, account: a)
                HStack(spacing: Space.s2) {
                    Spacer(minLength: Space.s2)
                    AccLink(
                        title: tech ? "Hide details" : "Technical details", symbol: tech ? "chevron.up" : "chevron.down"
                    ) {
                        withAnimation(Motion.out(Motion.ui)) { tech.toggle() }
                    }
                }
                .font(.system(size: MacTextSize.meta))
                if tech {
                    HStack(spacing: Space.s2) {
                        AccChip(text: "state \(a.state)", mono: true)
                        AccChip(text: a.baseURL, mono: true)
                        AccChip(text: "id \(a.id)", mono: true)
                        AccChip(text: "added \(a.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    .transition(.opacity)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task(id: a.id) { await model.reloadCosts() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-detail")
    }

    // MARK: the answer

    /// One refusal no longer turns an account off: Core tests the key again and only a second refusal does.
    private var confirming: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "key.slash").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GlassInk.orangeInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("The provider refused this key once").font(.system(size: MacTextSize.headline, weight: .semibold))
                Text("Core is checking it again. If it's refused again, the account turns off by itself.")
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(GlassInk.orange.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.orange.opacity(0.4), lineWidth: 1) }
        .transition(.opacity)
    }

    /// The one verdict: what it is, why, and the way to its cause.
    private func banner(_ a: AccountItem, verdict: AccountVerdict, pools: [PoolItem], proxy: ScrollViewProxy) -> some View
    {
        let tone = palette.tone(verdict.tone)
        let title = verdict.usable ? "Your agents can use it" : verdict.label
        let line =
            verdict.usable
            ? "It's in \(pools.map(\.name).joined(separator: ", ")). Agents bound to \(pools.count == 1 ? "that pool" : "those pools") draw on it."
            : verdict.line(a, limits: model.limits(of: a), budgets: model.budgets, now: model.now())
        return HStack(spacing: Space.s4) {
            Image(systemName: verdict.usable ? "checkmark.seal.fill" : verdict.symbol)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(tone.ink)
                .frame(width: 52, height: 52)
                .background(GlassInk.well, in: coreShape(Radius.cardMac))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: MacTextSize.title, weight: .bold)).foregroundStyle(tone.ink)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            path(on: a.phase != .disabled, inPool: !pools.isEmpty, hue: GlassInk.blue)
            if let cause = verdict.cause, cause != .state, cause != .pools {
                AccLink(title: "Open \(AccountsWords.causeName(cause))", symbol: "arrow.down.right") {
                    open(cause, proxy: proxy)
                }
            }
            if verdict.kind == .noPool {
                AppActionTile(title: "Add to a pool", symbol: "square.grid.2x2", key: "P", hue: GlassInk.blue, prominent: true) {
                    addToPool(a)
                }
                .disabled(model.readOnly)
            }
        }
        .padding(Space.s4)
        .background(tone.fill.opacity(0.12), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(tone.ink.opacity(0.4), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-verdict")
    }

    /// A verdict's cause lives in one section of this page (or in Budgets): scroll to it.
    private func open(_ cause: AccountVerdict.Cause, proxy: ScrollViewProxy) {
        withAnimation(reduce ? nil : Motion.out(Motion.ui)) {
            switch cause {
            case .keyTest: proxy.scrollTo("keytest", anchor: .center)
            case .limits: proxy.scrollTo("limits", anchor: .center)
            case .pools: proxy.scrollTo("pools", anchor: .center)
            case .budgets:
                model.page = .budgets
                model.detail = nil
            case .state: proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    /// Key saved → Turned on → In a pool: each step lit once it holds.
    private func path(on: Bool, inPool: Bool, hue: Color) -> some View {
        HStack(spacing: 6) {
            ForEach(Array([("Key saved", true), ("Turned on", on), ("In a pool", inPool)].enumerated()), id: \.offset) {
                i, s in
                if i > 0 { coreShape(1).fill(s.1 ? hue : GlassInk.track).frame(width: 14, height: 2) }
                Label(s.0, systemImage: s.1 ? "checkmark" : "circle.dashed")
                    .font(.system(size: MacTextSize.meta, weight: .semibold))
                    .foregroundStyle(s.1 ? .white : GlassInk.secondary)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(s.1 ? hue.opacity(0.6) : GlassInk.well, in: coreShape(6))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Key saved\(on ? ", turned on" : ", turned off")\(inPool ? ", in a pool" : ", not in a pool")")
    }

    // MARK: tiles

    private func tile<C: View>(_ title: String, _ symbol: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(title, systemImage: symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
                .foregroundStyle(GlassInk.secondary)
            c()
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    private func keyTile(_ a: AccountItem) -> some View {
        tile("Key", "lock.shield.fill") {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    coreShape(2).fill(GlassInk.secondary).frame(width: 8, height: 8)
                }
                Text(a.maskedTail.isEmpty ? "saved" : a.maskedTail).font(
                    .system(size: MacTextSize.title, weight: .semibold, design: .monospaced))
            }
            Text("Kept sealed in Core. It can't be shown again.").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary)
            Text(AccountsWords.used(a.lastUsedAt, now: model.now())).font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private func poolsTile(_ a: AccountItem, _ pools: [PoolItem]) -> some View {
        tile("Pools", "square.grid.2x2.fill") {
            if pools.isEmpty {
                Text("In no pool").font(.system(size: MacTextSize.title, weight: .semibold))
                Text("Agents can't reach it yet.").font(.system(size: MacTextSize.meta)).foregroundStyle(
                    GlassInk.orangeInk)
            }
            ForEach(pools) { p in
                Button {
                    model.poolSelection = p.id
                    model.page = .pools
                    model.detail = nil
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: p.isDefault ? "star.fill" : "square.grid.2x2").foregroundStyle(GlassInk.blueInk)
                        Text(p.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, Space.s2).frame(minHeight: 30)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                }
                .buttonStyle(.plain).focusable(false)
            }
        }
    }

    /// Into this provider's first pool, or a new pool when it has none.
    private func addToPool(_ a: AccountItem) {
        if let p = model.defaultPool(a.provider) ?? model.pools(for: a.provider).first {
            AccountDialogs.openAddMember(model, pool: p)
        } else {
            AccountDialogs.openNewPool(model)
        }
    }
}

extension AccountsModel {
    /// Whether agents can draw on this account now: turned on, ready, and in at least one pool.
    func usable(_ a: AccountItem) -> Bool { a.phase == .active && !pools(of: a).isEmpty }
}
