import AppKit
import CoreKit
import Foundation
import Shell

/// What a gallery card can do (hover buttons and the context menu), each said with its reason when it cannot.
extension ProjectsModel {
    /// Why Start cannot be used on this project now, in words; nil when it can.
    func startBlock(_ p: ProjectItem) -> String? {
        if p.archived { return "Unarchive it first." }
        if readOnly { return "This device can look at projects but not change them." }
        if p.repos.isEmpty { return "Add a repo first." }
        if service == nil { return "Connect this Mac to a Core first." }
        if controlling.contains(p.id) { return "Working on it…" }
        return nil
    }

    var isRunningOrStarting: (ProjectItem) -> Bool { { $0.tag == .running || $0.tag == .starting } }

    /// Start, or Stop when it runs: the run routes the model already has.
    func toggleRun(_ p: ProjectItem) {
        if isRunningOrStarting(p) { control(.stop, p) } else { control(.start, p) }
    }

    func copyLink(_ p: ProjectItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://\(p.link)", forType: .string)
        host.shell.showToast("Link copied")
    }

    /// Archive, with the question first on a Core that cannot undo it.
    func requestArchive(_ p: ProjectItem) {
        if insightsService == nil { confirmArchive(p) } else { Task { await archive(p) } }
    }
}
