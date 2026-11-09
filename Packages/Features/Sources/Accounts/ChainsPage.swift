import CoreUI
import SwiftUI

/// Chains: a chain is an ordered list of 1 to 4 pools, each with a model. A new session tries the first pool that has an
/// account to give; when an account fails it moves down the list. Only admins see this page.
struct ChainsPage: View {
    let model: AccountsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            AccHeader(
                title: "Chains",
                detail:
                    "A chain lists pools in the order a session tries them. If an account fails, the next pool takes over.",
                symbol: "link", hue: GlassInk.blue
            ) { EmptyView() }
            if model.chains.isEmpty {
                AccStateCard(
                    symbol: "link", title: "No chains yet",
                    text:
                        "Without a chain, a session runs on one harness you pick. Make one with New chain (⌘N) to let sessions fall back to another pool."
                )
            } else {
                tabs
                if let c = model.selectedChain {
                    ChainDetail(model: model, chain: c).id(c.id).transition(.opacity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chains")
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(model.chains) { c in ChainTab(model: model, chain: c, on: c.id == model.selectedChain?.id) }
            }
            .padding(Space.s1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chains")
    }
}

private struct ChainTab: View {
    let model: AccountsModel
    let chain: ChainItem
    let on: Bool
    @State private var hovering = false
    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { model.chainSelection = chain.id }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(chain.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                Text(
                    "\(chain.entries.count) pool\(chain.entries.count == 1 ? "" : "s")\(chain.isDefault ? " · default" : "")"
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s3).frame(minHeight: 48)
            .background(
                on ? GlassInk.blue.opacity(0.3) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.control + 2)
            )
            .overlay {
                coreShape(Radius.control + 2).strokeBorder(
                    on ? GlassInk.blue.opacity(0.7) : GlassInk.wellEdge, lineWidth: 1)
            }
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("chain-tab-\(chain.name)")
    }
}

private struct ChainDetail: View {
    let model: AccountsModel
    let chain: ChainItem

    var body: some View {
        let ro = model.readOnly
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chain.name).font(.system(size: MacTextSize.large, weight: .bold))
                    Label(
                        chain.isDefault
                            ? "Default: for agents with no chain of their own" : "Serves agents bound to it",
                        systemImage: chain.isDefault ? "checkmark.circle" : "link"
                    )
                    .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                if !chain.isDefault {
                    AppActionTile(title: "Make default", symbol: "checkmark.circle", key: "D", hue: GlassInk.blue) {
                        Task { await model.makeDefault(chain) }
                    }
                    .disabled(ro || model.busy != nil)
                }
                AppActionTile(title: "Edit…", symbol: "slider.horizontal.3", key: "E", hue: GlassInk.blue) {
                    AccountDialogs.openChain(model, editing: chain)
                }
                .disabled(ro)
                AppActionTile(title: "Delete", symbol: ro ? "lock" : "trash", key: "", hue: GlassInk.red) {
                    AccountDialogs.openDeleteChain(model, chain)
                }
                .disabled(ro)
                .accessibilityIdentifier("chain-delete-button")
            }
            AccPanel(spacing: Space.s2) {
                Label("Pools, in the order they're tried", systemImage: "list.number").font(
                    .system(size: MacTextSize.title, weight: .semibold))
                ForEach(Array(chain.entries.enumerated()), id: \.offset) { i, e in
                    EntryRow(model: model, index: i, entry: e)
                }
                if let e = model.writeError["chain-default-\(chain.id)"] { AccIssue(text: e) }
                Text("A running session keeps the chain it started with. Edits apply to new sessions.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AccPanel(spacing: Space.s2) {
                HStack {
                    Label("Agents on this chain", systemImage: "person.2").font(
                        .system(size: MacTextSize.title, weight: .semibold))
                    Spacer()
                    AccLink(title: "Bind an agent", symbol: "plus") {
                        AccountDialogs.openBindAgent(model, chain: chain)
                    }
                    .disabled(ro)
                }
                let agents = model.agents(of: chain)
                if agents.isEmpty {
                    Text("No agent is bound to this chain.").foregroundStyle(GlassInk.secondary)
                }
                ForEach(agents) { b in
                    HStack(spacing: Space.s3) {
                        Text(b.agent).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                        Spacer(minLength: Space.s2)
                        AccLink(title: "Unbind", symbol: "xmark", danger: true, help: "Unbind \(b.agent)") {
                            Task { await model.unbind(b.agent) }
                        }
                        .disabled(ro || model.busy != nil)
                    }
                    .padding(Space.s2).background(GlassInk.well, in: coreShape(Radius.control + 2))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bound-\(b.agent)")
                }
                if let e = model.writeError["bind-chain"] ?? model.writeError["unbind-\(agents.first?.agent ?? "")"] {
                    AccIssue(text: e)
                }
            }
        }
    }
}

/// One step: its place, its provider tile, the pool and the model it runs.
private struct EntryRow: View {
    let model: AccountsModel
    let index: Int
    let entry: ChainEntryItem
    var body: some View {
        HStack(spacing: Space.s3) {
            Text("\(index + 1)").font(.system(size: MacTextSize.body, weight: .bold, design: .rounded))
                .foregroundStyle(index == 0 ? .white : GlassInk.secondary)
                .frame(width: 26, height: 26)
                .background(index == 0 ? GlassInk.blue.opacity(0.85) : GlassInk.well, in: coreShape(7))
            AccTile(provider: entry.provider).scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.providerName(entry.provider)) · \(model.pool(entry.pool)?.name ?? "Pool \(entry.pool)")")
                    .font(
                        .system(size: MacTextSize.headline, weight: .semibold)
                    ).lineLimit(1)
                Text(index == 0 ? "Tried first" : "Tried if the one above has no account to give")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            AccChip(text: entry.model ?? "Provider's default model", mono: entry.model != nil)
        }
        .padding(Space.s2).background(GlassInk.well, in: coreShape(Radius.control + 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chain-entry-\(index + 1)")
    }
}
