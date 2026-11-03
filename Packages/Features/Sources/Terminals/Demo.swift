#if DEBUG
import CoreKit
import Foundation
import Shell

/// Debug only: every terminal state of the prototype, on sample data and a stand-in service, for screenshots and for the
/// reviewer to click through. Nothing here reaches a Core. Runner and terminal names follow the prototype's `data.js`.
@MainActor
public final class TerminalsDemo {
    final class Host: TerminalHost {
        let shell: ShellModel
        var isElevated = true
        var elevationNotice: ElevationNotice?
        init(shell: ShellModel) { self.shell = shell }
        func clearElevationNotice() { elevationNotice = nil }
        func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T
        {
            try await op()
        }
    }

    final class DemoLink: TerminalLink, @unchecked Sendable {
        let opened: TerminalOpened
        let updates: AsyncStream<TerminalUpdate>
        private let feed: AsyncStream<TerminalUpdate>.Continuation
        init(cols: Int, rows: Int, seq: UInt64) {
            opened = TerminalOpened(state: "running", rows: rows, cols: cols, seq: seq)
            var c: AsyncStream<TerminalUpdate>.Continuation!
            updates = AsyncStream { c = $0 }
            feed = c
            feed.yield(.output(Data(TerminalsDemo.screen.utf8)))
        }
        var cursor: UInt64 { 0 }
        var repainted: Bool { false }
        func input(_ bytes: Data) { feed.yield(.output(bytes)) }
        func resize(rows: Int, cols: Int) {}
        func drawn(_ bytes: Int) {}
        func detach() {
            feed.yield(.closed(.detached))
            feed.finish()
        }
    }

    final class Service: TerminalService, @unchecked Sendable {
        var terminalList: [TerminalItem] = []
        var runnerList: [RunnerItem] = []
        var refusal: CoreError?
        func terminals() async throws -> [TerminalItem] { terminalList }
        func terminal(_ id: String) async throws -> TerminalItem {
            guard let t = terminalList.first(where: { $0.id == id }) else { throw CoreError.offline("gone") }
            return t
        }
        func runners() async throws -> [RunnerItem] { runnerList }
        func create(runner: String, program: String?, rows: Int, cols: Int) async throws -> TerminalItem {
            if let refusal { throw refusal }
            return item("t_new", runner: runner, attached: 0)
        }
        func close(_ id: String) async throws -> TerminalItem { try await terminal(id) }
        func signal(_ id: String, _ name: String) async throws {}
        func noop(_ runner: String) async throws -> Int { 31 }
        func attach(_ id: String, after: UInt64) async throws -> any TerminalLink {
            let t = try await terminal(id)
            return DemoLink(cols: t.cols, rows: t.rows, seq: 0)
        }
    }

    nonisolated static let esc = "\u{1b}"
    nonisolated static let screen: String = {
        let p = "\(esc)[38;2;127;184;255m~/AinkradCore\(esc)[0m $ "
        let ok = "\(esc)[38;2;52;211;153mok\(esc)[0m"
        let dim = "\(esc)[38;2;111;129;155m"
        return [
            p + "cargo test -p citadel",
            "\(dim)   Compiling citadel v0.24.0 (crates/citadel)\(esc)[0m",
            "\(dim)    Finished test profile in 31.4s\(esc)[0m",
            "test routes::planning::list_plans ... \(ok)",
            "test scopes::agent_cannot_read_secrets ... \(ok)",
            "test result: \(ok). 412 passed; 0 failed; 38.2s",
            p + "git status",
            "On branch feat/e2-14-citadel-bootstrap",
            "nothing to commit, working tree clean",
            p,
        ].joined(separator: "\r\n")
    }()

