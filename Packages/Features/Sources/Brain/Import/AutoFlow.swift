import Foundation
import Observation

/// The import's Sort and Learn steps when the Core accepts and distils by itself (D-26, mockup 17). It only reads the Core and
/// offers Undo; the Core does the work. Closing the wizard cancels the polling, not the work.
@MainActor @Observable
public final class AutoFlow {
    public enum Sort: Equatable {
        /// The Core is still sorting.
        case waiting
        /// All accepted: `rooms` places made.
        case sorted(rooms: Int)
        /// Put back to one pile by the person: `items` are in Unsorted, open for review.
        case undone(items: Int)
        /// Nothing the Core could accept on its own.
        case nothing
    }

    public private(set) var sort: Sort = .waiting
    /// While sorting: what the Core does now, in words, and how far the local model has read (nil when it is not reading).
    public private(set) var sortPhase = "Getting ready to sort"
    public private(set) var reading: SemanticProgress?
    /// The time left at the local model's measured pace; nil until two readings apart show a pace.
    public private(set) var readingLeft: Duration?
    @ObservationIgnored private var pace: (at: ContinuousClock.Instant, done: Int)?
    public private(set) var learning: LearningWire?
    public private(set) var failure: String?
    let routes: BrainRoutes
    let poll: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(routes: BrainRoutes, poll: Duration = .seconds(2)) {
        self.routes = routes
        self.poll = poll
    }

    /// Polls until the Core has accepted the run's rooms (or says there is nothing to accept).
    func watchSort(run: String) {
        task?.cancel()
        sort = .waiting
        reading = nil
        readingLeft = nil
        pace = nil
        task = Task { [weak self] in
            var quiet = 0
            while !Task.isCancelled, let self {
                if let all = try? await routes.autoImports(), let a = all.first(where: { $0.run == run }) {
                    sort = .sorted(rooms: a.rooms)
                    return
                }
                if let v = try? await routes.run(run), v.state == "committed" {
                    let n = (try? await routes.learning(run: run))?.places.count ?? 0
                    sort = n > 0 ? .sorted(rooms: n) : .nothing
                    return
                }
                // The Core may have filed the places already without its audit record (Core 0.10.0 lost it, 2026-11-21:
                // 20 places made, the app said "Nothing was sorted"). Places of this run mean it is sorted.
                if let n = (try? await routes.learning(run: run))?.places.count, n > 0 {
                    sort = .sorted(rooms: n)
                    return
                }
                // The slow part is the local model reading every item (GET /imports/{run}/semantic); the Core files the
                // rooms once it is done. Wait as long as it reads: the old 2-minute give-up said "Nothing was sorted" on
                // a big import while the model was still reading (Ahmed, 2026-11-21, 12,391 sessions).
                let sem = try? await routes.semantic(run: run)
                if sem?.state == "pending" {
                    quiet = 0
                    sortPhase = "The local model is reading your work"
                    if let p = sem?.progress, p.total > 0 { note(p) }
                } else {
                    reading = nil
                    readingLeft = nil
                    sortPhase = "Filing your work into places"
                    quiet += 1
                }
                // About two minutes after the reading with nothing filed: the person sorts it (the Core leaves Unsorted
                // and mixed rooms alone). The Core files every 30 s, so this is several of its rounds.
                if quiet > 60 {
                    sort = .nothing
                    return
                }
                try? await Task.sleep(for: poll)
            }
        }
    }

    /// A new reading of the local model's progress: the count, and the time left at the pace measured since the first one.
    private func note(_ p: SemanticProgress) {
        reading = p
        let now = ContinuousClock.now
        guard let first = pace else {
            pace = (now, p.done)
            return
        }
        let read = p.done - first.done
        let took = now - first.at
        guard read > 0, took > .seconds(5) else { return }
        let perItem = took / read
        readingLeft = perItem * max(0, p.total - p.done)
    }

    func undo(run: String) async {
        task?.cancel()
        do {
            let r = try await routes.undoAutoImport(run: run)
            sort = .undone(items: r.items)
            failure = nil
        } catch { failure = BrainWords.failure(error) }
    }

    /// Polls the Learn step until every place is done. `onDone` runs once.
    func watchLearning(run: String, onDone: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                if let l = try? await routes.learning(run: run) {
                    learning = l
                    if l.done {
                        await onDone()
                        return
                    }
                }
                try? await Task.sleep(for: poll)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// "$1.42": the running cost in dollars from millionths.
    public static func dollars(_ micros: Int) -> String {
        let d = Double(micros) / 1_000_000
        return d < 0.01 && micros > 0 ? "less than $0.01" : String(format: "$%.2f", d)
    }
}
