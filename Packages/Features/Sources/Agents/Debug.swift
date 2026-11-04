#if DEBUG
import Foundation

/// Debug only: puts the module in a named state for the self-snapshot walk (no keys sent, nothing leaves the app).
extension AgentsModel {
    public func debugDropHost() { host = nil }

    /// A believable climb to each session's token total, so the burn charts have samples in the demo.
    public func debugSeedBurn() {
        for (i, s) in sessions.items.enumerated() {
            guard let total = s.usage?.tokens, total > 0 else { continue }
            var v = 0.0
            let steps = (0..<24).map { k in Double(((k * 7 + i * 5) % 9) + 1) }
            let sum = steps.reduce(0, +)
            sessions.debugSeedBurn(
                s.id,
                steps.map { step in
                    v += step / sum * Double(total)
                    return v
                })
        }
    }

    public func debugList(_ mode: String) {
        switch mode {
        case "loading": sessions.debugSet(load: .loading)
        case "empty":
            held = sessions.items
            sessions.debugSet(load: .ready, items: [])
        case "failed": sessions.debugSet(load: .failed("The connection was refused."))
        default: sessions.debugSet(load: .ready, items: held.isEmpty ? nil : held)
        }
    }

    public func debugLink(_ l: String) {
        link = l == "reconnecting" ? .reconnecting : l == "ended" ? .ended("This Mac was revoked.") : .live
    }

    public func debugPermission(_ p: String) {
        notifierPermission = p == "denied" ? .denied : p == "allowed" ? .allowed : .notAsked
        askedAboutNotifications = false
    }

    public func debugNotice(_ request: String, title: String, detail: String, symbol: String, tone: String = "warn") {
        if title.isEmpty {
            approvalNotices[request] = nil
            return
        }
        approvalNotices[request] = InlineNotice(
            title: title, detail: detail, symbol: symbol, tone: tone == "queue" ? .queue : .warn)
    }

    public func debugSessionNotice(_ id: String, title: String, detail: String) {
        notices[id] = title.isEmpty ? nil : InlineNotice(title: title, detail: detail)
    }

    public func debugPendingIDs() -> [String] { pending.map(\.id) }
    public func debugFirstPending(session: String? = nil) -> ApprovalRequest? {
        pending.first { session == nil || $0.session == session }
    }
    public func debugSessionID(at i: Int) -> String? { sessions.items.indices.contains(i) ? sessions.items[i].id : nil }
    public func debugIDs(prefix suffix: String) -> String? { sessions.items.first { $0.id.hasSuffix(suffix) }?.id }

    /// A request that nobody answered in time.
    public func debugExpired(session: String) async {
        guard let fake = api as? FakeAgentsAPI else { return }
        fake.append(
            session,
            [
                .approvalRequest(
                    id: "req_old", tool: "Bash", input: "rm -rf node_modules && pnpm install", timeoutSecs: 60)
            ], at: Date().addingTimeInterval(-300))
        await refreshSession(session)
        await store(session).refresh(fake, knownLast: 0)
        syncDerived()
    }

    /// "New approval arrives": a running session asks for a tool.
    public func debugArrive(session: String) async {
        guard let fake = api as? FakeAgentsAPI else { return }
        fake.update(session) { $0.state = .running }
        fake.append(
            session,
            [
                .approvalRequest(
                    id: "req_new\(Int.random(in: 0...9999))", tool: "Bash",
                    input: "rm -rf node_modules && pnpm install", timeoutSecs: 300)
            ])
        await apply(AgentEvent(kind: "agent.approval_requested", session: session))
    }
}
#endif
