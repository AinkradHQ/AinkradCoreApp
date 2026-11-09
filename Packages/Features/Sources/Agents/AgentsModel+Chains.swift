import CoreKit
import CoreUI
import Foundation
import Shell

/// KAN-475: the Core will take a `pool_id` on a new session (API 1.47 does not). When it lands, the pool chip goes where this
/// is read, in `QuickSessionView` and `NewSessionSheet`, and Accounts, Bindings retires. Until then no pool picker exists.
public enum SessionPoolHook {
    public static let isAvailable = false
}

/// Settings, Agents and chains: which chain each agent draws its accounts from. The chains themselves (their pools and models)
/// are made in Accounts, Chains; agents are bound here, where work starts.
extension AgentsModel {
    /// Agents shown on the page: every one bound, then the ones bound from here before (the Core keeps no list of agents).
    public var knownAgents: [String] {
        let recent = defaults.stringArray(forKey: Self.recentAgentsKey) ?? []
        return Array(NSOrderedSet(array: bindings.map(\.agent) + agentNames + recent)) as? [String] ?? []
    }

    static let recentAgentsKey = "accounts.recentAgents"

    public func chain(of agent: String) -> ChainOption? {
        bindings.first { $0.agent == agent }.flatMap { b in chains.first { $0.id == b.chain } }
    }

    /// The chain a plain start uses: the default one, else the first.
    public var defaultChain: ChainOption? { chains.first { $0.isDefault } ?? chains.first }

    func loadBindings() async {
        guard let api else { return }
        #if DEBUG
        if debugFreezeBindings { return }
        #endif
        do {
            bindings = try await api.bindings()
            bindingsPhase = .ready
        } catch {
            bindingsPhase = .failed(Self.words(error))
        }
    }

    public func retryBindings() {
        bindingsPhase = .loading
        Task { await loadBindings() }
    }

    static func words(_ error: any Error) -> String {
        CoreError.unwrapping(error)?.localizedDescription ?? "The Core did not answer."
    }

    /// Binds (or moves) an agent. Touch ID first. True when it went through.
    @discardableResult
    public func bind(_ agent: String, to chain: ChainOption) async -> Bool {
        let a = agent.trimmingCharacters(in: .whitespaces)
        guard let api, Self.validAgent(a), bindingBusy == nil else { return false }
        bindingBusy = a
        bindingNotices[a] = nil
        defer { bindingBusy = nil }
        do {
            try await elevated("Bind \(a) to \(chain.name). Its sessions draw accounts from that chain.") {
                try await api.bind(agent: a, chain: chain.id)
            }
            bindings.removeAll { $0.agent == a }
            bindings.append(AgentBinding(agent: a, chain: chain.id))
            if !agentNames.contains(a) { agentNames.append(a) }
            defaults.set(
                Array(([a] + (defaults.stringArray(forKey: Self.recentAgentsKey) ?? []).filter { $0 != a }).prefix(12)),
                forKey: Self.recentAgentsKey)
            shell.showToast("\(a) is bound to \(chain.name)")
            return true
        } catch {
            bindingNotices[a] = failure(error, doing: "Binding")
            return false
        }
    }

    /// Asks first: the agent's sessions then use the default chain.
    public func confirmUnbind(_ agent: String) {
        shell.presentSheet(
            title: "Unbind \(agent)?",
            message:
                "New sessions of \(agent) will use \(defaultChain.map { "the default chain, \($0.name)" } ?? "the default chain"). Running sessions keep the chain they started with.",
            actions: [
                ShellSheetAction("Keep it bound"),
                ShellSheetAction("Unbind", primary: true, destructive: true) { [weak self] in
                    Task { await self?.unbind(agent) }
                },
            ])
    }

    func unbind(_ agent: String) async {
        guard let api, bindingBusy == nil else { return }
        bindingBusy = agent
        bindingNotices[agent] = nil
        defer { bindingBusy = nil }
        do {
            try await elevated("Unbind \(agent). It falls back to the default chain.") {
                try await api.unbind(agent: agent)
            }
            bindings.removeAll { $0.agent == agent }
            shell.showToast("\(agent) is unbound")
        } catch {
            bindingNotices[agent] = failure(error, doing: "Unbinding")
        }
    }

    private func failure(_ error: any Error, doing: String) -> InlineNotice {
        if case .forbiddenScope? = CoreError.unwrapping(error) { bindingsReadOnly = true }
        return Self.notice(error, doing: doing)
    }

    /// The Core's rule for an agent id: 1 to 64 of `[A-Za-z0-9._:-]`.
    public static func validAgent(_ s: String) -> Bool { SessionSource.validAgent(s) }
    public static let agentIDRule = SessionSource.idRule

    /// "Agents and chains" in Settings.
    public func openChainBinding() {
        shell.settings.selected = "agent-chains"
        shell.open(.settings)
    }
}
