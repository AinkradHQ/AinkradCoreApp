import Foundation
import Observation

/// The Checks tab's state. It starts runs, shows their progress and displays what the service returns. It never decides a
/// result and never clears Paused by itself: a passing re-run leaves Paused as it is; only `BrainModel.clearPaused` does.
@MainActor @Observable
public final class ChecksModel {
    public enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }

    @ObservationIgnored weak var brain: BrainModel?
    public internal(set) var phase: Phase = .loading
    public private(set) var report = ChecksReport(items: [], pilot: [])
    /// Checks running now, with progress 0 to 1.
    public private(set) var running: [String: Double] = [:]
    public var selectedID = "leakage"
    @ObservationIgnored private var started = false

    init(brain: BrainModel) { self.brain = brain }

    public var items: [CheckItem] { report.items.filter { !$0.housekeeping } }
    public var housekeeping: [CheckItem] { report.items.filter(\.housekeeping) }
    public var selected: CheckItem? { report.items.first { $0.id == selectedID } ?? report.items.first }
    public var anyRunning: Bool { !running.isEmpty }
    public var summary: String {
        BrainWords.checksSummary(
            failed: report.items.filter { $0.outcome == .fail }.count,
            due: report.items.filter { $0.outcome == .due || $0.outcome == .never }.count)
    }

    public func state(_ c: CheckItem) -> CheckState {
        if running[c.id] != nil { return .running }
        if c.skippedOffline { return .skipped }
        switch c.outcome {
        case .pass: return .pass
        case .fail: return .fail
        case .due: return .due
        case .never: return .never
        }
    }

    /// The one sentence under a check's name.
    public func sentence(_ c: CheckItem) -> String {
        switch state(c) {
        case .skipped: BrainWords.checksSkipped
        case .never: BrainWords.checksNever
        default: c.about
        }
    }

    func reset() {
        started = false
        report = ChecksReport(items: [], pilot: [])
        running = [:]
        selectedID = "leakage"
        phase = .loading
    }

    public func enter() {
        guard !started else { return }
        started = true
        Task { await load() }
    }

    public func load() async {
        guard let service = brain?.service else { return }
        do {
            report = try await service.checks()
            phase = .ready
        } catch {
            phase = .failed(BrainWords.failure(error))
        }
    }

    public func retry() {
        phase = .loading
        Task { await load() }
    }

    /// Runs one check. A check already running is left alone.
    public func run(_ id: String, options: CheckRunOptions = .standard) async {
        guard let service = brain?.service, running[id] == nil else { return }
        running[id] = 0
        defer { running[id] = nil }
        do {
            let done = try await service.runCheck(id, options: options) { [weak self] p in
                Task { @MainActor in self?.progress(id, p) }
            }
            if let i = report.items.firstIndex(where: { $0.id == id }) { report.items[i] = done }
            let name = done.name
            if done.skippedOffline {
                brain?.host.shell.showToast("\(name) was skipped: this Mac is offline.", kind: .warn)
            } else if done.outcome == .fail {
                brain?.host.shell.showToast("\(name) failed.", kind: .error)
            } else {
                brain?.host.shell.showToast("\(name) passed.", kind: .ok)
            }
            // The service may have paused search or settled something; read the pane again.
            await brain?.reload()
            await load()
        } catch {
            brain?.host.shell.showToast(BrainWords.failure(error), kind: .error)
        }
    }

    public func runAll(_ ids: [String]? = nil, options: CheckRunOptions = .standard) async {
        let list = ids ?? report.items.map(\.id)
        let tasks = list.map { id in Task { @MainActor in await self.run(id, options: options) } }
        for t in tasks { await t.value }
    }

    private func progress(_ id: String, _ p: Double) {
        guard let old = running[id] else { return }
        running[id] = max(old, min(p, 1))
    }
}
