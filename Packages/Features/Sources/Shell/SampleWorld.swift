#if DEBUG
import CoreUI
import SwiftUI

/// Debug and preview only: the sample world the shell runs on until the networking lane lands. No fake networking, no persistence.
/// Names follow the prototype's `data.js` (Home Core, mac-studio / linux-01 / oracle-arm, claude-code / codex).
extension HomeSnapshot {
    /// A steady load line ending at `last`, with a little deterministic wobble.
    static func series(_ last: Double, _ wobble: Double, _ seed: Double) -> [Double] {
        (0..<24).map { i in i == 23 ? last : max(0, last + wobble * sin(Double(i) * 0.9 + seed)) }
    }

    public static let sample = HomeSnapshot(
        greetingName: "Sam", coreName: "Home Core",
        machines: [
            Machine(id: "mac-studio", os: "macOS 27", online: true, slots: 4, used: 2, load: series(0.19, 0.04, 1)),
            Machine(id: "linux-01", os: "Ubuntu 26.04", online: true, slots: 2, used: 0, load: series(0.15, 0.03, 2)),
            Machine(
                id: "home-server", os: "Ubuntu 26.04 (arm64)", online: true, slots: 2, used: 1,
                load: series(0.10, 0.03, 3)),
        ],
        running: [
            Run(id: "s1", tool: "claude-code", name: "Login rate limit", minutes: 38),
            Run(id: "s4", tool: "claude-code", name: "Checkout plan review", minutes: 27),
        ],
        events: [
            Event(
                id: "e1", text: "Claude wants to push feat/login-rate-limit", source: "mac-studio", minutesAgo: 1,
                symbol: "lock.shield"),
            Event(
                id: "e2", text: "cargo test passed · 412 tests", source: "mac-studio", minutesAgo: 3,
                symbol: "checkmark"),
        ],
        board: Board(todo: 2, doing: 2, review: 2, blocked: 1, done: 3), loadSampleSeconds: 3, spendToday: 18.60,
        monthTokensUsed: 0.77, spendByDay: [3.1, 5.4, 2.2, 6.8, 4.0, 1.2, 3.2, 18.6], monthSpend: 142.4)
}

@MainActor
public enum SampleWorld {
    public static func install(into shell: ShellModel) {
        shell.home = .sample
        if !shell.profile.hasName { shell.profile.set("Sam") }
        for e in launcherEntries(shell) { shell.launcher.register(e) }
        shell.launcher.recents = ["core", "agents.list", "terminals"]
        approvals(shell)
        shell.bell.add(
            BellItem(
                id: "alarm-backup", kind: .alarm, title: "Backup age 31 h, limit 26 h", sub: "alarm.raised · Home Core",
                time: "2 min",
                actions: [BellAction("Open Ops", primary: true) { shell.showToast("Sample: Ops opens here.") }]))
        shell.bell.add(
            BellItem(
                id: "runner-cooling", kind: .runner, title: "codex-plus is cooling down",
                sub: "A session moved to codex-api and restarted", time: "now"))
    }

    static func approvals(_ shell: ShellModel) {
        let rows = [
            (
                "Claude wants to push feat/login-rate-limit",
                "mac-studio · needs Touch ID · expires in 5 min", "now"
            ),
            ("Claude wants to read GH_TOKEN", "home-server · needs Touch ID · expires in 5 min", "2 min"),
            ("codex wants to run cargo add prometheus-client", "linux-01 · needs Touch ID · expires in 5 min", "4 min"),
        ]
        for (i, r) in rows.enumerated() { shell.bell.add(approval(shell, id: "agents.appr-\(i)", r.0, r.1, r.2)) }
    }

    static func approval(_ shell: ShellModel, id: String, _ title: String, _ sub: String, _ time: String) -> BellItem {
        BellItem(
            id: id, kind: .approval, title: title, sub: sub, time: time,
            actions: [
                BellAction("Deny") {
                    shell.bell.remove(id)
                    shell.showToast("Denied.")
                },
                BellAction("Approve", primary: true) {
                    shell.bell.remove(id)
                    shell.showToast("Approved (sample).") { shell.bell.add(approval(shell, id: id, title, sub, time)) }
                },
            ])
    }

