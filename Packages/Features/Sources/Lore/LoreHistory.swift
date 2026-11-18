// LoreHistory — backlinks, versions and the project of the open note (plan R6-04).
//
// Rename needs no code here: the Core derives a note's title from its first heading on every save (T5) and rewrites the
// links to it (R1-04), so editing the heading is the rename; `LoreModel.save` already takes the new title from the answer.
import CoreKit
import CoreUI
import Foundation
import Shell
import SwiftUI

/// The button on the notice line under the top bar.
enum LoreNoticeAction: Equatable {
    /// A save kept the other text as this version (T2): open the versions sheet on it.
    case seeChanges(String)
    /// A restore replaced the text; this version is the text it replaced.
    case undoRestore(String)
}

extension LoreModel {
    /// Restore a version: unsent text goes up first, so Undo brings that back too.
    func restore(_ version: String, offerUndo: Bool = true) async {
        guard let service, let id = note?.id else { return }
        await leave()
        do {
            let r = try await service.restore(id, version: version)
            adopt(r.note)
            if offerUndo, let undo = r.version {
                notice = "Restored"
                noticeAction = .undoRestore(undo)
            } else {
                notice = offerUndo ? "That is already the current text." : nil
            }
        } catch { say(error) }
    }

    /// The project chip: personal or a project. A daily note stays personal.
    func move(to project: String?) async {
        guard let service, let n = note, n.kind == "note", n.project != project else { return }
        do {
            moved(try await service.move(n.id, project: project))
            host.shell.showToast("Moved to \(projectName).", kind: .info)
        } catch { say(error) }
    }

    func showVersions(selecting: String? = nil) {
        guard note != nil else { return }
        host.shell.present(ShellDialog(id: "lore-versions") { LoreVersionsSheet(model: self, selecting: selecting) })
    }

    /// Projects for the chip menu, by name.
    var projectChoices: [(id: String, name: String)] {
        projectNames.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum LoreVersionWords {
    static func title(_ v: LoreVersion) -> String {
        switch v.kind {
        case "named": (v.name?.isEmpty == false ? v.name : nil) ?? "Named version"
        case "conflict": "Kept when two edits met"
        default: "Saved automatically"
        }
    }

    static func detail(_ v: LoreVersion) -> String {
        let who = v.origin.hasPrefix("session:") ? "AI session" : v.origin.hasPrefix("person:") ? "You" : "Lore"
        guard let d = date(v.createdAt) else { return who }
        return "\(d.formatted(.relative(presentation: .named, unitsStyle: .wide))) · \(who)"
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
