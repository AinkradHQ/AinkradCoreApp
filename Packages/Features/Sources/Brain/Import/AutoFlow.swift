import Foundation
import Observation

/// The import's Sort and Learn steps on a Core that prepares the places and distils by itself (D-26, mockup 17). Nothing
/// is filed before the person approves (Ahmed, 2026-11-21: review before filing): Sort is the review of what the Core
/// prepared. Only an old run the Core already accepted by itself (it lists it in GET /auto-imports) shows "sorted" with
/// Undo. Closing the wizard cancels the polling, not the work.
@MainActor @Observable
public final class AutoFlow {
    public enum Sort: Equatable {
        /// Not looked yet.
        case checking
        /// The places wait for the person's review (the normal case).
        case review
        /// An old run the Core accepted by itself: `rooms` places made.
        case sorted(rooms: Int)
    }

    public private(set) var sort: Sort = .checking
    /// The Core recorded the old sort as its own (GET /auto-imports lists the run): only then can it be undone.
    public private(set) var canUndo = false
    /// After an Undo of an old sort: the items back in Unsorted, for the summary line.
    public private(set) var undoneItems: Int?
    public private(set) var learning: LearningWire?
    public private(set) var failure: String?
    let routes: BrainRoutes
    let poll: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(routes: BrainRoutes, poll: Duration = .seconds(2)) {
        self.routes = routes
        self.poll = poll
    }

    /// One look: an old run the Core sorted by itself, or one already filed, skips the review; anything else is reviewed.
    func check(run: String) async {
        canUndo = false
        if let all = try? await routes.autoImports(), let a = all.first(where: { $0.run == run }) {
            sort = .sorted(rooms: a.rooms)
            canUndo = true
        } else if let v = try? await routes.run(run), v.state == "committed" {
            sort = .sorted(rooms: (try? await routes.learning(run: run))?.places.count ?? 0)
        } else {
            sort = .review
        }
    }

    /// Undo of an old sort: back to one pile, and that pile is reviewed like any other.
    func undo(run: String) async {
        task?.cancel()
        do {
            let r = try await routes.undoAutoImport(run: run)
            undoneItems = r.items
            sort = .review
            canUndo = false
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
