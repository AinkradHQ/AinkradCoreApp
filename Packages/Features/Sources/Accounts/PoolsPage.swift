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
                symbol: "square.grid.2x2.fill", hue: GlassInk.violet
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
        let hue = ProviderLook.hue(pool.provider)
        Button {
            withAnimation(.spring(duration: 0.3)) {
                model.poolSelection = pool.id
                model.cursor = nil
            }
        } label: {
            HStack(spacing: Space.s2) {
                AccTile(provider: pool.provider).scaleEffect(0.8)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(pool.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                        if pool.isDefault {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(GlassInk.orange)
                        }
                    }
                    Text("\(pool.members.count) account\(pool.members.count == 1 ? "" : "s")")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.leading, Space.s1).padding(.trailing, Space.s3).frame(minHeight: 48)
            .background {
                if on {
                    coreShape(Radius.control + 2).fill(hue.opacity(0.35))
                        .shadow(color: hue.opacity(0.45), radius: 10)
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
        .scaleEffect(hovering ? 1.03 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pool-tab-\(pool.name)")
    }
}

private struct PoolDetail: View {
    let model: AccountsModel
    let pool: PoolItem

    var body: some View {
        let ro = model.readOnly
        let bound = model.bindings(of: pool)
        let first = model.firstReady(in: pool)
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(
                    "\(model.providerName(pool.provider)) pool. "
                        + (pool.isDefault
                            ? "The default: it also serves every agent of this provider with no binding. The default cannot be deleted; make another pool the default first."
                            : "Serves the agents bound to it.")
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s2)
                // Always shown, so the option is findable; the Core refuses the default pool, so it is off there with the reason above.
                if !pool.isDefault {
                    AppActionTile(title: "Make default", symbol: "star", key: "D", hue: GlassInk.orange) {
                        Task { await model.makeDefault(pool) }
                    }
                    .disabled(ro || model.busy != nil)
                }
                AppActionTile(title: "Delete pool", symbol: ro ? "lock" : "trash", key: "", hue: GlassInk.red) {
                    AccountDialogs.openDeletePool(model, pool)
                }
                .disabled(ro || pool.isDefault)
                .opacity(pool.isDefault ? 0.5 : 1)
                .help(pool.isDefault ? "The default pool cannot be deleted" : "Delete \(pool.name) and its bindings")
                .accessibilityIdentifier("pool-delete-button")
            }
            HStack(alignment: .top, spacing: Space.s3) {
                AccPanel(spacing: Space.s2) {
                    HStack {
                        Label("Agents", systemImage: "sparkles").font(
                            .system(size: MacTextSize.title, weight: .semibold))
                        Spacer()
                        AccLink(title: "Bind · B", symbol: "link") { AccountDialogs.openBind(model, pool: pool) }
                            .disabled(ro)
                    }
                    if bound.isEmpty {
                        Text(
                            pool.isDefault
                                ? "No agent is bound here. Agents with no binding use this pool."
                                : "No agent uses this pool yet."
                        )
                        .foregroundStyle(GlassInk.secondary)
                    }
                    ForEach(bound) { b in
                        HStack {
                            AccTile(symbol: "sparkles", provider: "agent").scaleEffect(0.8)
                            Text(b.agent).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                            Spacer()
                            AccLink(
                                title: "Unbind", symbol: ro ? "lock" : nil, help: "Unbind \(b.agent) from \(pool.name)"
                            ) {
                                Task { await model.unbind(b) }
                            }
                            .disabled(ro)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    if let e = model.writeError["bind"] { AccIssue(text: e) }
                }
                AccPanel(spacing: Space.s2) {
                    HStack {
                        Label("Accounts", systemImage: "list.number").font(
                            .system(size: MacTextSize.title, weight: .semibold))
                        Spacer()
                        AccLink(title: "Add · A", symbol: "plus") { AccountDialogs.openAddMember(model, pool: pool) }
                            .disabled(ro)
                    }
                    if pool.members.isEmpty {
                        Text("Add an account to get this pool working.").foregroundStyle(GlassInk.orange)
                    }
                    ForEach(Array(pool.members.enumerated()), id: \.offset) { i, id in
                        MemberRow(model: model, pool: pool, index: i, id: id, first: first?.id == id)
                    }
                    if let e = model.writeError["member-\(pool.id)"] ?? model.writeError["default-\(pool.id)"] {
                        AccIssue(text: e)
                    }
                    Text(
                        "Accounts are tried in this order. If one stops, the next ready account of this provider takes over and the task restarts without its earlier conversation. Core only adds to the end of the order."
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
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
        let hue = ProviderLook.hue(pool.provider)
        let on = model.cursor == "m-\(id)"
        HStack(spacing: Space.s3) {
            Text("\(index + 1)").font(.system(size: MacTextSize.body, weight: .bold, design: .rounded))
                .foregroundStyle(first ? .white : GlassInk.secondary)
                .frame(width: 26, height: 26)
                .background(first ? hue.opacity(0.85) : GlassInk.well, in: coreShape(7))
                .shadow(color: hue.opacity(first ? 0.5 : 0), radius: 6)
            AccTile(provider: pool.provider).scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 0) {
                Text(a?.label ?? "Account \(id)").font(.system(size: MacTextSize.headline, weight: .semibold))
                    .lineLimit(1)
                Text(first ? "Tried first" : AccountsWords.capWords(a?.cap ?? 0)).font(.system(size: MacTextSize.meta))
                    .foregroundStyle(first ? hue : GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            if let a { PhaseBadge(phase: a.phase) }
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
        .shadow(color: hue.opacity(on ? 0.4 : 0), radius: 10)
        .contentShape(coreShape(Radius.control + 2))
        .onTapGesture { withAnimation(.spring(duration: 0.25)) { model.cursor = "m-\(id)" } }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .animation(.spring(duration: 0.25), value: on)
        .id("m-\(id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("member-\(a?.label ?? String(id))")
    }
}

/// Bindings: which pool each agent draws a provider's accounts from. An agent with none uses the provider's default pool.
struct BindingsPage: View {
    let model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Bindings",
                detail:
                    "An agent draws each provider's accounts from one pool. With no binding it uses the provider's default pool.",
                symbol: "link", hue: GlassInk.blue
            ) { EmptyView() }
            if model.bindings.isEmpty {
                AccStateCard(
                    symbol: "link", title: "No agent is bound",
                    text: "Every agent uses its provider's default pool. Bind one to give it a pool of its own.")
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(Array(model.bindings.enumerated()), id: \.element.id) { i, b in
                        BindingRow(model: model, binding: b, index: i)
                    }
                    if let e = model.writeError.first(where: { $0.key.hasPrefix("unbind-") })?.value {
                        AccIssue(text: e)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bindings")
    }
}

/// One binding as a flow: the agent's tile, an arrow that travels, the provider's tile and its pool; Unbind on hover or
/// on the cursor.
private struct BindingRow: View {
    let model: AccountsModel
    let binding: BindingItem
    let index: Int
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let b = binding
        let hue = ProviderLook.hue(b.provider)
        let on = model.cursor == "b-\(b.id)"
        HStack(spacing: Space.s3) {
            AccTile(symbol: "sparkles", provider: "agent")
            Text(b.agent).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced)).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(hue)
                .offset(x: shown && !reduce ? 4 : -4)
                .animation(reduce ? nil : .easeInOut(duration: 1).repeatForever(), value: shown)
            AccTile(provider: b.provider).scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.providerName(b.provider)).font(.system(size: MacTextSize.meta)).foregroundStyle(
                    GlassInk.secondary)
                if let p = model.pool(b.poolID) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            model.poolSelection = p.id
                            model.page = .pools
                        }
                    } label: {
                        Text("\(p.name) pool\(p.isDefault ? " · default" : "")").font(
                            .system(size: MacTextSize.body, weight: .semibold)
                        )
                        .foregroundStyle(hue)
                    }
                    .buttonStyle(.plain).focusable(false)
                } else {
                    AccChip(text: "pool \(b.poolID)", mono: true)
                }
            }
            Spacer(minLength: Space.s2)
            if hovering || on {
                AccLink(
                    title: "Unbind", symbol: model.readOnly ? "lock" : "link.badge.plus", danger: true,
                    help: "Unbind \(b.agent)"
                ) {
                    Task { await model.unbind(b) }
                }
                .disabled(model.readOnly)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(Space.s3)
        .background(
            on ? hue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(on ? hue.opacity(0.7) : GlassInk.wellEdge, lineWidth: on ? 1.5 : 1)
        }
        .shadow(color: hue.opacity(on ? 0.4 : 0), radius: 12)
        .scaleEffect(hovering ? 1.01 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture { withAnimation(.spring(duration: 0.25)) { model.cursor = "b-\(b.id)" } }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .animation(.spring(duration: 0.25), value: on)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .id("b-\(b.id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("binding-\(b.agent)")
    }
}
