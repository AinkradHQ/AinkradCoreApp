import Admin
import BrainImport
import Foundation
import Observation

/// The Import wizard's state machine: sources, collect and clean, review rooms, import, done. It owns the run; the sheet
/// only draws it, so closing the sheet while a collect runs loses nothing. Every call to the Core is in `BrainRoutes`.
@MainActor @Observable
public final class ImportModel {
    public enum Step: Int, CaseIterable, Sendable { case sources, collecting, review, importing, done }
    public enum Phase: Sendable { case reading, uploading, discovering }

    public struct Choice: Identifiable, Equatable {
        public let id: String
        public let title: String
        /// nil until the first scan answered.
        public var found: Int?
        public var skipped: [String: Int] = [:]
        public var on = true
    }

    let host: any AdminHost
    let routes: BrainRoutes
    let sources: [String: any ImportSource]
    let poll: Duration
    let pause: @Sendable (Int) async -> Void

    public private(set) var step: Step = .sources
    public private(set) var phase: Phase = .reading
    public var choices: [Choice]
    public private(set) var run: String?
    /// The Core's counts for this run, as `GET /imports/{run}` last said.
    public private(set) var counts = RunCounts()
    /// What the Mac itself skipped before sending, by reason code.
    public private(set) var localSkipped: [String: Int] = [:]
    public private(set) var toSend = 0
    public private(set) var secondsLeft: Int?
    public internal(set) var failure: String?
    public private(set) var result: CommitResult?
    public let review: ReviewModel

    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let uploaded = Uploader.Progress()
    @ObservationIgnored private var collectedSources: Set<String> = []
    @ObservationIgnored private var started: Date?

    public init(
        host: any AdminHost, routes: BrainRoutes, sources: [any ImportSource], poll: Duration = .seconds(1),
        pause: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .seconds(Double(1 << $0))) }
    ) {
        self.host = host
        self.routes = routes
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.poll = poll
        self.pause = pause
        choices = sources.map { Choice(id: $0.id, title: $0.title) }
        review = ReviewModel(host: host, routes: routes)
    }

    // MARK: step 1

    public var chosen: [Choice] { choices.filter(\.on) }
    public var canStart: Bool { step == .sources && !chosen.isEmpty && job == nil }
    /// Something is running or waiting for the person: the pane says "Import in progress".
    public var isActive: Bool { run != nil && step != .done }

    /// Counts what each source holds, from file names only.
    public func scan() async {
        for i in choices.indices {
            guard let source = sources[choices[i].id] else { continue }
            let r = await source.scan()
            choices[i].found = r.found
            choices[i].skipped = r.skipped
        }
    }

    // MARK: step 2

    public func start() {
        guard canStart else { return }
        job = Task { await collectAndClean() }
    }

    /// Try again after a failure: the run and everything the Core already confirmed are kept.
    public func retry() {
        guard step == .collecting, failure != nil, job == nil else { return }
        failure = nil
        job = Task { await collectAndClean() }
    }

    func collectAndClean() async {
        step = .collecting
        failure = nil
        phase = .reading
        started = Date()
        defer { job = nil }
        do {
            let id: String
            if let run {
                id = run
            } else {
                id = try await routes.startRun(kind: "full", sources: chosen.map(\.id))
                run = id
            }
            var collected: [(source: String, items: [ImportItem])] = []
            localSkipped = [:]
            for c in chosen {
                guard let source = sources[c.id], !collectedSources.contains(c.id) else { continue }
                let (items, report) = await source.collect()
                for (k, n) in report.skipped { localSkipped[k, default: 0] += n }
                collected.append((c.id, items))
            }
            toSend = collected.reduce(0) { $0 + $1.items.count }
            phase = .uploading
            startPoller(run: id)
            let uploader = Uploader(transport: RoutesImportTransport(routes: routes), pause: pause)
            for (source, items) in collected {
                try await uploader.upload(items, run: id, progress: uploaded)
                do { _ = try await routes.collected(run: id, source: source) } catch let e as BrainHTTPError
                    where e.status == 409
                {}  // already reported by an earlier attempt
                collectedSources.insert(source)
            }
            stopPoller()
            phase = .discovering
            try await waitForReview(run: id)
            try await review.load(run: id)
            step = .review
        } catch is CancellationError {
            stopPoller()
        } catch {
            stopPoller()
            failure = BrainWords.failure(error)
        }
    }

    private func startPoller(run: String) {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(run: run)
                try? await Task.sleep(for: self?.poll ?? .seconds(1))
            }
        }
    }

    private func stopPoller() {
        poller?.cancel()
        poller = nil
    }

    /// One `GET /imports/{run}`; the progress bar and the status line read what it said.
    @discardableResult
    func refresh(run: String) async -> RunView? {
        guard let v = try? await routes.run(run) else { return nil }
        counts = v.counts
        if toSend > 0, counts.answered > 0, let started {
            let elapsed = Date().timeIntervalSince(started)
            let rate = Double(counts.answered) / max(elapsed, 0.001)
            secondsLeft = elapsed > 2 ? Int((Double(max(toSend - counts.answered, 0)) / rate).rounded(.up)) : nil
        }
        return v
    }

    private func waitForReview(run: String) async throws {
        while true {
            try Task.checkCancellation()
            if let v = await refresh(run: run) {
                if v.state == "abandoned" { throw BrainFailure("This import was abandoned.", code: "abandoned") }
                if ["review", "committing", "committed"].contains(v.state) { return }
            }
            try await Task.sleep(for: poll)
        }
    }

    /// 0 to 1 for the bar: reading is not counted, uploading is the Core's answers over what was sent, discovery is full.
    public var fraction: Double {
        switch phase {
        case .reading: 0
        case .uploading: toSend == 0 ? 0 : min(1, Double(counts.answered) / Double(toSend))
        case .discovering: 1
        }
    }

    /// The one live status line.
    public var statusLine: String {
        switch phase {
        case .reading: return "Reading your sessions. Nothing has left this Mac yet."
        case .discovering: return "Sorting what was kept into rooms. This uses no model."
        case .uploading:
            var s = "\(toSend) found, \(counts.stored) kept, \(counts.duplicate) already known"
            let skips = ImportWords.skips(merged(localSkipped, counts.skipped))
            let refused = counts.refused + counts.rejected
            if refused > 0 || !skips.isEmpty {
                let n = refused + merged(localSkipped, counts.skipped).values.reduce(0, +)
                s += ", \(n) skipped"
                if !skips.isEmpty { s += " (\(skips))" }
            }
            if let secondsLeft { s += ". About \(ImportWords.left(seconds: secondsLeft)) left" }
            return s
        }
    }

    private func merged(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        a.merging(b) { $0 + $1 }
    }

    /// Stops a collect in progress and goes back to choosing sources. The run stays on the Core, unused.
    public func stop() {
        job?.cancel()
        stopPoller()
        job = nil
    }

    // MARK: step 4

    public func commit() async {
        guard step == .review, review.canCommit, let run else { return }
        step = .importing
        do {
            let r = try await host.elevated(
                "Import the accepted rooms into the Brain.", done: "imported", keepsEdit: false
            ) { try await self.routes.commit(run: run) }
            result = r
            await review.refresh()
            step = .done
        } catch is AdminDeclined {
            step = .review
        } catch {
            step = .review
            review.notice = BrainWords.failure(error)
        }
    }

    /// For the done page: which rooms were made and which wait for the backup.
    public func heldCards() -> [ProposalCard] { review.cards.filter(\.isHeld) }
}
