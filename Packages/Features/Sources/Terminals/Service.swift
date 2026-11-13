import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// A terminal as the Core lists it. Only fields the API has: no `cwd` or `program` yet (KAN-456).
struct TerminalItem: Identifiable, Equatable, Sendable {
    let id: String
    var runner: String
    /// The Core's word: `created`, `running`, `exited`, `reaped`, or one this build does not know (shown raw).
    var status: String
    var rows: Int
    var cols: Int
    var seq: UInt64
    var attached: Int
    /// Running with no client attached: closed once idle past `terminal.idle_secs`.
    var orphaned: Bool
    var exitCode: Int32?
    var exitSignal: String?
    var createdAt: Date?

    var isEnded: Bool { status == "exited" || status == "reaped" }
    var hostLost: Bool { exitSignal == "host_lost" }
}

struct DriverItem: Equatable, Sendable {
    var name: String
    var commands: [String]
    var capacity: Int?
    /// `agent`: how many sessions each harness may run at once. The harnesses named here are the tools found.
    var slots: [String: Int] = [:]
}

/// Whether agents on a runner can use the user's accounts, and why not (`GET /runners` `accounts`).
struct RunnerAccountFacts: Equatable, Sendable {
    var gateway: Bool
    var subscriptionEnv: Bool
    var egressFilter: Bool
    var gatewayReason: String?
    var subscriptionEnvReason: String?
    var egressFilterReason: String?
}

/// Used and capacity per driver; capacity nil means that driver is off.
struct RunnerSlotFacts: Equatable, Sendable {
    var agentsUsed: Int
    var agentsCapacity: Int?
    var terminalsUsed: Int
    var terminalsCapacity: Int?
}

/// What a runner offers now (`GET /runners` `policy`): terminals, AI sessions, and how many sessions at once.
struct RunnerPolicy: Equatable, Sendable {
    var terminals: Bool
    var agents: Bool
    var capacity: Int
}

/// An install of a host tool on a runner, as `runner.tool_install` events report it.
struct ToolInstall: Equatable, Sendable {
    enum State: String, Sendable { case running, done, failed }
    var op: String
    var tool: String
    var state: State
    var percent: Int
    var step: String
    var reason: String?
}

struct RunnerItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var online: Bool
    var degraded: Bool
    var load: Int
    var capacity: Int
    var avg1: Double?
    var cores: Int?
    var version: String?
    var arch: String?
    var lastSeen: Date?
    var drivers: [DriverItem]
    var isolationTiers: [String]?
    // Facts from Core API minor 51: all nil for an old or offline runner.
    var osPretty: String?
    var os: String?
    var sandbox: String?
    var runsAsUser: String?
    var runsAsRoot: Bool?
    var connectedSince: Date?
    var updateAvailable: Bool?
    var builtIn = false
    var accounts: RunnerAccountFacts?
    var slots: RunnerSlotFacts?
    /// Harness name to version, e.g. `claude` to `2.1.318`.
    var tools: [String: String] = [:]
    /// What the runner offers now; nil for an old runner or one that never connected.
    var policy: RunnerPolicy?

    var hasPty: Bool { drivers.contains { $0.name == "pty" } }
    var perCore: Double? { avg1.flatMap { a in cores.flatMap { $0 > 0 ? a / Double($0) : nil } } }
}

/// One live attach, as the session model needs it. `TerminalAttachment` is the real one; tests bring their own.
protocol TerminalLink: Sendable {
    var opened: TerminalOpened { get }
    var updates: AsyncStream<TerminalUpdate> { get }
    var cursor: UInt64 { get }
    var repainted: Bool { get }
    func input(_ bytes: Data)
    func resize(rows: Int, cols: Int)
    func drawn(_ bytes: Int)
    func detach()
}

extension TerminalAttachment: TerminalLink {}
extension LocalTerminalAttachment: TerminalLink {}

