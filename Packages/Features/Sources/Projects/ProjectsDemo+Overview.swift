#if DEBUG
import CoreKit
import Foundation

/// Debug only: the details v2 Overview of every kind in every state (`ov-<kind>-<state>`), project 1 each time.
extension ProjectsDemo {
    static let overviewKinds = ["web", "app", "infra", "other", "webapp"]
    static let overviewStates = ["running", "starting", "stopped", "failed"]
    static let overviewScenes = overviewKinds.flatMap { k in overviewStates.map { "ov-\(k)-\($0)" } }

    private static func parts(_ scene: String) -> (kind: String, state: RunSummary.State)? {
        let p = scene.split(separator: "-").map(String.init)
        guard p.count == 3, p[0] == "ov", overviewKinds.contains(p[1]) else { return nil }
        let state: RunSummary.State =
            switch p[2] {
            case "starting": .starting
            case "stopped": .stopped
            case "failed": .failed
            default: .running
            }
        return (p[1], state)
    }

    private static func repos(_ p: inout ProjectItem, _ names: [String]) {
        p.repos = names.enumerated().map {
            RepoItem(
                id: p.id * 10 + Int64($0.offset), name: $0.element,
                remoteURL: "https://github.com/tidepool-labs/\($0.element)", branch: "main", primary: $0.offset == 0,
                fetchedAt: Date().addingTimeInterval(-600), fetchError: nil)
        }
    }

    static func overviewSample(_ scene: String, _ list: inout [ProjectItem]) {
        guard let (kind, state) = parts(scene) else { return }
        var p = list[0]
        p.kinds =
            switch kind {
            case "webapp": [.web, .app]
            default: [ProjectKind(rawValue: kind) ?? .web]
            }
        p.kindName = p.kinds[0].rawValue
        let n = state == .running ? 5 : 5
        var live = DemoLive.make(state, progress: 0.4)
        live.metrics = state == .running ? DemoLive.metrics() : [:]
        switch kind {
        case "app", "webapp":
            if kind == "app" {
                p.name = "Tidepool Mobile"
                p.description = "Order tracking for couriers"
                repos(&p, ["tidepool-ios", "tidepool-android"])
            } else {
                repos(&p, ["lanterna-web", "lanterna-ios"])
            }
            let step = { (t: String, s: RunStep.State, d: String?) in StartStep(title: t, state: s, detail: d) }
            switch state {
            case .running:
                live.steps = [
                    step("Getting the code", .done, nil), step("Building for iOS", .done, "41 s"),
                    step("Signing", .done, nil), step("Installing on the simulator", .done, nil),
                ]
            case .starting:
                live.steps = [
                    step("Getting the code", .done, nil), step("Building for iOS", .active, nil),
                    step("Signing", .pending, nil), step("Installing on the simulator", .pending, nil),
                ]
            case .failed:
                live.failure = "The last build failed."
                live.failureFix = "Read the log, fix what stops the build, then build it again."
                live.steps = [
                    step("Getting the code", .done, nil),
                    step("Building for iOS", .failed, "error: no such module ‘Tidepool’"),
                    step("Signing", .pending, nil), step("Installing on the simulator", .pending, nil),
                ]
            case .stopped: live.steps = []
            }
        case "infra":
            p.name = "Harbor Platform"
            p.description = "The servers behind it all"
            repos(&p, ["harbor-infra", "harbor-os"])
            p.draft = RunDraft(source: "main.tf", services: ["gateway", "api", "queue", "db", "vault"], secrets: [])
        case "other":
            p.name = "Harbour Book"
            p.description = "Research and chapters for the harbour book"
            repos(&p, [])
        default: break
        }
        if state == .failed, kind != "app", kind != "other" {
            p.draft = RunDraft(
                source: "docker-compose.yml", services: ["web", "api", "queue", "mysql", "redis"],
                secrets: ["STRIPE_SECRET"])
        }
        if kind == "other" {
            p.run = nil
            live.services = []
            live.logs = []
        } else {
            p.run = RunSummary(
                state: state, services: n, sessions: 4, lastRun: state == .stopped ? "yesterday" : nil)
        }
        p.live = live
        list[0] = p
    }

    func showOverviewScene(_ scene: String) async {
        guard let (kind, state) = Self.parts(scene) else { return }
        let svc = DemoLive.make(state, progress: 0.4).services
        if kind == "infra" {
            let h = { (n: String, m: String, st: ProjectLive.Service.State, health: String, r: Int) in
                ProjectLive.Service(name: n, memory: m, state: st, restarts: r, health: health)
            }
            let up: ProjectLive.Service.State = state == .running ? .up : .down
            (model.runService as? DemoRunService)?.services[1] = [
                h("gateway", "41 MB", state == .failed ? .exited : up, "healthy", state == .failed ? 3 : 0),
                h("api", "148 MB", state == .starting ? .up : up, "healthy", 0),
                h("queue", "96 MB", up, state == .running ? "unhealthy" : "healthy", 0),
                h("db", "402 MB", state == .starting ? .up : up, "healthy", 0),
                h("vault", "118 MB", up, "healthy", 0),
            ]
        } else {
            (model.runService as? DemoRunService)?.services[1] = svc
        }
        if kind == "other" {
            // A docs project has no run: its four states are what the Docs hold (many, a few, none, unreadable).
            let docs = DemoDocsLore(
                state == .running ? DemoDocsLore.harbour : state == .starting ? Array(DemoDocsLore.harbour.prefix(2)) : [])
            docs.failing = state == .failed
            model.lore = docs
        }
        model.openID = 1
        await model.refreshLive(1)
    }
}
#endif
