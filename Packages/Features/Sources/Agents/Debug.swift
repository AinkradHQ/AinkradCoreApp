#if DEBUG
import CoreUI
import Foundation

/// Debug only: puts the module in a named state for the self-snapshot walk (no keys sent, nothing leaves the app).
extension AgentsModel {
    public func debugDropHost() { host = nil }
    public func debugOpenRows() { EntryRow.openAtStart = true }

    public func debugChains(_ list: [ChainOption]) {
        debugChainList = list.isEmpty ? nil : list
        chains = list
    }

    public func debugAgents(_ names: [String]) {
        (api as? FakeAgentsAPI)?.agentList = names
        agentNames = names
    }

    /// Settings, Agents and chains in one named state: ready, empty, loading, failed, readonly, nochains, notadmin, refused,
    /// unbind (the confirm sheet). Sample chains and agents; long and non-Latin names are in `ready` on purpose.
    public func debugBindings(_ mode: String) async {
        guard let fake = api as? FakeAgentsAPI else { return }
        debugFreezeBindings = false
        isAdmin = mode != "notadmin"
        bindingsReadOnly = mode == "readonly"
        bindingNotices = [:]
        shell.sheet = nil
        let long = "release-train-nightly-integration-agent:eu-west-1.canary.0042"
        let chainsList = [
            ChainOption(id: 1, name: "daily", isDefault: true, steps: ["claude · sonnet", "codex · default model"]),
            ChainOption(id: 2, name: "careful", isDefault: false, steps: ["claude · opus"]),
            ChainOption(id: 3, name: "سلسلة الصباح الطويلة جدا للاختبار", isDefault: false, steps: ["claude · haiku"]),
        ]
        debugChains(mode == "nochains" ? [] : chainsList)
        fake.chainList = chains
        fake.bindingList =
            mode == "empty"
            ? []
            : [
                AgentBinding(agent: "atlas", chain: 2), AgentBinding(agent: "orion", chain: 1),
                AgentBinding(agent: long, chain: 3),
            ]
        fake.agentList = fake.bindingList.map(\.agent)
        agentNames = fake.agentList
        bindings = fake.bindingList
        bindingsPhase = .ready
        switch mode {
        case "loading":
            debugFreezeBindings = true
            bindingsPhase = .loading
        case "failed":
            debugFreezeBindings = true
            bindingsPhase = .failed("The Core did not answer.")
        case "refused":
            bindingNotices["atlas"] = InlineNotice(
                title: "Binding did not go through.", detail: "The Core refused: that chain no longer exists.")
        case "unbind": confirmUnbind("atlas")
        default: break
        }
    }

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

    /// A session as the scheduler places it (or, with a nil route, as a device that is not an admin sees it).
    public func debugRoute(
        _ id: String, route: SessionRoute?, attempts list: [AgentSessionInfo] = [], accounts: [Int64: String] = [:],
        ledger: SessionLedger? = nil, ended: (SessionOutcome, String?)? = nil
    ) async {
        (api as? FakeAgentsAPI)?.update(id) {
            $0.route = route
            if let ended {
                $0.state = .ended
                $0.outcome = ended.0
                $0.outcomeReason = ended.1
                $0.endedAt = Date().addingTimeInterval(-90)
            }
        }
        await refreshSession(id)
        for (k, v) in accounts { accountNames[k] = v }
        if let run = route?.run {
            attempts[run] = list
            (api as? FakeAgentsAPI)?.runAttempts[run] = list
        }
        ledgers[id] = ledger
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

    /// Code Mode on a running session: a search, three scripts (done, done with console lines, refused) and a Core-held write
    /// waiting for you. Made-up names only.
    public func debugCodeMode(session: String) async {
        guard let fake = api as? FakeAgentsAPI else { return }
        let search = "mcp__ainkrad__ainkrad_search"
        let run = "mcp__ainkrad__ainkrad_run"
        let script = """
            const found = await ainkrad.connections.jira.search_issues({ jql: "project = CP AND assignee = currentUser()" });
            const open = found.issues.filter(i => i.status !== "Done");
            console.log("found " + open.length + " open issues");
            return { open: open.length, first: open[0]?.key };
            """
        let ask = """
            {"summary":"Create the Jira issue “Rate-limit the login endpoint” in project CP","args":{"project":"CP","title":"Rate-limit the login endpoint","description":"Add a per-address limit and a short lockout, then document it for the support team.","assignee":"Mira Hollis","api_token":"[redacted]"},"reason":"It creates something in Jira, outside your Core."}
            """
        fake.update(session) {
            $0.state = .running
            $0.project = "customer-portal"
        }
        fake.append(
            session,
            [
                .assistant("I will look for the open issues first, then file the missing one."),
                .toolUse(id: "cm1", name: search, summary: "jira issues assigned to me"),
                .toolResult(
                    id: "cm1", name: search, ok: true, exitCode: nil,
                    output: "connections.jira.search_issues\nconnections.jira.create_issue", durationMs: 240),
                .toolUse(id: "cm2", name: run, summary: script),
                .toolResult(
                    id: "cm2", name: run, ok: true, exitCode: nil,
                    output: "{\"open\":4,\"first\":\"CP-212\"}\nconsole:\nfound 4 open issues\n[1 call, 1180 ms]",
                    durationMs: 1_400),
                .toolUse(
                    id: "cm3", name: run,
                    summary: "await ainkrad.brainAiPropose({ room: \"portal\", title: \"Login limits\" })"),
                .toolResult(
                    id: "cm3", name: run, ok: false, exitCode: nil,
                    output: "error: a call was turned down (line 1) [approval_denied]\n[1 call, 640 ms]",
                    durationMs: 900),
                .toolUse(
                    id: "cm4", name: run,
                    summary: "for (const i of ids) await ainkrad.connections.jira.get_issue({ key: i })"),
                .toolResult(
                    id: "cm4", name: run, ok: false, exitCode: nil,
                    output: "error: the script made too many calls (line 1) [too_many_calls]\n[100 calls, 8210 ms]",
                    durationMs: 8_300),
                .assistant("Now I will file the issue. That reaches Jira, so it needs your approval."),
            ], at: Date().addingTimeInterval(-400))
        // The Core holds this one itself: it is listed by the approvals route, not written in the transcript.
        fake.held[session] = [
            CoreApproval(
                id: "cm_k3x9", tool: "ainkrad.connections.jira.create_issue", input: ask,
                requestedAt: Date().addingTimeInterval(-60), expiresAt: Date().addingTimeInterval(840))
        ]
        await apply(AgentEvent(kind: "agent.approval_requested", session: session))
        await refreshSession(session)
        await store(session).refresh(fake, knownLast: 0)
        await loadHeld(session)
        syncDerived()
    }
}
#endif
