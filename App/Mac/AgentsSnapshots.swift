#if DEBUG
import AppKit
import Agents
import Accounts
import Pairing
import Shell
import SwiftUI

/// Debug only. `CORE_AGENTS_SNAPSHOT=<dir>` (with `CORE_DEMO=1`, the prototype's agents world) walks every agents screen and state
/// by setting the app's own state, and captures its own window. No key events, nothing leaves the app.
@MainActor
enum AgentsSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad" }) else {
            return log("no main window")
        }
        let shell = app.shell
        let a = app.agents
        a.debugDropHost()
        for item in shell.bell.items where !item.id.hasPrefix("agents.") { shell.bell.remove(item.id) }
        for _ in 0..<100 where a.sessions.items.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        a.debugSeedBurn()
        func id(_ n: Int) -> String { String(format: "as_01JC4X7Q3MZ8N5V2K9R%03d", n) }
        var n = 0
        func shot(_ name: String, wait: Double = 1.2) async {
            try? await Task.sleep(for: .seconds(wait))
            n += 1
            let file = "\(dir)/\(String(format: "%02d", n))-\(name)-\(theme)-app.png"
            log("shot \(n) \(name) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        func only(_ open: () -> Void) {
            shell.closeAllPanes()
            shell.overlay = nil
            shell.bellOpen = false
            shell.closeDialog()
            open()
        }
        func list(_ mode: String, _ name: String) async {
            a.debugList(mode)
            only { a.openList() }
            await shot(name)
            a.debugList("normal")
        }
        a.debugPermission("allowed")
        log("key=\(window.isKeyWindow) fr=\(String(describing: window.firstResponder))")

        // The list, in each state the prototype shows.
        only { a.openList() }
        await shot("list-normal")
        a.filter = .needsYou
        await shot("list-needs-you")
        a.filter = .active
        await shot("list-active")
        a.filter = .ended
        await shot("list-ended")
        a.filter = .all
        await list("loading", "list-loading")
        await list("empty", "list-empty")
        await list("failed", "list-error")
        a.debugLink("reconnecting")
        await shot("list-reconnecting")
        a.debugLink("live")
        a.debugPermission("notAsked")
        await shot("list-notification-ask")
        a.debugPermission("allowed")

        // Sessions: one pane for every state.
        for (n, name) in [
            (1, "waiting"), (4, "starting"), (5, "interrupted"), (11, "lost"), (6, "ended-succeeded"),
            (9, "ended-failed"),
            (10, "ended-cancelled"), (8, "ended-token-cap"), (7, "ended-stalled"),
        ] {
            only { a.openSession(id(n)) }
            await shot("session-\(name)")
        }
        // Where the scheduler put a session (admin only), and a budget stop.
        let steps = ["claude · sonnet", "codex · default model", "claude · opus"]
        let accounts: [Int64: String] = [1: "claude-api-metered", 2: "claude-api-batch"]
        let run = id(2)
        let route = SessionRoute(
            agent: "atlas", chainID: 1, chainPos: 1, steps: steps, account: 1, repicked: 1,
            upstreamClass: "rate_limited",
            run: run, attempt: 1, failoverOf: id(12))
        let first = AgentSessionInfo(
            id: id(12), runner: "d_ora", harness: "claude", state: .ended, outcome: .cancelled,
            createdAt: Date().addingTimeInterval(-1500), updatedAt: Date().addingTimeInterval(-600),
            route: SessionRoute(
                chainID: 1, chainPos: 0, steps: steps, account: 2, run: run, attempt: 0, failedOverTo: id(2),
                failoverClass: "rate_limited"))
        let here = AgentSessionInfo(
            id: id(2), runner: "d_ora", harness: "claude", state: .running, createdAt: Date(), updatedAt: Date(),
            route: route)
        let spend = SessionLedger(
            costMicros: 1_240_000, tokens: 152_000, unpriced: false, account: "claude-api-metered",
            maxUSDMicros: 5_000_000)
        await a.debugRoute(id(2), route: route, attempts: [first, here], accounts: accounts, ledger: spend)
        only { a.openSession(id(2)) }
        await shot("route-moved-attempts")
        await a.debugRoute(id(2), route: nil)
        let waiting = SessionRoute(
            agent: "atlas", chainID: 1, chainPos: 0, steps: steps,
            waiting: SessionWaiting(
                since: Date().addingTimeInterval(-420), until: Date().addingTimeInterval(1800),
                why: "every account the chain can use is cooling, limited or at its cap"), run: id(4), attempt: 0)
        await a.debugRoute(id(4), route: waiting)
        only { a.openSession(id(4)) }
        await shot("route-waiting")
        await a.debugRoute(id(4), route: nil)
        let noAccount = SessionRoute(
            chainID: 1, chainPos: 2, steps: steps, account: 2, run: id(9), attempt: 3, failoverOf: id(12),
            ended: FailoverEnd(
                result: "ended", why: "no account is available",
                reasons: ["entry 1: cooling until 14:00", "entry 2: at its cap", "entry 3: budget reached"]))
        await a.debugRoute(id(9), route: noAccount, accounts: accounts)
        only { a.openSession(id(9)) }
        await shot("route-no-account-left")
        await a.debugRoute(id(9), route: nil)
        let capped = SessionLedger(
            costMicros: 5_000_000, tokens: 410_000, unpriced: false, account: "claude-api-metered",
            maxUSDMicros: 5_000_000)
        await a.debugRoute(
            id(7), route: nil, ledger: capped, ended: (.cancelled, "The account's budget ran out"))
        only { a.openSession(id(7)) }
        await shot("ended-budget")
        // A device that is not an admin: the same running session with no chain, account or health.
        only { a.openSession(id(3)) }
        await shot("route-none-not-admin")

        // Both panes side by side, as the workspace shows them.
        only {
            a.openList()
            a.openSession(id(1))
        }
        await shot("workspace-list-and-session")
        a.debugLink("reconnecting")
        only { a.openSession(id(1)) }
        await shot("session-reconnecting")
        a.debugLink("live")

        // Approval card states in a session.
        only { a.openSession(id(1)) }
        if let r = a.debugFirstPending(session: id(1)) {
            a.debugNotice(
                r.id, title: "Cancelled, nothing was done.", detail: "Try again when you are ready.",
                symbol: "hand.raised", tone: "queue")
            await shot("approval-touchid-cancelled")
            a.debugNotice(
                r.id, title: "Touch ID didn't match. Nothing was done.",
                detail: "The Secure Enclave could not sign the request. Try again.", symbol: "exclamationmark.triangle")
            await shot("approval-touchid-failed")
            a.debugNotice(
                r.id, title: "Approving did not go through.", detail: "no such request waits",
                symbol: "exclamationmark.triangle")
            await shot("approval-refused")
            a.debugNotice(r.id, title: "", detail: "", symbol: "")
        }
        a.debugSessionNotice(id(1), title: "Sending did not go through.", detail: "Touch ID did not match.")
        await shot("session-send-failed")
        a.debugSessionNotice(id(1), title: "", detail: "")
        // Decide: one approved, one denied, one expired.
        if let r = a.debugFirstPending(session: id(1)) { await a.decide(r, approved: true) }
        await shot("approval-approved")
        if let r = a.debugFirstPending(session: id(3)) { await a.decide(r, approved: false) }
        only { a.openSession(id(3)) }
        await shot("approval-denied")
        await a.debugExpired(session: id(4))
        only { a.openSession(id(4)) }
        await shot("approval-expired")

        // The inbox, the bell, a new approval arriving.
        a.openInbox()
        await shot("inbox")
        shell.closeDialog()
        a.debugList("normal")
        await a.debugArrive(session: id(4))
        shell.bellOpen = true
        await shot("bell-approvals")
        shell.bellOpen = false

        // New session.
        a.openNewSession()
        await shot("new-session")
        // New session from a chain, an agent, and a busy runner (admin only: a device with no chains sees none of this).
        a.debugChains([
            ChainOption(id: 1, name: "daily", isDefault: true, steps: ["claude · sonnet", "codex · default model"]),
            ChainOption(id: 2, name: "careful", isDefault: false, steps: ["claude · opus"]),
        ])
        a.debugAgents(["atlas", "orion", "scout"])
        only { a.openNewSession() }
        await shot("quick-session-default-chain")
        only { a.openNewSession(advanced: true) }
        await shot("new-session-advanced")
        for source in ["chain", "agent", "busy"] {
            a.debugSource = source
            shell.closeDialog()
            try? await Task.sleep(for: .milliseconds(500))
            only { a.openNewSession(advanced: true) }
            await shot("new-session-\(source)")
        }
        a.debugSource = nil
        a.debugChains([])
        a.debugAgents([])
        shell.closeDialog()
        shell.toggleLauncher()
        await shot("launcher")
        shell.launcherOpen = false

        // Settings, Notifications.
        for (p, name) in [("notAsked", "not-asked"), ("denied", "denied"), ("allowed", "allowed")] {
            a.debugPermission(p)
            shell.settings.selected = "notifications"
            shell.open(.settings)
            await shot("settings-notifications-\(name)")
            shell.overlay = nil
        }
        // An admin device: the account tiles, and the bell telling account news in plain words.
        a.isAdmin = true
        a.debugPermission("allowed")
        shell.settings.selected = "notifications"
        shell.open(.settings)
        await shot("settings-notifications-admin")
        shell.overlay = nil
        let accountsDemo = app.debugAccountsDemo()
        await accountsDemo.show(AccountsDemo.scenes[0])
        let later = ISO8601DateFormatter().string(from: Date().addingTimeInterval(1_800))
        app.accountNotice("account.limited", ["account": "1", "class": "rate_limited", "until": later])
        app.accountNotice(
            "account.failover", ["run": "r1", "from_account": "1", "to_account": "2", "to_session": "as_2", "hop": "1"])
        app.accountNotice("account.health", ["account": "2", "reason": "upstream_errors"])
        app.accountNotice("account.expired", ["account": "2", "reason": "auth"])
        app.accountNotice("alarm.raised", ["alarm": "failover_storm", "user": "1"])
        shell.bellOpen = true
        await shot("bell-accounts")
        shell.bellOpen = false
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution])
        else { return false }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
