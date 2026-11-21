#if DEBUG
import CoreKit
import Foundation
import Shell
import SwiftUI

/// Debug only: every Machines state on made-up machines (Attic box, Harbor mini, Garage pi, a phone and a tablet), for
/// screenshots and for clicking through. Nothing here reaches a Core. The app that owns devices fills in the sign-in pages,
/// This Mac's switch and Add machine through the closures, so those are the real screens.
@MainActor
public final class MachinesDemo {
    final class Host: TerminalHost, RunnerHost {
        let shell: ShellModel
        var isElevated = false
        var elevationNotice: ElevationNotice?
        var thisMacRunnerID: String? = "m_this"
        var devices: [SignInMachine]? = []
        var work: [String: [RunnerWork]] = [:]
        var page: (String, @escaping @MainActor () -> Void) -> AnyView = { _, _ in AnyView(EmptyView()) }
        var mac: () -> AnyView? = { nil }
        var add: (AddMachineStart) -> Void = { _ in }
        init(shell: ShellModel) { self.shell = shell }
        func clearElevationNotice() { elevationNotice = nil }
        func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T
        {
            try await op()
        }
        func agentWork(on runner: String) -> [RunnerWork] { work[runner] ?? [] }
        func openAgent(_ id: String) {}
        func startAgent(on runner: String) {}
        func addMachine(_ start: AddMachineStart) { add(start) }
        func people() -> [RunnerPerson] { [] }
        func renameRunner(_ id: String, to name: String) async -> String? { nil }
        func revokeRunner(_ id: String) async -> String? { nil }
        func signInMachines() -> [SignInMachine]? { devices }
        func signInPage(_ id: String, back: @escaping @MainActor () -> Void) -> AnyView { page(id, back) }
        func thisMacWork() -> AnyView? { mac() }
    }

    public static let scenes = [
        "list", "detail", "offline", "devices", "mac-signs-in", "add", "add-server", "empty", "unreachable",
    ]

    let shell: ShellModel
    let host: Host
    let service = TerminalsDemo.Service()
    public let model: TerminalsModel

    /// `page` draws a sign-in machine's page, `thisMac` This Mac's switch, `add` opens Add machine.
    public init(
        shell: ShellModel, page: @escaping (String, @escaping @MainActor () -> Void) -> AnyView,
        thisMac: @escaping () -> AnyView?, add: @escaping (AddMachineStart) -> Void
    ) {
        self.shell = shell
        host = Host(shell: shell)
        host.page = page
        host.mac = thisMac
        host.add = add
        model = TerminalsModel(host: host, service: service)
    }

    /// The made-up sign-in machines, for the app to seed its devices with (same ids as the rows).
    public static let signIns: [SignInMachine] = [
        SignInMachine(
            id: "d_phone", name: "iPhone", platform: "ios", lastSeen: .now.addingTimeInterval(-5 * 60),
            added: .now.addingTimeInterval(-18 * 86400), scopes: ["read", "approve", "terminal"], isThisMac: false),
        SignInMachine(
            id: "d_tablet", name: "iPad", platform: "ipados", lastSeen: .now.addingTimeInterval(-26 * 3600),
            added: .now.addingTimeInterval(-40 * 86400), scopes: ["read"], isThisMac: false),
        SignInMachine(
            id: "d_studio", name: "Studio laptop", platform: "macos", lastSeen: .now.addingTimeInterval(-3 * 3600),
            added: .now.addingTimeInterval(-9 * 86400), scopes: ["read", "approve", "terminal", "agent"],
            isThisMac: false),
    ]

    private static func machine(
        _ id: String, _ name: String, os: String, pretty: String, cores: Int, used: Int, cap: Int,
        tools: [String: String], online: Bool = true
    ) -> RunnerItem {
        var r = TerminalsDemo.runner(
            id, arch: "aarch64", load: used, capacity: cap, avg1: 0.6, cores: cores, online: online)
        r.name = name
        r.os = os
        r.osPretty = pretty
        r.tools = tools
        r.connectedSince = .now.addingTimeInterval(-3 * 86400 - 3600)
        r.slots = RunnerSlotFacts(agentsUsed: used, agentsCapacity: cap, terminalsUsed: 0, terminalsCapacity: 16)
        r.drivers.append(DriverItem(name: "agent", commands: [], capacity: cap, slots: ["claude": cap]))
        r.policy = RunnerPolicy(terminals: true, agents: true, capacity: cap)
        r.home = "/home/ainkrad/work"
        r.version = "0.10.2"
        return r
    }

