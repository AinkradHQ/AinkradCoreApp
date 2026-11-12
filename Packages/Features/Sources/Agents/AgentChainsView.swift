import CoreUI
import SwiftUI

/// Settings, Agents and chains: each known agent with the chain its sessions draw accounts from, a chain picker per agent and
/// Unbind. The chains themselves are made in Accounts, Chains. An agent with no chain uses the default one.
struct AgentChainsSection: View {
    @Bindable var model: AgentsModel
    @State private var newAgent = ""
    @State private var newChain: Int64 = 0
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(intro).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            content
        }
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("agent-chains")
        .task { if model.bindingsPhase == .loading { await model.loadBindings() } }
    }

    private var intro: String {
        let d = model.defaultChain.map { "the default chain, \($0.name)" } ?? "the default chain"
        return "Pick the order of accounts each AI session draws from. One with none uses \(d)."
    }

    @ViewBuilder private var content: some View {
        if model.api == nil {
            CoreStateCard(
                symbol: "wifi.slash", title: "Not connected to a Core",
                line: "AI sessions and their chains come from your Core. Connect this Mac to one first.")
        } else if !model.isAdmin {
            CoreStateCard(
                symbol: "lock", title: "This Mac can only look",
                line: "Choosing a chain for an AI session needs a Mac you allowed to manage the Core.")
        } else {
            switch model.bindingsPhase {
            case .loading: skeleton
            case .failed(let why):
                CoreStateCard(
                    symbol: "exclamationmark.triangle", title: "Couldn't load the AI sessions",
                    line: "\(why) Nothing was changed.",
                    primary: CoreAction("Try again") { model.retryBindings() })
            case .ready: ready
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in CoreSkeleton(coreShape(Radius.cardMac)).frame(height: 52) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the AI sessions")
    }

    @ViewBuilder private var ready: some View {
        if model.bindingsReadOnly {
            CoreNotice(
                symbol: "lock", title: "This Mac can only look",
                text: "Changes need a Mac you allowed to manage the Core.")
        }
        if model.chains.isEmpty {
            CoreStateCard(
                symbol: "link", title: "No chains yet",
                line: "A chain says which accounts a session tries, in order. Make one in Accounts first.",
                primary: CoreAction("Open Accounts, Chains") { openChains() })
        } else {
            let agents = model.knownAgents
            if agents.isEmpty {
                CoreStateCard(
                    symbol: "sparkles", title: "No order of its own yet",
                    line: "Every AI session uses the default order. Bind one below to give it another.")
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(agents, id: \.self) { row($0) }
                }
            }
            addRow
            HStack(spacing: Space.s2) {
                Text("Chains are made in Accounts.").coreFont(size: MacTextSize.meta).foregroundStyle(
                    palette.text2)
                Button("Open Accounts, Chains") { openChains() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
    }

    private func row(_ agent: String) -> some View {
        let bound = model.chain(of: agent)
        let busy = model.bindingBusy == agent
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Image(systemName: "sparkles").foregroundStyle(palette.text2).frame(width: Space.s4)
                    .accessibilityHidden(true)
                Text(agent).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    .truncationMode(.middle).help(agent).layoutPriority(1)
                Spacer(minLength: Space.s2)
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { bound?.id ?? 0 },
                        set: { id in
                            if let c = model.chains.first(where: { $0.id == id }) {
                                Task { await model.bind(agent, to: c) }
                            }
                        }),
                    options: (bound == nil ? [CoreSelectOption(Int64(0), defaultLabel)] : [])
                        + model.chains.map { CoreSelectOption($0.id, $0.name, note: $0.isDefault ? "default" : nil) }
                )
                .frame(width: Space.s8 * 8)
                .disabled(busy || model.bindingsReadOnly)
                .accessibilityLabel("Chain for \(agent)")
                Button("Unbind") { model.confirmUnbind(agent) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(bound == nil || busy || model.bindingsReadOnly)
                    .opacity(bound == nil ? 0 : 1)
                    .accessibilityHidden(bound == nil)
            }
            if let n = model.bindingNotices[agent] { NoticeBanner(notice: n) }
        }
        .padding(Space.s3)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-chain-\(agent)")
    }

    private var defaultLabel: String { "Default chain" + (model.defaultChain.map { " · \($0.name)" } ?? "") }

    private var addRow: some View {
        let id = newAgent.trimmingCharacters(in: .whitespaces)
        let valid = AgentsModel.validAgent(id)
        let chain = model.chains.first { $0.id == newChain } ?? model.defaultChain
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("Bind another AI session").coreFont(size: MacTextSize.headline, weight: .semibold)
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreTextField(
                    "AI session id", placeholder: "AI session id, such as atlas", text: $newAgent,
                    error: id.isEmpty || valid ? nil : AgentsModel.agentIDRule, mono: true
                ) { add(id, chain) }
                .disabled(model.bindingsReadOnly)
                CoreSelect(
                    "Chain", selection: Binding(get: { chain?.id ?? 0 }, set: { newChain = $0 }),
                    options: model.chains.map { CoreSelectOption($0.id, $0.name, note: $0.isDefault ? "default" : nil) }
                )
                .frame(width: Space.s8 * 8)
                Button("Bind AI session") { add(id, chain) }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: model.bindingBusy == id))
                    .disabled(!valid || chain == nil || model.bindingBusy != nil || model.bindingsReadOnly)
                    .frame(minHeight: MacSize.controlLg)
            }
            if let n = model.bindingNotices[id], !id.isEmpty, !model.knownAgents.contains(id) {
                NoticeBanner(notice: n)
            }
        }
    }

    private func add(_ id: String, _ chain: ChainOption?) {
        guard let chain, AgentsModel.validAgent(id) else { return }
        Task { if await model.bind(id, to: chain) { newAgent = "" } }
    }

    private func openChains() {
        model.shell.overlay = nil
        model.shell.launcher.entry("accounts-chains")?.run()
    }
}
