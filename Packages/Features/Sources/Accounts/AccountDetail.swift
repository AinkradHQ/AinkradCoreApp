import CoreUI
import SwiftUI

/// One account (Ahmed, 2026-11-05: visual, easy to understand). The page answers one question first: can my agents use
/// it, and if not, what is missing. A stage with the account's tile, state and that answer; a path of the three things
/// an account needs (key saved, turned on, in a pool) with the missing one offering its fix; then three tiles: the key,
/// how many sessions at once, and the pools it is in. What Core does not report yet is one quiet line, not a card.
struct AccountDetailView: View {
    let model: AccountsModel
    let account: AccountItem
    @State private var shown = false
    @State private var tech = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let a = account
        let ro = model.readOnly
        let hue = ProviderLook.hue(a.provider)
        let pools = model.pools(of: a)
        let on = a.phase != .disabled
        let usable = a.phase == .active && !pools.isEmpty
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .center, spacing: Space.s3) {
                BackTile { model.detail = nil }
                AccTile(large: true, provider: a.provider)
                    .symbolEffect(.pulse, options: .repeating, isActive: usable && !reduce)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s2) {
                        Text(a.label).font(.system(size: MacTextSize.large, weight: .bold)).accessibilityAddTraits(
                            .isHeader)
                        PhaseBadge(phase: a.phase)
                    }
                    Text(model.providerName(a.provider)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s3)
                HStack(spacing: Space.s2) {
                    AppActionTile(title: "Remove", symbol: "trash", key: "⌫", hue: GlassInk.red) {
                        AccountDialogs.openDelete(model, a)
                    }
                    .disabled(ro)
                    AppActionTile(title: "New key", symbol: "key.fill", key: "K", hue: GlassInk.orange) {
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
            verdict(a, usable: usable, on: on, pools: pools, hue: hue)
            if let e = model.writeError["account-\(a.id)"] { AccIssue(text: e) }
            if a.lastTest?.result == "auth_failed", a.phase != .disabled { confirming }
            HStack(alignment: .top, spacing: Space.s3) {
                keyTile(a, hue)
                capTile(a, hue)
                poolsTile(a, pools, hue)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Space.s3) {
                tile("Key test", "checkmark.shield.fill", hue) { TestTile(model: model, account: a, hue: hue) }
                tile("Each session", "gauge.with.needle.fill", hue) {
                    LimitsTileBody(model: model, account: a, hue: hue)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            AccountLimitsSection(model: model, account: a, hue: hue)
            HStack(spacing: Space.s2) {
                Image(systemName: "hourglass").foregroundStyle(GlassInk.slate)
                Text("Spend and usage over time appear here once Core reports them.")
                    .foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s2)
                AccLink(
                    title: tech ? "Hide details" : "Technical details", symbol: tech ? "chevron.up" : "chevron.down"
                ) {
                    withAnimation(.smooth(duration: 0.35)) { tech.toggle() }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-detail")
    }

    // MARK: the answer

    /// One refusal no longer turns an account off: Core tests the key again and only a second refusal does.
    private var confirming: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "key.slash").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GlassInk.orangeInk)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduce)
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

    /// "Agents can use it" or what is missing, with the three things an account needs as a path, and the fix.
    private func verdict(_ a: AccountItem, usable: Bool, on: Bool, pools: [PoolItem], hue: Color) -> some View {
        let tone: Color = usable ? GlassInk.green : a.phase.tone == .fail ? GlassInk.red : GlassInk.orange
        let title =
            usable
            ? "Your agents can use it"
            : !on ? "Turned off" : a.phase != .active ? a.phase.label : "Not in a pool yet"
        let line =
            usable
            ? "It's in \(pools.map { "\($0.name)" }.joined(separator: ", ")). Agents bound to \(pools.count == 1 ? "that pool" : "those pools") draw on it."
            : !on || a.phase != .active
                ? AccountsWords.why(a, now: model.now())
                : "Agents only use accounts that are in a pool. Add it to one and it's ready."
        return HStack(spacing: Space.s4) {
            Image(systemName: usable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [tone, tone.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    in: coreShape(13)
                )
                .shadow(color: tone.opacity(0.5), radius: 12)
                .symbolEffect(.bounce, value: usable)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: MacTextSize.title, weight: .bold)).foregroundStyle(tone)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            path(on: on, inPool: !pools.isEmpty, hue: tone)
            if on, a.phase == .active, pools.isEmpty {
                AppActionTile(title: "Add to a pool", symbol: "square.grid.2x2", key: "P", hue: hue, prominent: true) {
                    addToPool(a)
                }
                .disabled(model.readOnly)
            }
        }
        .padding(Space.s4)
        // The glow is an overlay of the fill, so it can never change the banner's size.
        .background {
            tone.opacity(0.1)
                .overlay(alignment: .leading) {
                    coreShape(60).fill(tone.opacity(0.35)).frame(width: 200, height: 80).blur(radius: 50)
                        .offset(x: shown && !reduce ? 40 : -60)
                        .animation(reduce ? nil : .easeInOut(duration: 4).repeatForever(), value: shown)
                }
                .clipShape(coreShape(Radius.cardMac))
        }
        .overlay { coreShape(Radius.cardMac).strokeBorder(tone.opacity(0.45), lineWidth: 1) }
        .animation(.smooth(duration: 0.4), value: usable)
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

    private func tile<C: View>(_ title: String, _ symbol: String, _ hue: Color, @ViewBuilder _ c: () -> C) -> some View
    {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(title, systemImage: symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
                .foregroundStyle(hue)
            c()
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    private func keyTile(_ a: AccountItem, _ hue: Color) -> some View {
        tile("Key", "lock.shield.fill", hue) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    coreShape(2).fill(GlassInk.secondary).frame(width: 8, height: 8)
                        .opacity(shown ? 1 : 0).animation(.smooth(duration: 0.3).delay(Double(i) * 0.06), value: shown)
                }
                Text(a.maskedTail.isEmpty ? "saved" : a.maskedTail).font(
                    .system(size: MacTextSize.title, weight: .semibold, design: .monospaced))
            }
            Text("Kept sealed in Core. It can't be shown again.").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary)
        }
    }

    /// The limit as slots: one rounded bar per session it may run at once (or an open line when there is no limit).
    private func capTile(_ a: AccountItem, _ hue: Color) -> some View {
        tile("At once", "square.stack.3d.up.fill", hue) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(a.cap == 0 ? "∞" : "\(a.cap)").font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(a.cap == 0 ? "no limit" : a.cap == 1 ? "session" : "sessions").foregroundStyle(
                    GlassInk.secondary)
                Spacer(minLength: 0)
                AccLink(title: "Change · L", symbol: "slider.horizontal.3") { AccountDialogs.openCap(model, a) }
                    .disabled(model.readOnly)
            }
            HStack(spacing: 4) {
                ForEach(0..<Int(min(max(a.cap, 1), 12)), id: \.self) { i in
                    coreShape(3).fill(a.cap == 0 ? hue.opacity(0.35) : hue.opacity(0.8)).frame(height: 8)
                        .scaleEffect(x: 1, y: shown ? 1 : 0.2, anchor: .bottom)
                        .animation(.smooth(duration: 0.4).delay(Double(i) * 0.05), value: shown)
                }
            }
            Text(AccountsWords.used(a.lastUsedAt, now: model.now())).font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private func poolsTile(_ a: AccountItem, _ pools: [PoolItem], _ hue: Color) -> some View {
        tile("Pools", "square.grid.2x2.fill", hue) {
            if pools.isEmpty {
                Text("In no pool").font(.system(size: MacTextSize.title, weight: .semibold))
                Text("Agents can't reach it yet.").font(.system(size: MacTextSize.meta)).foregroundStyle(
                    GlassInk.orange)
            }
            ForEach(pools) { p in
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        model.poolSelection = p.id
                        model.page = .pools
                        model.detail = nil
                    }
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: p.isDefault ? "star.fill" : "square.grid.2x2").foregroundStyle(hue)
                        Text(p.name).font(.system(size: MacTextSize.headline, weight: .semibold))
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
