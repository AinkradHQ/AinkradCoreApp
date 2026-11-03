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
}

struct LiveTerminalService: TerminalService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func terminals() async throws -> [TerminalItem] {
        try await run { try await client.listTerminals().ok.body.json.map(Self.item) }
    }

    func terminal(_ id: String) async throws -> TerminalItem {
        try await run {
            switch try await client.getTerminal(path: .init(id: id)) {
            case .ok(let o): return Self.item(try o.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
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

    // MARK: mapping

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            throw CoreError.unwrapping(error) ?? error
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
                DriverItem(name: $0.name ?? "", commands: $0.commands ?? [], capacity: $0.capacity.map(Int.init))
            }, isolationTiers: r.isolation?.tiers)
    }
}