    private static func hardware(_ id: String, _ name: String, cpu: Int) -> HardwareItem {
        HardwareItem(
            id: id, name: name, kind: "runner", online: true, degraded: false, pausedUntil: nil, gate: "open", os: nil,
            arch: nil, cores: 8, cpuPct: cpu, memTotalMb: 16384, memFreeMb: 8192, battery: nil, toolchains: [:],
            sessions: 0, jobs: [], jobSlots: 2)
    }

    private func reset() {
        let all = ["claude": "2.1.31", "codex": "0.9.4", "opencode": "1.4.2"]
        var mine = Self.machine(
            "m_this", "This Mac", os: "macos", pretty: "macOS 27", cores: 12, used: 0, cap: 4, tools: all)
        mine.home = "~/.ainkrad-runner/work"
        var attic = Self.machine(
            "m_attic", "Attic box", os: "linux", pretty: "Ubuntu 24.04", cores: 8, used: 1, cap: 4,
            tools: ["claude": "2.1.31", "codex": "0.9.4", "opencode": "1.4.2"])
        attic.slots?.terminalsUsed = 1
        let harbor = Self.machine(
            "m_harbor", "Harbor mini", os: "macos", pretty: "macOS 26", cores: 10, used: 2, cap: 3, tools: all)
        var garage = Self.machine(
            "m_garage", "Garage pi", os: "linux", pretty: "Debian 12", cores: 4, used: 0, cap: 2,
            tools: ["claude": "2.1.31"], online: false)
        let cal = Calendar.current
        garage.lastSeen = cal.date(bySettingHour: 14, minute: 2, second: 0, of: .now) ?? .now
        garage.slots = nil
        service.down = nil
        service.runnerList = [mine, attic, harbor, garage]
        service.terminalList = [
            TerminalsDemo.item("t_attic1", runner: "m_attic", attached: 1, ageMinutes: 25),
            TerminalsDemo.item("t_garage1", runner: "m_garage", attached: 0, ageMinutes: 300),
        ]
        shell.tabNames["terminal-t_attic1"] = "acme-shop"
        shell.tabNames["terminal-t_garage1"] = "logs"
        host.work = [
            "m_attic": [
                RunnerWork(
                    id: "s_1", title: "Fix the login bug", detail: "Claude · started 12 min ago", minutes: 12,
                    tool: "Claude")
            ],
            "m_harbor": [
                RunnerWork(
                    id: "s_2", title: "Write tests for checkout", detail: "Codex · started 40 min ago", minutes: 40,
                    tool: "Codex"),
                RunnerWork(
                    id: "s_3", title: "Tidy the settings screen", detail: "Claude · started 8 min ago", minutes: 8,
                    tool: "Claude"),
            ],
        ]
        host.devices = Self.signIns.filter { $0.id != "d_studio" }
        host.isElevated = false
    }

    /// Shows one scene: panes and dialogs closed first, then Machines as the scene needs it.
    public func show(_ scene: String) async {
        shell.closeAllPanes()
        try? await Task.sleep(for: .milliseconds(450))
        shell.closeDialog()
        shell.closeTopDialog()
        shell.launcherOpen = false
        shell.bellOpen = false
        reset()
        switch scene {
        case "empty":
            service.runnerList = []
            service.terminalList = []
            host.devices = []
        case "unreachable":
            service.down = .http(status: 503, code: "unavailable", message: "Your Core did not answer.")
        case "mac-signs-in":
            host.devices = Self.signIns
        default: break
        }
        await model.reload()
        for (id, name, cpu) in [
            ("m_this", "This Mac", 6), ("m_attic", "Attic box", 38), ("m_harbor", "Harbor mini", 62),
        ] {
            model.hardware[id] = Self.hardware(id, name, cpu: cpu)
        }
        // Antigravity installing on Attic box, as the mockup shows it.
        model.installs["m_attic"] = [
            "agy": ToolInstall(op: "demo", tool: "agy", state: .running, percent: 55, step: "Downloading")
        ]
        switch scene {
        case "detail": model.openMachines("m_attic")
        case "offline": model.openMachines("m_garage")
        case "devices": model.openMachines("d_phone")
        case "mac-signs-in": model.openMachines("d_studio")
        case "add":
            model.openMachines()
            host.addMachine(.pick)
        case "add-server":
            model.openMachines()
            host.addMachine(.server(name: nil))
        default: model.openMachines()
        }
    }
}
#endif