    nonisolated static func item(
        _ id: String, runner: String, status: String = "running", attached: Int = 1, code: Int32? = nil,
        signal: String? = nil, orphaned: Bool = false, cols: Int = 86, rows: Int = 34, ageMinutes: Double = 41
    ) -> TerminalItem {
        TerminalItem(
            id: id, runner: runner, status: status, rows: rows, cols: cols, seq: 0, attached: attached,
            orphaned: orphaned, exitCode: code, exitSignal: signal,
            createdAt: Date(timeIntervalSinceNow: -ageMinutes * 60))
    }

    nonisolated static func runner(
        _ id: String, arch: String, load: Int, capacity: Int, avg1: Double, cores: Int, online: Bool = true,
        degraded: Bool = false
    ) -> RunnerItem {
        RunnerItem(
            id: id, name: id, online: online, degraded: degraded, load: load, capacity: capacity, avg1: avg1,
            cores: cores,
            version: "0.24.0", arch: arch, lastSeen: nil,
            drivers: [
                DriverItem(name: "pty", commands: ["pty.open", "pty.attach", "pty.close"], capacity: 16),
                DriverItem(name: "exec", commands: ["noop"], capacity: 4),
            ], isolationTiers: nil)
    }

    let shell: ShellModel
    let service = Service()
    let model: TerminalsModel
    private let host: Host

    public init(shell: ShellModel) {
        self.shell = shell
        host = Host(shell: shell)
        model = TerminalsModel(host: host, service: service)
        reset()
    }

    public static let scenes = [
        "list", "live", "letterbox", "elsewhere", "detached", "orphaned", "exited", "gone", "host-lost",
        "runner-offline",
        "stepup-expired", "reconnecting", "resumed", "snapshot", "attaching", "failed", "runners", "runner-detail",
        "runner-degraded", "runner-offline-detail", "runner-busy", "new-terminal", "new-busy", "new-offline",
        "new-stepup", "end-confirm", "launcher", "bell",
    ]

    func reset() {
        service.refusal = nil
        service.runnerList = [
            Self.runner("mac-studio", arch: "aarch64", load: 2, capacity: 4, avg1: 3.1, cores: 16),
            Self.runner("linux-01", arch: "x86_64", load: 0, capacity: 2, avg1: 1.2, cores: 8),
            Self.runner("oracle-arm", arch: "aarch64", load: 1, capacity: 2, avg1: 0.4, cores: 4),
        ]
        service.terminalList = [
            Self.item("t_1a2b3c4d5e6f7a8b", runner: "mac-studio", attached: 1),
            Self.item("t_2b3c4d5e6f7a8b9c", runner: "linux-01", attached: 1, cols: 64, rows: 24, ageMinutes: 190),
            Self.item(
                "t_3c4d5e6f7a8b9c0d", runner: "oracle-arm", attached: 0, orphaned: true, cols: 80, rows: 24,
                ageMinutes: 1460),
            Self.item(
                "t_4d5e6f7a8b9c0d1e", runner: "mac-studio", status: "exited", attached: 0, code: 0, ageMinutes: 64),
            Self.item("t_5e6f7a8b9c0d1e2f", runner: "oracle-arm", attached: 0, cols: 80, rows: 24, ageMinutes: 980),
            Self.item(
                "t_6f7a8b9c0d1e2f3a", runner: "linux-01", status: "exited", attached: 0, signal: "host_lost", cols: 100,
                rows: 30, ageMinutes: 300),
            Self.item("t_7a8b9c0d1e2f3a4b", runner: "linux-01", status: "reaped", attached: 0, code: 0, ageMinutes: 58),
        ]
        host.elevationNotice = nil
        host.isElevated = true
    }

    private func id(_ n: Int) -> String { service.terminalList[n].id }