/// The Core as the terminal screens use it. `LiveTerminalService` is the only real one.
protocol TerminalService: Sendable {
    func terminals() async throws -> [TerminalItem]
    func terminal(_ id: String) async throws -> TerminalItem
    func runners() async throws -> [RunnerItem]
    func create(runner: String, program: String?, rows: Int, cols: Int) async throws -> TerminalItem
    func close(_ id: String) async throws -> TerminalItem
    func signal(_ id: String, _ name: String) async throws
    /// Milliseconds the runner took to answer an empty round trip.
    func noop(_ runner: String) async throws -> Int
    func attach(_ id: String, after: UInt64) async throws -> any TerminalLink
    /// Attaches to a terminal whose runner is `runner`: directly, when that runner is on this Mac, else through the Core.
    func attach(_ id: String, runner: String?, after: UInt64) async throws -> any TerminalLink
    /// `PUT /runners/{id}/policy` (admin, step-up). `restarting`: the runner restarts to read it.
    func setPolicy(_ runner: String, _ policy: RunnerPolicy) async throws -> (policy: RunnerPolicy, restarting: Bool)
    /// `POST /runners/{id}/tools` (admin, step-up): the id of the install operation.
    func installTool(_ runner: String, tool: String) async throws -> String
}

extension TerminalService {
    func attach(_ id: String, runner: String?, after: UInt64) async throws -> any TerminalLink {
        try await attach(id, after: after)
    }
    func setPolicy(_ runner: String, _ policy: RunnerPolicy) async throws -> (policy: RunnerPolicy, restarting: Bool) {
        (policy, false)
    }
    func installTool(_ runner: String, tool: String) async throws -> String { "op" }
}

struct LiveTerminalService: TerminalService {
    let connection: CoreConnection
    /// The runner on this Mac, if the app runs one (the local path).
    var localRunner: @Sendable () async -> LocalRunner? = { nil }
    private var client: Client { connection.client }

    func terminals() async throws -> [TerminalItem] {
        try await run { try await client.listTerminals().ok.body.json.map(Self.item) }
    }

