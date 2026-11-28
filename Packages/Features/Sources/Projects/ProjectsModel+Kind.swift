import Foundation

/// What the Projects app does with the project kind (Core API 111): read it, and change it in Settings.
extension ProjectsModel {
    /// The kind the Core holds, else the one chosen on this Mac, else web.
    func kind(_ p: ProjectItem) -> ProjectKind {
        p.kindName.flatMap(ProjectKind.init(rawValue:)) ?? kinds.kind(p.slug) ?? .web
    }

    /// A kind picked in Settings: saved on the Core when it holds kinds (one Touch ID, like every change), else a choice of this
    /// Mac, as the colour is on an older Core.
    func setKind(_ k: ProjectKind, for p: ProjectItem) {
        guard k != kind(p) else { return }
        guard core111, service != nil else {
            kinds.set(k, for: p.slug)
            reapply(p.id)
            return
        }
        Task {
            if await change(p, ProjectPatch(kind: k.rawValue), why: "Change what \(p.name) is.") {
                kinds.set(k, for: p.slug)
            }
        }
    }
}

/// The old page names, kept so callers and the demo that say `section` keep working: the page is `module` (details v2).
extension ProjectsModel {
    var section: ProjectSection {
        get {
            switch module {
            case .overview, .activity: .overview
            case .live, .builds, .services, .logs: .run
            case .docs: .docs
            case .ai: .sessions
            case .brain: .brain
            case .repos: .repos
            case .settings: .settings
            }
        }
        set {
            module =
                switch newValue {
                case .overview: .overview
                case .run: .logs
                case .repos: .repos
                case .sessions: .ai
                case .brain: .brain
                case .settings: .settings
                case .docs: .docs
                }
        }
    }
}
