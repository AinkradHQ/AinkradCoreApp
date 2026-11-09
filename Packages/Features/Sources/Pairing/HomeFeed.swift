import Agents
import AinkradClient
import CoreKit
import Foundation
import Shell

struct HomeRunner: Equatable, Sendable {
    var name: String
    var arch: String?
    var online: Bool
    var capacity: Int
    var load: Int
    /// Host load per core, 0...1, when the runner reports it.
    var perCore: Double?
}

struct HomeAudit: Equatable, Sendable {
    var seq: Int64
    var at: Date
    var action: String
    var actor: String
}

/// What Home needs from the Core. Each read stands alone: a device without `admin` fails the costs and audit reads and the rest still show.
protocol HomeSource: Sendable {
    func sessions() async throws -> [AgentSessionInfo]
    func runners() async throws -> [HomeRunner]
    /// Cost events, newest first (at most 100): when, and millionths of a dollar.
    func costs() async throws -> [(at: Date, micros: Int64)]
    /// The tightest usage limit across accounts, 0...1.
    func utilisation() async throws -> Double
    func audit() async throws -> [HomeAudit]
}

struct LiveHomeSource: HomeSource {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func sessions() async throws -> [AgentSessionInfo] {
        try await LiveAgentsAPI(connection: connection).sessions(before: nil, limit: 50)
    }
    func runners() async throws -> [HomeRunner] {
        try await run {
            try await client.listRunners().ok.body.json.map { r in
                HomeRunner(
                    name: r.name, arch: r.arch, online: r.online ?? false, capacity: Int(r.capacity ?? 0),
                    load: Int(r.load ?? 0),
                    perCore: r.hostLoad.flatMap { $0.cores > 0 ? $0.avg1 / Double($0.cores) : nil })
            }
        }
    }
    func costs() async throws -> [(at: Date, micros: Int64)] {
        try await run {
            try await client.listCosts(query: .init(limit: 100)).ok.body.json.map {
                ($0.occurredAt, $0.costUsdMicros ?? 0)
            }
        }
    }
    func utilisation() async throws -> Double {
        try await run {
            let all = try await client.accountsUsage().ok.body.json
            return min(1, all.map { Double($0.maxUtilisationBps) / 10_000 }.max() ?? 0)
        }
    }
    func audit() async throws -> [HomeAudit] {
        try await run {
            let page = try await client.listAudit(query: .init(limit: 8)).ok.body.json
            return page.items.map {
                let who: String
                switch $0.actor {
                case .user(let u): who = "User \(u.userId)"
                case .system: who = "Core"
                }
                return HomeAudit(seq: $0.seq, at: $0.at, action: $0.action, actor: who)
            }
        }
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? error }
    }
}

/// Fills `shell.home` from the Core: once on connect, then after a quiet moment following any agent, runner, account or audit event.
@MainActor
final class HomeFeed {
    private let shell: ShellModel
    private let source: any HomeSource
    private let now: @Sendable () -> Date
    private let quiet: Duration
    private var pending: Task<Void, Never>?
    private var history: [String: [Double]] = [:]
    /// The kinds that change what Home shows.
    static let prefixes = ["agent.", "runner.", "account.", "audit", "pairing."]

    init(
        shell: ShellModel, source: any HomeSource, quiet: Duration = .milliseconds(500),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.shell = shell
        self.source = source
        self.quiet = quiet
        self.now = now
    }

    func event(kind: String) {
        guard Self.prefixes.contains(where: kind.hasPrefix) else { return }
        pending?.cancel()
        pending = Task { [weak self, quiet] in
            try? await Task.sleep(for: quiet)
            if !Task.isCancelled { await self?.refresh() }
        }
    }

    func stop() { pending?.cancel() }

    func refresh() async {
        let at = now()
        var home = shell.home
        if let s = try? await source.sessions() {
            home.running = s.filter(\.live).map {
                .init(
                    id: $0.id, tool: $0.harness, name: $0.model ?? $0.harness,
                    minutes: max(0, Int(at.timeIntervalSince($0.createdAt) / 60)))
            }
        }
        if let r = try? await source.runners() {
            home.machines = r.map { m in
                var h = history[m.name, default: []]
                if let p = m.perCore { h = Array((h + [min(1, p)]).suffix(12)) }
                history[m.name] = h
                return .init(
                    id: m.name, os: m.arch ?? "runner", online: m.online, slots: m.capacity, used: m.load, load: h)
            }
        }
        if let c = try? await source.costs() {
            let micros = c.filter { Calendar.current.isDate($0.at, inSameDayAs: at) }.reduce(0) { $0 + $1.micros }
            home.spendToday = Double(micros) / 1_000_000
        }
        if let u = try? await source.utilisation() { home.monthTokensUsed = u }
        if let a = try? await source.audit() {
            home.events = a.map {
                .init(
                    id: String($0.seq), text: Self.words($0.action), source: $0.actor,
                    minutesAgo: max(0, Int(at.timeIntervalSince($0.at) / 60)), symbol: "list.bullet")
            }
        }
        shell.home = home
    }

    /// `device.revoked` reads "Device revoked".
    static func words(_ action: String) -> String {
        let s = action.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