    func terminal(_ id: String) async throws -> TerminalItem {
        try await run {
            switch try await client.getTerminal(path: .init(id: id)) {
            case .ok(let o): return Self.item(try o.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func runners() async throws -> [RunnerItem] {
        try await run { try await client.listRunners().ok.body.json.map(Self.runner) }
    }

    func create(runner: String, program: String?, rows: Int, cols: Int) async throws -> TerminalItem {
        try await run {
            let body = Components.Schemas.NewTerminal(
                program: program, runner: runner, size: .init(cols: Int32(cols), rows: Int32(rows)))
            switch try await client.createTerminal(body: .json(body)) {
            case .created(let o): return Self.item(try o.body.json)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func close(_ id: String) async throws -> TerminalItem {
        try await run {
            switch try await client.closeTerminal(path: .init(id: id)) {
            case .ok(let o): return Self.item(try o.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func signal(_ id: String, _ name: String) async throws {
        try await run {
            switch try await client.signalTerminal(path: .init(id: id), body: .json(.init(signal: name))) {
            case .noContent: return
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func noop(_ runner: String) async throws -> Int {
        try await run {
            switch try await client.runNoop(path: .init(id: runner)) {
            case .ok(let o):
                let r = try o.body.json
                guard r.ok != false else { throw Self.fail(504, nil) }
                return Int(r.durationMs ?? 0)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func attach(_ id: String, after: UInt64) async throws -> any TerminalLink {
        try await run { try await connection.attachTerminal(id, after: after) }
    }

    func attach(_ id: String, runner: String?, after: UInt64) async throws -> any TerminalLink {
        if let runner, let local = try await attacher.attach(id, runner: runner, after: after) { return local }
        return try await attach(id, after: after)
    }

    /// The local path's decisions, wired to this Core connection.
    private var attacher: LocalAttacher {
        LocalAttacher(
            localRunner: localRunner,
            supported: { await connection.serverSupports(minor: LocalAttacher.localMinor) },
            source: { id in
                LocalGrantSource(
                    grant: { try await self.grantLocal(id) },
                    sign: { try await self.connection.signWithRoutineKey($0) },
                    release: { await self.releaseLocal(id) })
            })
    }

    func grantLocal(_ id: String) async throws -> LocalTerminalGrant {
        try await run {
            switch try await client.grantLocalTerminal(path: .init(id: id)) {
            case .ok(let o):
                let g = try o.body.json
                return LocalTerminalGrant(
                    terminal: g.terminal, runner: g.runner, grant: g.grant, leaseSecs: Int(g.leaseSecs),
                    socket: g.socket)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func releaseLocal(_ id: String) async {
        _ = try? await client.releaseLocalTerminal(path: .init(id: id))
    }

    func setPolicy(_ runner: String, _ policy: RunnerPolicy) async throws -> (policy: RunnerPolicy, restarting: Bool) {
        try await run {
            let body = Components.Schemas.RunnerPolicyBody(
                agentCapacity: Int32(policy.capacity), agents: policy.agents, terminals: policy.terminals)
            switch try await client.setRunnerPolicy(path: .init(id: runner), body: .json(body)) {
            case .ok(let o):
                let r = try o.body.json
                return (r.policy.map(Self.policy) ?? policy, r.restarting ?? false)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func installTool(_ runner: String, tool: String) async throws -> String {
        try await run {
            switch try await client.installRunnerTool(path: .init(id: runner), body: .json(.init(tool: tool))) {
            case .accepted(let o): return try o.body.json.op ?? ""
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    static func policy(_ p: Components.Schemas.RunnerPolicyBody) -> RunnerPolicy {
        RunnerPolicy(terminals: p.terminals, agents: p.agents, capacity: Int(p.agentCapacity))
    }

    // MARK: mapping

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            throw CoreFailure.of(error) ?? error
        }
    }

    static func fail(_ status: Int, _ body: Components.Schemas.ErrorBody?) -> CoreError {
        .http(status: status, code: body?.code ?? "unknown", message: body?.message ?? "The Core refused that.")
    }

    /// A status the contract does not list (503 `runner_busy`, 504 `runner_lost`): read the standard error body.
    static func fail(_ status: Int, _ payload: UndocumentedPayload) async -> CoreError {
        var data = Data()
        if let body = payload.body, let all = try? await Data(collecting: body, upTo: 64 * 1024) { data = all }
        let b = try? JSONDecoder().decode(Components.Schemas.ErrorBody.self, from: data)
        return fail(status, b)
    }

    static func item(_ t: Components.Schemas.Terminal) -> TerminalItem {
        let raw = t.status.value1?.rawValue ?? t.status.value2 ?? "unknown"
        return TerminalItem(
            id: t.id, runner: t.runner, status: raw, rows: Int(t.size?.rows ?? 0), cols: Int(t.size?.cols ?? 0),
            seq: UInt64(max(0, t.seq ?? 0)), attached: Int(t.attached ?? 0), orphaned: t.orphaned ?? false,
            exitCode: t.exitCode, exitSignal: t.exitSignal, createdAt: t.createdAt)
    }

    static func runner(_ r: Components.Schemas.Runner) -> RunnerItem {
        RunnerItem(
            id: r.id, name: r.name, online: r.online ?? false, degraded: r.degraded ?? false, load: Int(r.load ?? 0),
            capacity: Int(r.capacity ?? 0), avg1: r.hostLoad?.avg1, cores: r.hostLoad.map { Int($0.cores) },
            version: r.version, arch: r.arch, lastSeen: r.lastSeen,
            drivers: (r.drivers ?? []).map {
                DriverItem(
                    name: $0.name ?? "", commands: $0.commands ?? [], capacity: $0.capacity.map(Int.init),
                    slots: ($0.slots?.additionalProperties ?? [:]).mapValues(Int.init))
            }, isolationTiers: r.isolation?.tiers, osPretty: r.osPretty, os: r.os, sandbox: r.sandbox,
            runsAsUser: r.runsAs?.user, runsAsRoot: r.runsAs?.root, connectedSince: r.connectedSince,
            updateAvailable: r.updateAvailable, builtIn: r.builtIn ?? false,
            accounts: r.accounts.map {
                RunnerAccountFacts(
                    gateway: $0.gateway, subscriptionEnv: $0.subscriptionEnv, egressFilter: $0.egressFilter,
                    gatewayReason: $0.gatewayReason, subscriptionEnvReason: $0.subscriptionEnvReason,
                    egressFilterReason: $0.egressFilterReason)
            },
            slots: r.slots.map {
                RunnerSlotFacts(
                    agentsUsed: Int($0.agentsUsed), agentsCapacity: $0.agentsCapacity.map(Int.init),
                    terminalsUsed: Int($0.terminalsUsed), terminalsCapacity: $0.terminalsCapacity.map(Int.init))
            },
            tools: r.tools?.additionalProperties ?? [:], policy: r.policy.map(Self.policy))
    }
}
