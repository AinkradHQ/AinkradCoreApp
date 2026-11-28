import Brain
import CoreKit
import Foundation

/// What the Core says of a project's setup: the run spec, as the "ready to start" line shows it. `draft` is nil when the project
/// has no spec yet.
struct SetupRead: Equatable, Sendable {
    var draft: RunDraft?
}

/// What the Overview's islands show of a project, read from the Core: the run's services, the project's AI sessions and its
/// Brain room, and whether its run crashed until the Core gave up restarting it.
struct LiveParts: Equatable, Sendable {
    var services: [ProjectLive.Service] = []
    var sessions: [ProjectLive.Session] = []
    var room: ProjectLive.Room?
    var roomID: String?
    var crashLoop = false
    var metrics: [String: ServiceSeries] = [:]
}

/// The Core is read for what the Overview shows, instead of the stand-in data the Debug demo fills.
extension ProjectsModel {
    // MARK: setup

    /// The setup of one project: nil when the Core could not say (it stays "checking" rather than guessing).
    static func readSetup(_ service: (any ProjectRunService)?, _ id: Int64) async -> SetupRead? {
        guard let service else { return nil }
        do {
            guard let spec = try await service.spec(project: id) else { return SetupRead(draft: nil) }
            // Listing secrets can be refused (admin); then what is missing is not known, and nothing is claimed missing.
            let stored = (try? await service.secrets(project: id)).map { Set($0.map(\.name)) }
            let missing = stored.map { s in spec.secretNames.filter { !s.contains($0) } } ?? []
            return SetupRead(
                draft: RunDraft(
                    source: spec.source, services: spec.services.map(\.name), secrets: missing, manual: !spec.drafted))
        } catch { return nil }
    }

    func refreshSetup(_ id: Int64) async {
        guard let r = await Self.readSetup(runService, id) else { return }
        setupStates[id] = r
        reapply(id)
    }

    // MARK: live parts

    /// Reads the open project's services (while it runs), AI sessions, Brain room and crash history.
    func refreshLive(_ id: Int64) async {
        var parts = liveParts[id] ?? LiveParts()
        if let state = project(id)?.run?.state, state == .running || state == .starting {
            if let s = try? await runService?.services(project: id) { parts.services = s }
            if core110, let m = try? await runService?.metrics(project: id) { parts.metrics = m }
        } else {
            parts.services = []
            parts.metrics = [:]
        }
        do {
            if let s = try await service?.sessions(project: id) { parts.sessions = s }
            liveFailures[id, default: [:]]["sessions"] = nil
        } catch { liveFailures[id, default: [:]]["sessions"] = words(error) }
        if let ins = insightsService, let t = try? await ins.tuning(project: id) {
            parts.roomID = t.roomID
            do {
                if let room = t.roomID, let o = try await ins.roomOverview(room: room) {
                    parts.room = Self.room(o, now: now())
                } else {
                    parts.room = nil
                }
                liveFailures[id, default: [:]]["room"] = nil
            } catch {
                parts.room = nil
                liveFailures[id, default: [:]]["room"] = words(error)
            }
        }
        if let cfg = configsService {
            if let names = try? await cfg.runners() { for r in names { runnerNames[r.id] = r.name } }
            if let runs = try? await cfg.history(project: id) { parts.crashLoop = CrashLoop.detect(runs, now: now()) }
        }
        liveParts[id] = parts
        reapply(id)
    }

    /// The Brain's overview as the Overview's Brain island shows it; nil until it is written.
    static func room(_ o: RoomOverview, now: Date) -> ProjectLive.Room? {
        guard o.overview != nil else { return nil }
        func ago(_ s: String?) -> String { RunWire.date(s).map { PickRepo.ago($0, now) } ?? "" }
        return ProjectLive.Room(
            overview: o, items: o.picked ?? 0, updated: ago(o.writtenAt), approved: ago(o.instructionsApprovedAt))
    }

    func reapply(_ id: Int64) {
        if let i = projects.firstIndex(where: { $0.id == id }) { projects[i] = applying(projects[i]) }
    }

    // MARK: the Core not answering

    var isStale: Bool {
        coreSilent || host.shell.coreLink == .offline || host.shell.coreLink == .reconnecting
    }

    /// Shows (or stops showing) that the run state is how the Core last said it, not how it is now.
    func markSilent(_ silent: Bool) {
        guard silent != coreSilent else { return }
        coreSilent = silent
        projects = projects.map(applying)
    }

    // MARK: names

    func runnerName(_ id: String?) -> String? { id.map { runnerNames[$0] ?? $0 } }

    // MARK: AI sessions

    func canStartSession(_ p: ProjectItem) -> Bool {
        sessionStarter != nil && (!p.repos.isEmpty || core111) && !p.archived && !readOnly && !startingSession.contains(p.id)
    }

    func sessionBlock(_ p: ProjectItem) -> String {
        if p.archived { return "An archived project cannot start AI sessions." }
        if p.repos.isEmpty && !core111 {
            return p.kind == .other
                ? "This Core starts an AI session in a project's repos, so add a repo (a notes or docs repo is fine) first."
                : "Add a repo first. A session works in a copy of the project's repos."
        }
        if readOnly { return "This device can look at projects but not change them." }
        if sessionStarter == nil { return "Connect to a Core to start an AI session." }
        return p.repos.isEmpty
            ? "Start an AI session in its own folder, with \(p.name)'s Brain room"
            : "Start an AI session in its own copy of \(p.name)'s repos"
    }

    /// The first message of an "Ask AI to Fix" session: what failed and what the Core said, so it starts from the failure.
    static func fixPrompt(project: String, what: String, details: [String?]) -> String {
        let facts = details.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        return "\(what) of \(project) failed." + (facts.isEmpty ? "" : "\n\n\(facts)")
            + "\n\nLook at why it failed and propose a fix."
    }

    /// New AI Session in the project: a session in its own clone, opened in AI Sessions.
    /// `prompt` is the session's first message (Ask AI to Fix says what failed); one start per project at a time.
    func newSession(in p: ProjectItem, prompt: String = "") {
        guard canStartSession(p), let start = sessionStarter else { return }
        startingSession.insert(p.id)
        Task {
            defer { startingSession.remove(p.id) }
            if let why = await start(p.id, prompt) {
                host.shell.showToast(why, kind: .warn)
            } else {
                await refreshLive(p.id)
            }
        }
    }
}

/// A run that came up and fell over until the Core stopped restarting it (`project.run_gave_up`): several crashes of one
/// configuration within ten minutes and nothing live of it.
enum CrashLoop {
    static let window: TimeInterval = 600
    static let tries = 3

    static func detect(_ runs: [RunRecord], now: Date) -> Bool {
        let byConfig = Dictionary(grouping: runs, by: { $0.configID ?? -1 })
        return byConfig.values.contains { list in
            guard !list.contains(where: \.live) else { return false }
            let ends = list.filter { $0.stopReason == "crash" }.compactMap { $0.stoppedAt ?? $0.startedAt }
                .filter { now.timeIntervalSince($0) < window * 3 }
            guard ends.count >= tries, let newest = ends.max(), let oldest = ends.min() else { return false }
            return newest.timeIntervalSince(oldest) <= window
        }
    }
}
