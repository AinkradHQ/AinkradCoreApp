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
        /// Why the source cannot be collected yet; such a choice is off and can not be turned on.
        public var notReadable: String?
        /// The tool has no history on this Mac at all (rather than one this app cannot read).
        public var absent = false
    }

    /// One source's line on the collect step: done, being read, or waiting.
    public struct SourceRow: Identifiable, Equatable {
        public enum State: Equatable { case waiting, reading, done }
        public let id: String
        public let title: String
        public let state: State
        /// Items read so far over the items the scan found.
        public let done: Int
        public let total: Int
        public var fraction: Double { total == 0 ? (state == .done ? 1 : 0) : min(1, Double(done) / Double(total)) }
    }

    let host: any AdminHost
    let routes: BrainRoutes
    /// Set by the pane: after a commit the imported Mac collectors are registered for incremental sync.
    @ObservationIgnored var service: (any BrainService)?
    let sources: [String: any ImportSource]
    /// Where "Notes and docs" look; nil when the sources do not read from the person's choices (tests, the sample).
    let places: ImportPlaces?
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
    /// Files and bytes done over total for the current source, from file attributes.
    public private(set) var progress = StreamProgress()
    public private(set) var itemsFound = 0
    public private(set) var secondsLeft: Int?
    public internal(set) var failure: String?
    public private(set) var result: CommitResult?
    public let review: ReviewModel

    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let uploaded = Uploader.Progress()
    /// The sources finished in this run, and the one being read now.
    public private(set) var collectedSources: Set<String> = []
    public private(set) var current: String?
    @ObservationIgnored private var started: Date?
    @ObservationIgnored private var baseline: UInt64?
    @ObservationIgnored private let resume: ResumeStore?
    @ObservationIgnored private var resumeState = ResumeState()

    public init(
        host: any AdminHost, routes: BrainRoutes, sources: [any ImportSource], poll: Duration = .seconds(1),
        resume: ResumeStore? = nil, places: ImportPlaces? = nil,
        pause: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .seconds(Double(1 << $0))) }
    ) {
        self.host = host
        self.routes = routes
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        self.poll = poll
        self.pause = pause
        self.resume = resume
        self.places = places
        mode = places?.mode ?? .folders
        folders = places?.folders ?? []
        chatFolder = places?.chat
        choices = sources.map {
            Choice(
                id: $0.id, title: $0.title, on: $0.notReadable == nil, notReadable: $0.notReadable,
                absent: ($0 as? NotReadableSource)?.absent ?? false)
        }
        review = ReviewModel(host: host, routes: routes)
    }

    // MARK: step 1

    public var chosen: [Choice] { choices.filter { $0.on && $0.notReadable == nil } }
    public var canStart: Bool { step == .sources && !chosen.isEmpty && job == nil && !searching }
    /// Something is running or waiting for the person: the pane says "Import in progress".
    public var isActive: Bool { run != nil && step != .done }

    /// Counts what each source holds, from file names only.
    public func scan() async {
        // Owned by the model, not by the sheet's task: a sheet that is redrawn does not cancel the count halfway.
        searchJob?.cancel()
        rescanJob?.cancel()
        let job = Task {
            if places != nil { suggestions = await suggest() }
            await scanChoices(notesOnly: false)
        }
        rescanJob = job
        await job.value
    }

    private func scanChoices(notesOnly: Bool) async {
        let notes = choices.indices.filter { SyncWords.group(choices[$0].id) == SyncWords.notesGroup }
        let sessions = choices.indices.filter { !notes.contains($0) }
        if notesOnly || places?.mode == .disk { for i in notes { choices[i].found = nil } }
        // Sessions first: their counts do not wait for a whole-disk search.
        for i in notesOnly ? [] : sessions { await count(i, stale: false) }
        if let places, places.mode == .folders {
            let chosen = places.folders
            notAllowed = await Task.detached { chosen.filter { !Self.canRead($0) }.count }.value
        }
        if let places, places.mode == .disk, !notes.isEmpty { await searchDisk(places) }
        for i in notes { await count(i, stale: true) }
    }

    /// `stale`: drop the answer when a newer change of place has already cancelled this recount.
    private func count(_ i: Int, stale: Bool) async {
        guard let source = sources[choices[i].id] else { return }
        let r = await source.scan()
        if stale, Task.isCancelled { return }
        choices[i].found = r.found
        choices[i].skipped = r.skipped
    }

    // MARK: where to look

    public private(set) var mode: ImportPlaces.Mode = .folders
    public private(set) var folders: [URL] = []
    public private(set) var chatFolder: URL?
    /// Folders the app found that look like projects or notes. Offered, never added on their own.
    public private(set) var suggestions: [URL] = []
    /// The whole-disk search is running; `checked` counts the files looked at so far.
    public private(set) var searching = false
    public private(set) var checked = 0
    /// How the last search ended, for the line under the choice.
    public private(set) var searched: DocWalker.Found?
    @ObservationIgnored private var rescanJob: Task<Void, Never>?
    @ObservationIgnored private var searchJob: Task<DocWalker.Found, Never>?

    private func suggest() async -> [URL] {
        guard let places, places.mode == .folders else { return [] }
        let taken = places.folders
        return await Task.detached { places.suggestions(excluding: taken) }.value
    }

    public func setMode(_ m: ImportPlaces.Mode) {
        guard let places, m != mode, step == .sources else { return }
        mode = m
        places.mode = m
        rescanNotes()
    }

    public func addFolders(_ urls: [URL]) {
        guard let places else { return }
        var seen = Set(folders.map(\.path))
        let new = urls.filter { seen.insert($0.path).inserted }
        guard !new.isEmpty else { return }
        folders += new
        places.folders = folders
        suggestions.removeAll { s in folders.contains { $0.path == s.path } }
        rescanNotes()
    }

    public func removeFolder(_ url: URL) {
        guard let places else { return }
        folders.removeAll { $0.path == url.path }
        places.folders = folders
        rescanNotes()
        Task { suggestions = await suggest() }
    }

    public func setChatFolder(_ url: URL?) {
        guard let places else { return }
        chatFolder = url
        places.chat = url
        rescanNotes()
    }

    /// Stops a search that is running and keeps what it found so far.
    public func stopSearch() { searchJob?.cancel() }

    public func searchAgain() { rescanNotes() }

    /// Waits for the recount a change of place started.
    func settled() async { await rescanJob?.value }

    private func rescanNotes() {
        searchJob?.cancel()
        rescanJob?.cancel()
        rescanJob = Task { await scanChoices(notesOnly: true) }
    }

    /// Walks the home folder off the main actor, with the count shown live. Cancelling keeps the partial answer.
    private func searchDisk(_ places: ImportPlaces) async {
        searchGen += 1
        let mine = searchGen
        searching = true
        checked = 0
        searched = nil
        let job = Task.detached { [weak self] in
            places.runSearch { n in Task { @MainActor in self?.checked = n } }
        }
        searchJob = job
        let found = await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            job.cancel()
        }
        guard mine == searchGen else { return }
        searched = found
        checked = found.checked
        notAllowed = found.unreadable
        searching = false
    }

    /// Folders macOS did not let this app open (Privacy & Security): chosen ones, or those a search met.
    public private(set) var notAllowed = 0
    @ObservationIgnored private var searchGen = 0

    /// False only when macOS refuses the folder; a folder that is gone is not a privacy problem.
    nonisolated static func canRead(_ url: URL) -> Bool {
        do { _ = try FileManager.default.contentsOfDirectory(atPath: url.path) } catch let e as CocoaError {
            return e.code != .fileReadNoPermission
        } catch {}
        return true
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
        baseline = nil
        defer { job = nil }
        do {
            let id = try await runID()
            localSkipped = [:]
            itemsFound = 0
            phase = .uploading
            startPoller(run: id)
            let uploader = Uploader(transport: RoutesImportTransport(routes: routes), pause: pause)
            for c in chosen {
                let sid = c.id
                guard let source = sources[sid], !collectedSources.contains(sid) else { continue }
                current = sid
                progress = StreamProgress()
                let report = try await source.stream(
                    run: id, uploader: uploader, uploaded: uploaded, resume: resumeState.sources[sid] ?? .init(),
                    save: { [weak self] s in self?.remember(sid, s) },
                    onProgress: { [weak self] p in await self?.apply(p) })
                for (k, n) in report.skipped { localSkipped[k, default: 0] += n }
                itemsFound += report.items
                do { _ = try await routes.collected(run: id, source: sid) } catch let e as BrainHTTPError
                    where e.status == 409
                {}  // already reported by an earlier attempt
                collectedSources.insert(sid)
            }
            current = nil
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

    /// The run in hand, or the one saved on this Mac if the Core still knows it, or a new one.
    private func runID() async throws -> String {
        if let run { return run }
        let ids = chosen.map(\.id)
        if let saved = resume?.load(), let r = saved.run, Set(saved.sources.keys).isSubset(of: ids),
            (try? await routes.run(r)) != nil
        {
            resumeState = saved
            run = r
            return r
        }
        let id = try await routes.startRun(kind: "full", sources: ids)
        run = id
        resumeState = ResumeState()
        resumeState.run = id
        resume?.save(resumeState)
        return id
    }

    private nonisolated func remember(_ source: String, _ s: SourceResume) {
        Task { @MainActor in
            resumeState.sources[source] = s
            resume?.save(resumeState)
        }
    }

    func apply(_ p: StreamProgress) {
        progress = p
        let base = baseline ?? p.bytesDone
        baseline = base
        guard let started, p.bytesDone > base else { return }
        let elapsed = Date().timeIntervalSince(started)
        let rate = Double(p.bytesDone - base) / max(elapsed, 0.001)
        secondsLeft = elapsed > 2 ? Int((Double(p.bytesTotal - p.bytesDone) / rate).rounded(.up)) : nil
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
        case .uploading: progress.bytesTotal == 0 ? 0 : min(1, Double(progress.bytesDone) / Double(progress.bytesTotal))
        case .discovering: 1
        }
    }

    /// The collect step's lines, one per chosen source.
    public var sourceRows: [SourceRow] {
        chosen.map { Self.row($0, done: collectedSources.contains($0.id), reading: $0.id == current ? progress : nil) }
    }

    /// One line, always in items (what the scan found). Reading progress comes in files, so it is turned into the same
    /// share of the items: mixing the two made a bar stall short and then jump, and the total add files to items.
    static func row(_ c: Choice, done: Bool, reading: StreamProgress?) -> SourceRow {
        let total = c.found ?? 0
        if done { return SourceRow(id: c.id, title: c.title, state: .done, done: total, total: total) }
        guard let p = reading else {
            return SourceRow(id: c.id, title: c.title, state: .waiting, done: 0, total: total)
        }
        let share = p.filesTotal == 0 ? 0 : min(1, Double(p.filesDone) / Double(p.filesTotal))
        return SourceRow(
            id: c.id, title: c.title, state: .reading, done: Int((Double(total) * share).rounded(.down)), total: total)
    }

    /// Items read over items found, across every chosen source.
    public var itemsDone: (done: Int, total: Int) {
        sourceRows.reduce((0, 0)) { ($0.0 + $1.done, $0.1 + $1.total) }
    }

    /// The one live status line.
    public var statusLine: String {
        switch phase {
        case .reading: return "Reading your sessions."
        case .discovering: return "Sorting what was kept into rooms. This uses no model."
        case .uploading:
            var s = "File \(min(progress.filesDone + 1, max(progress.filesTotal, 1))) of \(progress.filesTotal), "
            s += "\(ImportWords.bytes(progress.bytesDone)) of \(ImportWords.bytes(progress.bytesTotal))"
            if !progress.current.isEmpty { s += " (\(ImportWords.shortName(progress.current)))" }
            s += ". \(itemsFound) found, \(counts.stored) kept, \(counts.duplicate) already known"
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

    /// Opens the review step for a run the Core already holds (a sync that left rooms or Unsorted items to review).
    /// False when another import is in progress.
    @discardableResult
    public func reviewExisting(_ id: String) async -> Bool {
        if run == id, step == .review { return true }
        guard !isActive else { return false }
        do {
            try await review.load(run: id)
            run = id
            step = .review
            return true
        } catch {
            failure = BrainWords.failure(error)
            return false
        }
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
            resume?.clear()
            if let since = started, let service {
                await SyncModel.register(chosen.map(\.id), from: Array(sources.values), since: since, service: service)
            }
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
