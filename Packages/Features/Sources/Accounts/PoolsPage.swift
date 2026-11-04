import CoreUI
import SwiftUI

/// Pools: a pool is a team of one provider's accounts. Members are tried in fallback order; the Core only appends to it.
struct PoolsPage: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Pools",
                detail:
                    "A pool is a team of accounts from one provider. Agents share it, and Core picks who works next."
            ) {
                Button {
                    AccountDialogs.openNewPool(model)
                } label: {
                    Label("New pool", systemImage: "plus")
                }
                .buttonStyle(.coreProminent).disabled(model.readOnly).help("Make a pool for one provider")
            }
            if model.pools.isEmpty {
                AccStateCard(
                    symbol: "square.grid.2x2", title: "No pools yet",
                    text:
                        "Core makes a default pool for a provider when its first account arrives. You can also make one yourself."
                )
            } else {
                tabs
                if let p = model.selectedPool { PoolDetail(model: model, pool: p) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pools")
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(model.pools) { p in PoolTab(model: model, pool: p, on: p.id == model.selectedPool?.id) }
            }
            .padding(Space.s1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pools")
    }
}

private struct PoolTab: View {
    let model: AccountsModel
    let pool: PoolItem
    let on: Bool
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    var body: some View {
        Button {
            model.poolSelection = pool.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(pool.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                Text(
                    "\(model.providerName(pool.provider)) · \(pool.members.count) account\(pool.members.count == 1 ? "" : "s")\(pool.isDefault ? " · default" : "")"
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(on ? palette.navActive : palette.uDim, in: coreShape(Radius.control))
            .overlay { if on { coreShape(Radius.control).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused).focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.control, palette: palette)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pool-tab-\(pool.name)")
    }
}

private struct PoolDetail: View {
    let model: AccountsModel
    let pool: PoolItem
    @Environment(\.corePalette) private var palette

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
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s2)
                // Always shown, so the option is findable; the Core refuses the default pool, so it is off there with the reason above.
                Button {
                    AccountDialogs.openDeletePool(model, pool)
                } label: {
                    Label("Delete pool…", systemImage: ro ? "lock" : "trash")
                }
                .buttonStyle(.coreDanger).disabled(ro || pool.isDefault)
                .help(pool.isDefault ? "The default pool cannot be deleted" : "Delete \(pool.name) and its bindings")
                .accessibilityIdentifier("pool-delete-button")
            }
            HStack(alignment: .top, spacing: Space.s3) {
                AccPanel(spacing: Space.s2) {
                    HStack {
                        Text("Agents").font(.system(size: MacTextSize.title, weight: .semibold))
                        Spacer()
                        Button("Bind an agent…") { AccountDialogs.openBind(model, pool: pool) }
                            .buttonStyle(.coreSecondary).disabled(ro)
                    }
                    if bound.isEmpty {
                        Text(
                            pool.isDefault
                                ? "No agent is bound here. Agents with no binding use this pool."
                                : "No agent uses this pool yet."
                        )
                        .foregroundStyle(palette.text2)
                    }
                    ForEach(bound) { b in
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(palette.text2).accessibilityHidden(true)
                            Text(b.agent).font(.system(size: MacTextSize.body, design: .monospaced))
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
                        Text("Accounts").font(.system(size: MacTextSize.title, weight: .semibold))
                        Spacer()
                        if !pool.isDefault {
                            Button("Make default") { Task { await model.makeDefault(pool) } }
                                .buttonStyle(.coreSecondary).disabled(ro || model.busy != nil)
                        }
                        Button("Add…") { AccountDialogs.openAddMember(model, pool: pool) }
                            .buttonStyle(.coreSecondary).disabled(ro)
                    }
                    if pool.members.isEmpty {
                        Text("Add an account to get this pool working.").foregroundStyle(palette.text2)
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
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MemberRow: View {
    let model: AccountsModel
    let pool: PoolItem
    let index: Int
    let id: Int64
    let first: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        let a = model.account(id)
        HStack(spacing: Space.s3) {
            Text("\(index + 1)").font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(
                palette.text2
            )
            .frame(width: Space.s4)
            AccTile()
            VStack(alignment: .leading, spacing: 0) {
                Text(a?.label ?? "Account \(id)").font(.system(size: MacTextSize.headline, weight: .semibold))
                    .lineLimit(1)
                Text(first ? "Tried first" : AccountsWords.capWords(a?.cap ?? 0)).font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            if let a { PhaseBadge(phase: a.phase) }
            if let a {
                CoreIconButton(symbol: "xmark", label: "Remove \(a.label) from \(pool.name)") {
                    Task { await model.remove(a, from: pool) }
                }
                .disabled(model.readOnly || model.busy != nil)
            }
        }
        .padding(Space.s2).background(
            first ? palette.navActive.opacity(0.5) : palette.uDim, in: coreShape(Radius.control)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("member-\(a?.label ?? String(id))")
    }
}

/// Bindings: which pool each agent draws a provider's accounts from. An agent with none uses the provider's default pool.
struct BindingsPage: View {
    let model: AccountsModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Bindings",
                detail:
                    "An agent draws each provider's accounts from one pool. With no binding it uses the provider's default pool."
            ) {
                Button {
                    AccountDialogs.openBind(model, pool: nil)
                } label: {
                    Label("Bind an agent", systemImage: "plus")
                }
                .buttonStyle(.coreProminent).disabled(model.readOnly || model.pools.isEmpty)
            }
            if model.bindings.isEmpty {
                AccStateCard(
                    symbol: "link", title: "No agent is bound",
                    text: "Every agent uses its provider's default pool. Bind one to give it a pool of its own.")
            } else {
                AccPanel(spacing: Space.s2) {
                    ForEach(model.bindings) { b in
                        HStack(spacing: Space.s3) {
                            Image(systemName: "sparkles").foregroundStyle(palette.text2).accessibilityHidden(true)
                            Text(b.agent).font(
                                .system(size: MacTextSize.headline, weight: .semibold, design: .monospaced)
                            ).lineLimit(1)
                            Image(systemName: "arrow.right").foregroundStyle(palette.text2).accessibilityHidden(true)
                            Text(model.providerName(b.provider)).foregroundStyle(palette.text2)
                            if let p = model.pool(b.poolID) {
                                AccLink(title: "\(p.name) pool\(p.isDefault ? " (default)" : "")") {
                                    model.poolSelection = p.id
                                    model.page = .pools
                                }
                            } else {
                                AccChip(text: "pool \(b.poolID)", mono: true)
                            }
                            Spacer(minLength: Space.s2)
                            AccLink(title: "Unbind", symbol: model.readOnly ? "lock" : nil, help: "Unbind \(b.agent)") {
                                Task { await model.unbind(b) }
                            }
                            .disabled(model.readOnly)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("binding-\(b.agent)")
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
