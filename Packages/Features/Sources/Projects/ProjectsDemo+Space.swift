#if DEBUG
import CoreKit
import Foundation

/// Debug only: the project space in every state of every kind, so each shot shows the state its name says.
extension ProjectsDemo {
    static let spaceScenes = [
        "space-app-starting", "space-app-failed", "space-infra-starting", "space-infra-failed", "space-other-docs",
        "space-other-empty", "space-web-failed", "page-sessions-empty",
    ]

    /// What the stand-in run service answers for a scene: the four setup states of the same project (id 7) differ here.
    static func configureRun(_ scene: String, _ run: DemoRunService?) {
        guard let run else { return }
        // The running project reads its services from the run engine, as a real Core serves them.
        run.services[1] = DemoLive.make(.running).services
        switch scene {
        case "space-setting-up": run.unreadable = [7]
        case "space-needs-setup": run.noSpec = [7]
        case "space-ready": run.secretsSet = [7]
        default: break
        }
    }

    private static func make(_ p: inout ProjectItem, _ kind: ProjectKind, _ name: String, _ repos: [String]) {
        p.kindName = kind.rawValue
        p.name = name
        p.repos = repos.enumerated().map {
            RepoItem(
                id: p.id * 10 + Int64($0.offset), name: $0.element,
                remoteURL: "https://github.com/tidepool-labs/\($0.element)", branch: "main", primary: $0.offset == 0,
                fetchedAt: Date().addingTimeInterval(-600), fetchError: nil)
        }
    }

    static func spaceSample(_ scene: String, _ list: inout [ProjectItem]) {
        switch scene {
        case "space-app-starting":
            make(&list[1], .app, "Tidepool Mobile", ["tidepool-ios", "tidepool-android"])
            list[1].run = RunSummary(state: .starting, services: 2)
            var l = DemoLive.make(.starting, progress: 0.4)
            l.steps = [
                StartStep(title: "Getting the code", state: .done),
                StartStep(title: "Building the app", state: .active, detail: "Debug · 12 s"),
                StartStep(title: "Running it", state: .pending),
            ]
            list[1].live = l
        case "space-app-failed":
            make(&list[2], .app, "Tidepool Mobile", ["tidepool-ios", "tidepool-android"])
            var l = DemoLive.make(.failed)
            l.failure = "The last build failed."
            l.failureFix = "Read the log, fix what stops the build, then build it again."
            l.steps = [
                StartStep(title: "Getting the code", state: .done),
                StartStep(title: "Building the app", state: .failed, detail: "error: no such module ‘Tidepool’"),
                StartStep(title: "Running it", state: .pending),
            ]
            list[2].live = l
        case "space-infra-starting":
            make(&list[1], .infra, "Tidepool Platform", ["tidepool-infra", "tidepool-os"])
            list[1].run = RunSummary(state: .starting, services: 5)
            list[1].live = DemoLive.make(.starting, progress: 0.4)
        case "space-infra-failed":
            make(&list[2], .infra, "Tidepool Platform", ["tidepool-infra", "tidepool-os"])
            var l = DemoLive.make(.failed)
            l.failure = "The gateway would not come up."
            l.failureFix = "Read the log of the gateway, then start the stack again."
            list[2].live = l
        case "space-web-failed": break
        case "space-other-docs", "space-other-empty":
            make(&list[3], .other, "Harbour Book", [])
            list[3].run = nil
            var l = DemoLive.make(.stopped)
            l.services = []
            list[3].live = l
        case "page-sessions-empty":
            list[3].live?.sessions = []
            list[3].run = RunSummary(state: .stopped, services: 0, sessions: 0, lastRun: "Mon")
        default: break
        }
    }

    func showSpace(_ scene: String) async {
        switch scene {
        case "space-app-starting", "space-infra-starting":
            model.openID = 2
            if scene == "space-infra-starting" {
                let up = { (n: String, mem: String) in
                    ProjectLive.Service(name: n, memory: mem, state: .up, health: "healthy")
                }
                (model.runService as? DemoRunService)?.services[2] = [
                    up("network", "42 MB"), up("vault", "118 MB"),
                    ProjectLive.Service(name: "queue", memory: "–", state: .down),
                ]
                await model.refreshLive(2)
            }
        case "space-app-failed", "space-infra-failed", "space-web-failed": model.openID = 3
        case "space-other-docs", "space-other-empty":
            model.lore = DemoDocsLore(scene == "space-other-docs" ? DemoDocsLore.harbour : [])
            model.openID = 4
        case "page-sessions-empty":
            model.openID = 4
            model.section = .sessions
        default: break
        }
    }
}

/// A Lore service with a few made-up docs of the demo's book project, for the docs-first Overview.
final class DemoDocsLore: LoreService, @unchecked Sendable {
    let notes: [LoreNote]
    /// Scenes: a Core that cannot list the docs.
    var failing = false
    init(_ notes: [LoreNote]) { self.notes = notes }

    static let harbour: [LoreNote] = [
        ("Chapter 1 · The harbour at dawn", "#plan\n\nThe fog lifted slowly over the breakwater, and the first ferry slid out of it as if it had been waiting all night. Mira counted the gulls on the rail and stopped at forty."),
        ("Chapter 2 · The ferry crossing", "#plan\n\nMira counted the gulls as the ferry pulled away from the quay. By the second bell the town was a line of roofs."),
        ("Research · tide tables", "Spring tides peak two days after the new moon. The harbour floods at the lower quay first."),
        ("Outline of the whole book", "#spec\n\nPart one: arrival. Part two: the storm. Part three: the long way home."),
        ("Interview notes · harbour master", "“Forty years on these docks, and I still check the sky before the clock.”"),
        ("How to publish the book", "#runbook"),
    ].enumerated().map { LoreNote(id: "d\($0.offset)", project: "4", title: $0.element.0, text: $0.element.1) }

    func today(_ day: String) async throws -> LoreNote { throw CancellationError() }
    func daily(_ day: String) async throws -> LoreNote? { nil }
    func note(_ id: String) async throws -> LoreNote {
        guard let n = notes.first(where: { $0.id == id }) else { throw CancellationError() }
        return n
    }
    func create(text: String, project: String?) async throws -> LoreNote {
        LoreNote(id: "d-new", project: project, title: "", text: text)
    }
    func save(_ id: String, baseRev: Int, text: String) async throws -> LoreSaveResult { throw CancellationError() }
    func projectNames() async throws -> [String: String] { [:] }
    func list(filter: LoreFilter) async throws -> [LoreNote] {
        if failing { throw CancellationError() }
        return notes
    }
    func backlinks(_ id: String) async throws -> [LoreBacklink] { [] }
    func versions(_ id: String) async throws -> [LoreVersion] { [] }
    func versionText(_ id: String, version: String) async throws -> String { "" }
    func restore(_ id: String, version: String) async throws -> LoreSaveResult { throw CancellationError() }
    func move(_ id: String, project: String?) async throws -> LoreNote { throw CancellationError() }
}
#endif
