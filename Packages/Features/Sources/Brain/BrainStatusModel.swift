import Foundation
import Observation
import Shell

/// What the top-bar Brain icon shows: the Core's one status call (API minor 95), read every 20 seconds while a Core that has it
/// is attached. Counts only. Nothing here asks the person for anything but an AI account, a runner or the unlock.
@MainActor @Observable
public final class BrainStatusModel {
    public private(set) var activity: BrainActivityWire?
    @ObservationIgnored private var task: Task<Void, Never>?
    static let every: Duration = .seconds(20)

    public init() {}

    func start(_ routes: BrainRoutes) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let a = try? await routes.activity() { self?.activity = a }
                try? await Task.sleep(for: Self.every)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        activity = nil
    }

    /// The chip the shell draws; nil until the Core has answered.
    public var chip: Shell.BrainChip? {
        guard let a = activity else { return nil }
        return Shell.BrainChip(
            state: a.state, line: Self.line(a), needs: a.needs.map { Self.need($0) }, attention: a.health != "ok")
    }

    static func line(_ a: BrainActivityWire) -> String {
        switch a.state {
        case "locked": return "Brain is locked. Unlock your Core to let it learn."
        case "needs_you": return "Brain is paused until it has what it needs."
        case "working":
            let n = a.distilling + a.queued
            if n > 0 { return "Learning from \(n) \(n == 1 ? "place" : "places"), day and night." }
            return "Writing an overview of your places."
        default: return a.rooms == 0 ? "Nothing to learn from yet." : "Up to date. Brain keeps watching for new work."
        }
    }

    static func need(_ n: BrainActivityWire.Need) -> String {
        switch n.kind {
        case "ai_account": return "Brain needs an AI account"
        case "runner": return "Brain needs a runner that is online"
        case "local_model": return "Brain needs a local model"
        default: return "Unlock your Core"
        }
    }
}
