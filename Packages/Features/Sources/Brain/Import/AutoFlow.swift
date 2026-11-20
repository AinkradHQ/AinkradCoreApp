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
                quiet += 1
                // About two minutes with nothing: the person sorts it (the Core leaves Unsorted and mixed rooms alone).
                if quiet > 60 {
                    sort = .nothing
                    return
                }
                try? await Task.sleep(for: poll)
            }
        }
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
