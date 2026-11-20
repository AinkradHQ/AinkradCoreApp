import Agents
import AinkradClient
import Brain
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

struct HomeProject: Equatable, Sendable {
    var slug: String
    var name: String
    var updatedAt: Date
}

/// One provider's tightest plan limit.
struct HomeUsage: Equatable, Sendable {
    var provider: String
    var share: Double
    var resetsAt: Date?
}

extension ISO8601DateFormatter {
    /// The Core's timestamps carry fractions of a second.
    nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
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
    func health() async throws -> CoreHealthFacts
    func projects() async throws -> [HomeProject]
    func usage() async throws -> [HomeUsage]
    /// Today's Lore note, nil when none was started (reading never creates one).
    func todayNote() async throws -> HomeSnapshot.NoteFact?
    /// What the Brain is doing now; nil on a Core older than API minor 95.
    func brainPipeline() async throws -> HomeSnapshot.BrainGlance.Pipeline?
    /// Tokens per day for the last `days` days, oldest first, from the Core's cost ledger; nil before API minor 95.
    func usageSeries(days: Int) async throws -> [Double]?
    /// The last `lines` lines of a terminal's screen (E6's tail read); nil on a Core older than API minor 95.
    func terminalTail(_ id: String, lines: Int) async throws -> [String]?
    /// Saves a changed note (the Core merges when it moved on) and answers the note as it is now.
    func saveNote(_ id: String, rev: Int, text: String) async throws -> HomeSnapshot.NoteFact?
}

extension HomeSource {
    func projects() async throws -> [HomeProject] { [] }
    func usage() async throws -> [HomeUsage] { [] }
    func todayNote() async throws -> HomeSnapshot.NoteFact? { nil }
    func brainPipeline() async throws -> HomeSnapshot.BrainGlance.Pipeline? { nil }
    func usageSeries(days: Int) async throws -> [Double]? { nil }
    func terminalTail(_ id: String, lines: Int) async throws -> [String]? { nil }
    func saveNote(_ id: String, rev: Int, text: String) async throws -> HomeSnapshot.NoteFact? { nil }
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

    func health() async throws -> CoreHealthFacts {
        try await run {
            let h = try await client.getCoreHealth().ok.body.json
            return CoreHealthFacts(
                version: h.version, uptimeSecs: h.uptimeSecs, certDaysLeft: h.certDaysLeft.map(Int.init),
                lastBackupAt: h.lastBackupAt, lastBackupBytes: h.lastBackupBytes)
        }
    }

    func projects() async throws -> [HomeProject] {
        try await run {
            try await client.listProjects().ok.body.json.filter { $0.state != "archived" }.map {
                HomeProject(slug: $0.slug, name: $0.name, updatedAt: $0.updatedAt)
            }
        }
    }

    /// The tightest limit of each provider across its accounts, with the soonest plan-window reset.
    func usage() async throws -> [HomeUsage] {
        try await run {
            async let spend = client.accountsUsage().ok.body.json
            async let accounts = client.listAccounts().ok.body.json
            let (spent, list) = try await (spend, accounts)
            return Self.usage(
                spent: spent.map { ($0.accountId, Double($0.maxUtilisationBps) / 10_000) },
                accounts: list.map {
                    ($0.id, $0.provider, ($0.health?.planLimit?.windows ?? []).compactMap(\.resetsAt))
                })
        }
    }

    static func usage(spent: [(Int64, Double)], accounts: [(Int64, String, [Date])]) -> [HomeUsage] {
        var by: [String: HomeUsage] = [:]
        for (id, provider, resets) in accounts {
            guard let share = spent.first(where: { $0.0 == id })?.1 else { continue }
            var u = by[provider] ?? HomeUsage(provider: provider, share: 0, resetsAt: nil)
            u.share = max(u.share, min(1, share))
            u.resetsAt = ([u.resetsAt].compactMap { $0 } + resets).min()
            by[provider] = u
        }
        return by.values.sorted { $0.provider < $1.provider }
    }

