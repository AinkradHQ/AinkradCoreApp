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
