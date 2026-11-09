import CoreUI
import SwiftUI

/// Pools: a pool is a team of one provider's accounts. Members are tried in fallback order; the Core only appends to it.
struct PoolsPage: View {
    let model: AccountsModel
    @Namespace private var lens

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Pools",
                detail:
                    "A pool is a team of accounts from one provider. Agents share it, and Core picks who works next.",
                symbol: "square.grid.2x2.fill", hue: GlassInk.blue
            ) { EmptyView() }
            if model.pools.isEmpty {
                AccStateCard(
                    symbol: "square.grid.2x2", title: "No pools yet",
                    text:
                        "Agents only use accounts that are in a pool. Make one for a provider with New pool (⌘N), then add its accounts."
                )
            } else {
                tabs
                if let p = model.selectedPool {
                    PoolDetail(model: model, pool: p).id(p.id).transition(
                        .opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pools")
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(model.pools) { p in
                    PoolTab(model: model, pool: p, on: p.id == model.selectedPool?.id, lens: lens)
                }
            }
            .padding(Space.s1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pools")
    }
}

/// A pool as a tile: its provider's tile, the name and its facts. The picked one lights in the provider's colour and the
/// light glides between pools; hover lifts.
private struct PoolTab: View {
    let model: AccountsModel
    let pool: PoolItem
    let on: Bool
    let lens: Namespace.ID
    @State private var hovering = false
    var body: some View {
        let hue = GlassInk.blue
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                model.poolSelection = pool.id
                model.cursor = nil
            }
        } label: {
            HStack(spacing: Space.s2) {
                AccTile(provider: pool.provider).scaleEffect(0.8)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("\(ProviderLook.short(pool.provider, pool.provider)) · \(pool.name)").coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                        if pool.isDefault {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(GlassInk.orangeInk)
                        }
                    }
                    Text("\(pool.members.count) account\(pool.members.count == 1 ? "" : "s")")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.leading, Space.s1).padding(.trailing, Space.s3).frame(minHeight: 48)
            .background {
                if on {
                    coreShape(Radius.control + 2).fill(hue.opacity(0.35))
                        .matchedGeometryEffect(id: "lens", in: lens)
                } else {
                    coreShape(Radius.control + 2).fill(hovering ? GlassInk.wellHover : GlassInk.well)
                }
            }
            .overlay {
                coreShape(Radius.control + 2).strokeBorder(on ? hue.opacity(0.7) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pool-tab-\(pool.name)")
    }
}

private struct PoolDetail: View {
    let model: AccountsModel
    let pool: PoolItem

    var body: some View {
        let ro = model.readOnly
        let first = model.firstReady(in: pool)
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .center, spacing: Space.s3) {
                AccTile(large: true, provider: pool.provider)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ProviderLook.short(pool.provider, model.providerName(pool.provider))) · \(pool.name)")
                        .coreFont(size: MacTextSize.large, weight: .bold)
                    HStack(spacing: Space.s2) {
                        if pool.isDefault {
                            Label("Default pool for its provider", systemImage: "star.fill")
                                .foregroundStyle(GlassInk.orangeInk)
                        } else {
                            Label("Used by the chains that list it", systemImage: "link").foregroundStyle(
                                GlassInk.secondary)
                        }
                    }
                    .coreFont(size: MacTextSize.meta, weight: .semibold)
                }
                Spacer(minLength: Space.s2)
                if !pool.isDefault {
                    AppActionTile(title: "Make default", symbol: "star", key: "D", hue: GlassInk.blue) {
                        Task { await model.makeDefault(pool) }
                    }
                    .disabled(ro || model.busy != nil)
                    AppActionTile(title: "Delete pool", symbol: ro ? "lock" : "trash", key: "", hue: GlassInk.red) {
                        AccountDialogs.openDeletePool(model, pool)
                    }
                    .disabled(ro)
                    .help("Delete \(pool.name)")
                    .accessibilityIdentifier("pool-delete-button")
                }
            }
            HStack(alignment: .top, spacing: Space.s3) {
                AccPanel(spacing: Space.s2) {
                    HStack {
                        Label("Accounts, in the order they're tried", systemImage: "list.number").coreFont(size: MacTextSize.title, weight: .semibold)
                        Spacer()
                        AccLink(title: "Add · A", symbol: "plus") { AccountDialogs.openAddMember(model, pool: pool) }
                            .disabled(ro)
                    }
                    if pool.members.isEmpty {
                        Text("Add an account to get this pool working.").foregroundStyle(GlassInk.orangeInk)
                    }
                    ForEach(Array(pool.members.enumerated()), id: \.offset) { i, id in
                        MemberRow(model: model, pool: pool, index: i, id: id, first: first?.id == id)
                    }
                    if let e = model.writeError["member-\(pool.id)"] ?? model.writeError["default-\(pool.id)"] {
                        AccIssue(text: e)
                    }
                    Text("Tried top to bottom. If one stops, the next ready one takes over.")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One member in fallback order: its place as a numbered tile (glowing for the one tried first), its provider tile, its
/// state, and a remove action. The keyboard's cursor glows.
private struct MemberRow: View {
    let model: AccountsModel
    let pool: PoolItem
    let index: Int
    let id: Int64
    let first: Bool
    @State private var hovering = false

    var body: some View {
        let a = model.account(id)
        let hue = GlassInk.blue
        let on = model.cursor == "m-\(id)"
        HStack(spacing: Space.s3) {
            Text("\(index + 1)").coreFont(size: MacTextSize.body, weight: .bold, design: .rounded)
                .foregroundStyle(first ? .white : GlassInk.secondary)
                .frame(width: 26, height: 26)
                .background(first ? hue.opacity(0.85) : GlassInk.well, in: coreShape(7))
            AccTile(provider: pool.provider).scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 0) {
                Text(a?.label ?? "Account \(id)").coreFont(size: MacTextSize.headline, weight: .semibold)
                    .lineLimit(1)
                Text(first ? "Tried first" : AccountsWords.capWords(a?.cap ?? 0)).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(first ? GlassInk.blueInk : GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            if let a { VerdictBadge(verdict: model.verdict(a)) }
            if let a, hovering || on {
                AccLink(title: "Remove", symbol: "xmark", danger: true, help: "Remove \(a.label) from \(pool.name)") {
                    Task { await model.remove(a, from: pool) }
                }
                .disabled(model.readOnly || model.busy != nil)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(Space.s2)
        .background(
            on ? hue.opacity(0.18) : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control + 2)
        )
        .overlay { coreShape(Radius.control + 2).strokeBorder(on ? hue.opacity(0.7) : .clear, lineWidth: 1.5) }
        .contentShape(coreShape(Radius.control + 2))
        .onTapGesture { withAnimation(.smooth(duration: 0.25)) { model.cursor = "m-\(id)" } }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .animation(.smooth(duration: 0.25), value: on)
        .id("m-\(id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("member-\(a?.label ?? String(id))")
        .coreActivates { model.cursor = "m-\(id)" }
    }
}