    func brainPipeline() async throws -> HomeSnapshot.BrainGlance.Pipeline? {
        guard await connection.serverSupports(minor: 95) else { return nil }
        let a = try await BrainRoutes(transport: LiveBrainTransport(connection: connection)).activity()
        let done = a.lastDoneAt.flatMap { ISO8601DateFormatter.withFraction.date(from: $0) }
        return .init(
            now: HomeSnapshot.BrainGlance.Pipeline.stage(
                distilling: a.distilling, queued: a.queued, overviews: a.overviews),
            working: a.distilling, queued: a.queued, overviews: a.overviews, lastDoneAt: done)
    }

    /// `GET /terminals/{id}/tail` (E6): 1 to 20 lines of plain text, oldest first; empty for a terminal that is not a private sandbox.
    func terminalTail(_ id: String, lines: Int) async throws -> [String]? {
        guard await connection.serverSupports(minor: 95) else { return nil }
        struct Tail: Decodable { var lines: [String] }
        let data = try await run {
            try await connection.signedRequest(
                method: "GET", target: "/api/v1/terminals/\(id)/tail?lines=\(min(max(lines, 1), 20))", body: Data())
        }
        return try JSONDecoder().decode(Tail.self, from: data).lines
    }

    func usageSeries(days: Int) async throws -> [Double]? {
        guard await connection.serverSupports(minor: 95) else { return nil }
        let data = try await run {
            try await connection.signedRequest(method: "GET", target: "/api/v1/costs/series?days=\(days)", body: Data())
        }
        return try HomeFeed.series(data, days: days, now: Date())
    }

    private var lore: LiveLoreService { LiveLoreService(connection: connection) }

    func todayNote() async throws -> HomeSnapshot.NoteFact? {
        try await run {
            guard let n = try await lore.daily(HomeFeed.dayKey(Date())) else { return nil }
            return HomeSnapshot.NoteFact.parse(n.text, id: n.id, rev: n.rev)
        }
    }

