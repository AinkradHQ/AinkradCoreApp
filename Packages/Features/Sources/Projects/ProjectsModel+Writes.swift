import Admin
import CoreKit
import Foundation
import Shell

/// The guards and the undo around the model's writes: one write at a time (said, never dropped), a create whose answer was
/// lost, and the undo of a half-made project.
extension ProjectsModel {
    /// False, with a toast, while another write is in flight: a tap is never silently dropped.
    func writeFree() -> Bool {
        guard busy else { return true }
        host.shell.showToast("Still saving. Try again in a moment.", kind: .warn)
        return false
    }

    /// Unarchive is a Core 0.10 route (API minor 95); `runnerSupported` is set from the same check.
    var canUnarchive: Bool { runnerSupported }

    /// The draft a closing wizard leaves: nothing once "Open project" finished it.
    func draftToKeep(_ d: WizardDraft, made: Bool) -> WizardDraft? {
        !wizardFinished && (d.hasContent || made) ? d : nil
    }

    /// Whether a failed create may still have made the project: the connection dropped, the answer could not be read, or the
    /// Core failed. Never a refusal (a taken link name, a scope): those mean nothing was made.
    static func answerLost(_ error: any Error) -> Bool {
        if LiveProjectsService.network(error) != nil { return true }
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return true }
        switch e {
        case .offline: return true
        case .http(let status, _, _): return status >= 500
        default: return false
        }
    }

    /// The project a create made when only its answer was lost: the one with the link name of the attempt that failed, the same
    /// name, and made since this create began. Nil for anything else, so a project that was already there is never taken over.
    func recoverLostCreate(
        _ error: any Error, slug: String?, name: String, since: Date, _ service: any ProjectsService
    ) async -> ProjectItem? {
        guard let slug, Self.answerLost(error) else { return nil }
        let all = (try? await service.projects()) ?? []
        // The Core's clock may differ from this Mac's by a little.
        let from = since.addingTimeInterval(-60)
        return all.first { p in
            p.slug == slug && p.name == name && (p.createdAt.map { $0 >= from } ?? false)
        }
    }

    /// Undoes a half-made project: archive, then delete for good where the Core can (API 112). Says what really happened.
    func rollBack(_ p: ProjectItem) async -> String {
        guard let service else { return "It is still in your list." }
        do { try await service.archive(project: p.id) } catch {
            if ProjectConflict.of(error) != .archived {
                return "It could not be undone (\(words(error))), so it is still in your list. Archive it from its Settings."
            }
        }
        guard core112 else { return "It was archived and left your list. This Core cannot delete projects." }
        do {
            try await service.delete(project: p.id)
            return "Nothing was left behind."
        } catch {
            return "It was archived but could not be deleted (\(words(error))). Delete it from Archived."
        }
    }
}