    static func launcherEntries(_ shell: ShellModel) -> [LauncherEntry] {
        func pane(_ id: String, _ title: String, _ sub: String, _ symbol: String, wide: Bool = false) -> LauncherEntry {
            LauncherEntry(id: id, title: title, sub: sub, symbol: symbol) { shell.openPane(samplePane(id, shell)) }
        }
        func action(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ run: @escaping @MainActor () -> Void
        )
            -> LauncherEntry
        { LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, isAction: true, run: run) }
        func sample(_ title: String) -> @MainActor () -> Void {
            {
                shell.presentSheet(
                    title: title, message: "Sample data only: this starts nothing.",
                    actions: [ShellSheetAction("OK", primary: true)])
            }
        }
        return [
            pane("core", "Accounts", "Accounts, pools, budgets and costs", "creditcard"),
            pane("terminals", "Terminals", "Your terminals", "terminal"),
            pane("runners", "Runners", "machines and their slots", "server.rack"),
            action(
                "new-terminal", "New terminal", "Open a shell on a runner · needs Touch ID", "terminal",
                sample("New terminal")),
            action("add-device", "Add device", "create a one-time pairing code", "plus", sample("Add device")),
        ]
    }

    public static func samplePane(_ id: String, _ shell: ShellModel) -> PaneSpec {
        var spec = samplePaneBody(id, shell)
        // The tab carries the app's name, as the real panes do.
        spec.tab = ["agents": "AI Sessions", "terminals": "Terminals", "runners": "Runners", "core": "Accounts"][id]
        return spec
    }

    private static func samplePaneBody(_ id: String, _ shell: ShellModel) -> PaneSpec {
        switch id {
        case "agents":
            PaneSpec(
                id: id, title: "AI Sessions", sub: "Home Core", symbol: "sparkles",
                chip: PaneChip("Waiting on you", tone: .warn, symbol: "hourglass")
            ) {
                SampleList(
                    rows: [
                        ("Login rate limit", "claude-code · mac-studio", SessionState.running),
                        ("Checkout plan review", "claude-code · home-server", .running),
                        ("Hoard test fixtures", "claude-code · mac-studio", .starting),
                        ("E2-12 notifications", "codex · linux-01", .ended),
                    ])
            }
        case "terminals":
            PaneSpec(
                id: id, title: "Terminals", sub: "Rune", symbol: "terminal",
                chip: PaneChip("Home Core", tone: .queue, symbol: "server.rack")
            ) {
                SampleList(
                    rows: [
                        ("zsh", "~/acme-shop · mac-studio", SessionState.running),
                        ("bash", "~/acme-shop/logs · linux-01", .running),
                        ("zsh", "~/acme-shop · mac-studio", .ended),
                    ])
            }
        case "runners":
            PaneSpec(id: id, title: "Runners", sub: "3 machines", symbol: "server.rack") {
                SampleList(
                    rows: [
                        ("mac-studio", "macOS 27 · 2 of 4 slots", SessionState.running),
                        ("linux-01", "Ubuntu 26.04 · idle", .running),
                        ("home-server", "Ubuntu 26.04 (arm64) · 1 of 2 slots", .running),
                    ])
            }
        case "citadel":
            PaneSpec(id: id, title: "Citadel", sub: "Ainkrad", symbol: "building.columns", minWidth: 560) {
                SampleList(
                    rows: [
                        ("Board", "9 issues in the sprint", SessionState.running),
                        ("Runs", "2 running", .running),
                    ])
            }
        default:
            PaneSpec(id: id, title: "Accounts", sub: "Home Core", symbol: "creditcard", minWidth: 560) {
                SampleList(
                    rows: [
                        ("Accounts", "3 providers, all ready", SessionState.running),
                        ("Budgets", "77% of month tokens", .running),
                        ("Ledger", "$18.60 today", .running),
                    ])
            }
        }
    }
}

private struct SampleList: View {
    let rows: [(String, String, SessionState)]
    var body: some View {
        ScrollView {
            VStack(spacing: Space.s2) {
                ForEach(rows, id: \.0) { r in
                    CoreRow(r.0, subtitle: r.1) { StateBadge(r.2) }
                }
                Text("Sample data").coreFont(size: MacTextSize.meta).padding(.top, Space.s2)
            }
            .padding(Space.s3)
        }
    }
}

/// Debug ▸ Demo: states that need a backend to change, in place of the prototype's demo strip.
public struct DemoCommands: Commands {
    let shell: ShellModel
    public init(shell: ShellModel) { self.shell = shell }
    public var body: some Commands {
        CommandMenu("Demo") {
            Button("Add Approval to Bell") {
                shell.bell.add(
                    SampleWorld.approval(
                        shell, id: "appr-\(shell.bell.count)-\(Int.random(in: 0..<999))",
                        "Claude wants to push feat/demo", "mac-studio · needs Touch ID", "now"))
            }
            Button("Clear Bell") { shell.bell.removeAll() }
            Button("Reset Bell") {
                shell.bell.removeAll()
                SampleWorld.install(into: shell)
            }
            Divider()
            ForEach(["agents", "terminals", "runners", "core", "citadel"], id: \.self) { id in
                Button("Open \(id.capitalized) Pane") { shell.openPane(SampleWorld.samplePane(id, shell)) }
            }
            Button("Close All Panes") { shell.closeAllPanes() }
            Divider()
            Button("Toast with Undo") { shell.showToast("Sample toast.") {} }
            Button("Confirm Sheet") {
                shell.presentSheet(
                    title: "Remove device?", message: "Sample sheet.",
                    actions: [ShellSheetAction("Cancel"), ShellSheetAction("Remove", primary: true)])
            }
        }
    }
}
#endif