    func saveNote(_ id: String, rev: Int, text: String) async throws -> HomeSnapshot.NoteFact? {
        try await run {
            let r = try await lore.save(id, baseRev: rev, text: text)
            return HomeSnapshot.NoteFact.parse(r.note.text, id: r.note.id, rev: r.note.rev)
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
    /// Terminals and Brain live in their own apps; the app hands Home what they hold.
    var terminalFacts: (@MainActor () -> [HomeSnapshot.TerminalFact])?
    var brainService: (@MainActor () -> (any BrainService)?)?
    /// The kinds that change what Home shows.
    static let prefixes = [
        "agent.", "runner.", "account.", "audit", "pairing.", "terminal.", "project.", "lore.", "brain.",
    ]

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
        var live: [AgentSessionInfo] = []
        if let s = try? await source.sessions() {
            live = s.filter(\.live)
            home.running = live.map {
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
            home.spendByDay = HomeSnapshot.spendDays(c, now: at)
            home.monthSpend = HomeSnapshot.monthSpend(c, now: at)
        }
        if let u = try? await source.utilisation() { home.monthTokensUsed = u }
        if let a = try? await source.audit() {
            home.events = a.map {
                .init(
                    id: String($0.seq), text: Self.words($0.action), source: $0.actor,
                    minutesAgo: max(0, Int(at.timeIntervalSince($0.at) / 60)), symbol: "list.bullet")
            }
        }
        if let h = try? await source.health() { home.health = h }
        if let p = try? await source.projects() {
            home.projects = p.map { pr in
                .init(
                    id: pr.slug, name: pr.name, sessions: Self.sessions(in: pr, live: live),
                    updatedAt: pr.updatedAt)
            }
        }
        if let series = try? await source.usageSeries(days: 14) { home.usageSeries = series }
        if let u = try? await source.usage() {
            home.usage = u.map { .init(provider: $0.provider, share: $0.share, resetsAt: $0.resetsAt) }
        }
        if let n = try? await source.todayNote() { home.note = n } else { home.note = nil }
        if let t = terminalFacts {
            var facts = t()
            // The Core's tail serves every terminal; the attached screen (already in `lines`) is the fallback.
            for i in facts.indices {
                let f = facts[i]
                if let tail = try? await source.terminalTail(f.id, lines: 3), !tail.isEmpty {
                    facts[i] = .init(id: f.id, name: f.name, place: f.place, onThisMac: f.onThisMac, lines: tail)
                }
            }
            home.terminals = facts
        }
        if let b = brainService?() {
            var glance = await Self.glance(b)
            var pipeline = try? await source.brainPipeline()
            let progress = brainProgress(pipeline)
            pipeline?.progress = progress
            glance?.pipeline = pipeline
            home.brain = glance
        }
        shell.home = home
    }

    private var brainPeak = 0

    /// Done over done plus waiting, from the counts alone: the most work seen waiting since it last had none counts as
    /// the whole. nil while idle (the peak resets).
    private func brainProgress(_ p: HomeSnapshot.BrainGlance.Pipeline?) -> Double? {
        let pending = (p?.working ?? 0) + (p?.queued ?? 0)
        guard let p, p.now != nil else {
            brainPeak = 0
            return nil
        }
        brainPeak = max(brainPeak, pending, 1)
        return Double(brainPeak - pending) / Double(brainPeak)
    }

    /// Writes a tick on today's note back (the widget shows it at once; the Core's answer replaces it).
    func toggleTodo(_ index: Int) async {
        guard let n = shell.home.note, let text = HomeSnapshot.NoteFact.toggling(n.text, todo: index) else { return }
        shell.home.note = HomeSnapshot.NoteFact.parse(text, id: n.id, rev: n.rev)
        if let saved = try? await source.saveNote(n.id, rev: n.rev, text: text) {
            shell.home.note = saved
        } else {
            await refresh()
        }
    }

    /// `GET /costs/series` as one token total per UTC day, the last entry being `now`'s day.
    nonisolated static func series(_ data: Data, days: Int, now: Date) throws -> [Double] {
        struct Row: Decodable {
            var day: String
            var total_tokens: Int64
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let by = Dictionary(rows.map { ($0.day, Double($0.total_tokens)) }, uniquingKeysWith: +)
        return (0..<days).reversed().map { back in
            by[f.string(from: utc.date(byAdding: .day, value: -back, to: now) ?? now)] ?? 0
        }
    }

    /// "2026-11-19", the local day, as Lore keys its daily notes.
    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Live sessions whose folder or repo is this project (by its name or slug, the last path part, case ignored).
    static func sessions(in p: HomeProject, live: [AgentSessionInfo]) -> Int {
        let names: Set<String> = [p.slug.lowercased(), p.name.lowercased()]
        return live.filter {
            guard let f = $0.project?.split(separator: "/").last else { return false }
            return names.contains(f.lowercased())
        }.count
    }

    /// What Brain shows Home. nil when the Core has no Brain (rooms cannot be read).
    static func glance(_ s: any BrainService) async -> HomeSnapshot.BrainGlance? {
        guard let rooms = try? await s.rooms() else { return nil }
        let overview = try? await s.overview()
        let candidates = try? await s.candidates()
        let health: String
        switch overview?.health {
        case .needsYou: health = "Needs you"
        case .paused: health = "Paused"
        default: health = "Healthy"
        }
        return .init(
            known: rooms.compactMap { $0.counts?.records }.reduce(0, +), rooms: rooms.count,
            waiting: overview?.needs.map(\.n).reduce(0, +) ?? candidates?.items.count ?? 0, health: health,
            question: candidates?.items.first.map { .init(id: $0.id, room: $0.room, text: $0.text) })
    }

    /// Keeps or drops the candidate Brain asked about.
    func answer(_ id: String, room: String, keep: Bool) async {
        if let s = brainService?() { try? await s.decide(id, room: room, keep ? .accept : .reject) }
        await refresh()
    }

    /// `device.revoked` reads "Device revoked".
    static func words(_ action: String) -> String {
        let s = action.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