    /// Shows one scene: panes are closed first, then what the scene needs is opened.
    public func show(_ scene: String) async {
        shell.closeAllPanes()
        shell.closeDialog()
        shell.closeTopDialog()
        shell.sheet = nil
        shell.launcherOpen = false
        shell.bellOpen = false
        shell.overlay = nil
        reset()
        await model.reload()
        func pane(
            _ i: Int, _ link: Link? = nil, note: ResumeNote? = nil, letterbox: (Int, Int)? = nil, screen: Bool = true
        ) async {
            model.openTerminal(id(i), attach: false)
            let s = model.sessions[id(i)]!
            if screen { s.surface.feed(Data(Self.screen.utf8)) }
            if let letterbox { s.surface.layoutMode(.letterbox(cols: letterbox.0, rows: letterbox.1)) }
            if let link { s.debugForce(link: link, note: note) }
        }
        switch scene {
        case "list":
            model.openList()
            model.selected = id(0)
            await pane(0, .attached(letterbox: false))
            model.openList()
        case "live": await pane(0, .attached(letterbox: false))
        case "letterbox":
            service.terminalList[0].attached = 2
            await model.reload()
            await pane(0, .attached(letterbox: true), letterbox: (64, 24))
        case "elsewhere": await pane(1, Link.none, screen: false)
        case "detached": await pane(4, Link.none, screen: false)
        case "orphaned": await pane(2, Link.none, screen: false)
        case "exited": await pane(3, Link.none)
        case "gone": await pane(6, Link.none, screen: false)
        case "host-lost": await pane(5, Link.none, screen: false)
        case "runner-offline":
            service.runnerList[1].online = false
            await model.reload()
            await pane(1, Link.none, screen: false)
        case "stepup-expired": await pane(0, .stepUp)
        case "reconnecting": await pane(0, .reconnecting)
        case "resumed": await pane(0, .attached(letterbox: false), note: .resumed(from: 4_182_913, to: 4_190_742))
        case "snapshot": await pane(0, .attached(letterbox: false), note: .repainted)
        case "attaching": await pane(0, .attaching)
        case "failed":
            await pane(
                0, .failed(code: "too_many_attaches", message: "Too many clients are attached to this terminal."),
                screen: false)
        case "runners": model.openRunners()
        case "runner-detail": model.openRunners(service.runnerList[0].id)
        case "runner-degraded":
            service.runnerList[2].degraded = true
            await model.reload()
            model.openRunners(service.runnerList[2].id)
        case "runner-offline-detail":
            service.runnerList[1].online = false
            await model.reload()
            model.openRunners(service.runnerList[1].id)
        case "runner-busy":
            service.runnerList[1].avg1 = 36.8
            await model.reload()
            model.openRunners(service.runnerList[1].id)
        case "new-terminal":
            model.openList()
            model.openNew()
        case "new-busy":
            service.runnerList[1].avg1 = 36.8
            await model.reload()
            service.refusal = .http(status: 503, code: "runner_busy", message: "busy")
            model.openList()
            model.openNew(runner: service.runnerList[1].id)
            await model.newTerminal?.submit()
        case "new-offline":
            service.refusal = .http(status: 409, code: "runner_offline", message: "offline")
            model.openList()
            model.openNew(runner: service.runnerList[1].id)
            await model.newTerminal?.submit()
        case "new-stepup":
            host.elevationNotice = ElevationNotice(
                title: "Cancelled, nothing was opened.",
                detail: "Your edit is still here. Try again when you are ready.",
                symbol: "hand.raised", tone: .queue)
            model.openList()
            model.openNew()
        case "end-confirm":
            await pane(0, .attached(letterbox: false))
            shell.presentSheet(
                title: "End this terminal?",
                message:
                    "The terminal on mac-studio and everything running in it will stop. Closing the pane only detaches. This needs Touch ID.",
                actions: [ShellSheetAction("Keep it"), ShellSheetAction("End terminal")])
        case "launcher":
            model.openList()
            shell.launcherOpen = true
        case "bell":
            service.runnerList[1].online = false
            service.runnerList[2].degraded = true
            await model.reload()
            model.openList()
            shell.bellOpen = true
        default: break
        }
    }
}
#endif
