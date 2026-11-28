import CoreUI
import SwiftUI

/// Project details v2 (approved mockup `Designs/core/projects/details-v2.html`, 2026-11-28): a header, a stage and modules
/// on the Overview, and a thin icon rail where each module opens as its own focused page. Which modules a project has
/// follows its kinds; a project can have several (web + app).
enum ProjectModule: String, CaseIterable, Identifiable, Sendable {
    case overview, live, builds, services, docs, logs, run, ai, brain, repos, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .live: "Live site"
        case .builds: "Builds"
        case .services: "Services"
        case .docs: "Documents"
        case .logs: "Logs"
        case .run: "Run setup"
        case .ai: "AI Sessions"
        case .brain: "Brain"
        case .repos: "Repos"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .live: "macwindow"
        case .builds: "hammer"
        case .services: "server.rack"
        case .docs: "doc.text"
        case .logs: "text.alignleft"
        case .run: "gearshape.2"
        case .ai: "sparkles"
        case .brain: "brain"
        case .repos: "arrow.triangle.branch"
        case .activity: "waveform.path.ecg"
        case .settings: "slider.horizontal.3"
        }
    }

    /// The rail's tooltip: what the page is for, starting with a verb.
    var help: String {
        switch self {
        case .overview: "See the project at a glance"
        case .live: "Open the live site full size"
        case .builds: "See every build, its steps and its files"
        case .services: "See each service, its health and its use"
        case .docs: "Read and write the project's documents"
        case .logs: "Read and search the logs"
        case .run: "Set up how it runs: configurations, environments, secrets and history"
        case .ai: "See the AI sessions of this project"
        case .brain: "See what the Brain knows about this project"
        case .repos: "See the repos, their branches and copies"
        case .activity: "See what happened, newest first"
        case .settings: "Change the name, types, running and link"
        }
    }

    /// The rail, top to bottom, for a project of these kinds (Settings sits apart at the foot of the rail).
    static func rail(for kinds: [ProjectKind]) -> [ProjectModule] {
        var out: [ProjectModule] = [.overview]
        if kinds.contains(.web) { out.append(.live) }
        if kinds.contains(.app) { out.append(.builds) }
        if kinds.contains(.web) || kinds.contains(.infra) { out.append(.services) }
        if kinds.contains(.other) { out.append(.docs) }
        if kinds.contains(where: \.runs) { out += [.logs, .run] }
        out += [.ai, .brain, .repos, .activity]
        return out
    }
}

extension ProjectModule {
    /// The ⌘ digit of the rail's `index`th item: 1 to 9, and none after that (a tenth would share ⌘0 with the eleventh).
    static func key(at index: Int) -> Int? { index < 9 ? index + 1 : nil }
}

extension ProjectItem {
    /// Every kind the project has, first one first: `kinds` from a Core with API 112, else the one `kind`.
    var allKinds: [ProjectKind] { kinds.isEmpty ? [kind] : kinds }
}
