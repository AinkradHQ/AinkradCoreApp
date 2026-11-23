import CoreUI
import Foundation
import Shell

/// The redesign's actions that speak to the person: Forget with Undo in the toast, and the To check answers.
extension BrainModel {
    /// Takes a record out of memory (archived, never deleted); the toast's Undo puts it back.
    func forget(_ r: BrainAreaRecordWire) {
        Task {
            guard await calm.forget(r) else { return }
            forgotten(room: r.room, id: r.id)
        }
    }

    func forget(_ l: BrainCalmModel.Learned) {
        Task {
            guard await calm.undo(l) else { return }
            forgotten(room: l.room, id: l.id)
        }
    }

    private func forgotten(room: String, id: String) {
        let calm = calm
        host.shell.showToast("Forgotten · kept in the archive") { Task { await calm.restore(room: room, id: id) } }
    }

    /// What To check asks, in order: the ones put off with Later come last.
    var checkQueue: [InboxCandidate] {
        let later = calm.later
        let items = candidates.items
        return items.filter { !later.contains($0.id) } + later.compactMap { id in items.first { $0.id == id } }
    }

    enum CheckAnswer { case keep, drop, later }

    /// One answer on To check. A duplicate's Keep makes one (this copy goes), its Not Right keeps both.
    func answer(_ c: InboxCandidate, _ a: CheckAnswer) async {
        switch a {
        case .later:
            calm.answered(c.id, later: true)
            host.shell.showToast("Asked again later", kind: .info)
        case .keep, .drop:
            let keep = (a == .keep) != (c.reason == "duplicate")
            let done = keep ? await candidates.accept(c.id) : await candidates.reject(c.id)
            if done { calm.answered(c.id, later: false) }
        }
    }
}

/// Why To check asks, in words.
enum CheckWords {
    static func why(_ reason: String?) -> String? {
        switch reason {
        case "conflict": "Two sessions disagree"
        case "single_source": "Seen once"
        case "duplicate": "Looks like a duplicate"
        default: nil
        }
    }

    static func question(_ c: InboxCandidate) -> String {
        switch c.reason {
        case "conflict": "Is this still right?"
        case "duplicate": "Same thing twice?"
        default: c.kind == .rule ? "Keep this rule?" : "Keep this?"
        }
    }

    static func context(_ c: InboxCandidate) -> String? {
        switch c.reason {
        case "conflict": c.otherBody.map { "Another session said: “\($0)”. Brain is not sure which is true now." }
        case "single_source": "Learned from one session only, so Brain checks with you first."
        case "duplicate": c.otherBody.map { "Brain already knows “\($0)”, and thinks these say the same thing." }
        default: c.sources.first.map { "From \($0.title)" }
        }
    }
}
