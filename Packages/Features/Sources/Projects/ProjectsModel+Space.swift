import AppKit
import CoreUI
import Foundation
import Shell
import SwiftUI

/// What the space around a project needs from the model beyond the Core's data: unsaved drafts and leaving the space.
extension ProjectsModel {
    func setDraft(_ id: Int64, dirty: Bool) {
        if dirty { drafts.insert(id) } else { drafts.remove(id) }
    }

    /// Leaves the space (Esc, Back): at once, or after asking when Settings holds changes that are not saved.
    func leaveSpace(_ id: Int64, _ leave: @escaping () -> Void) {
        guard drafts.contains(id) else { return leave() }
        let shell = host.shell
        shell.present(
            ShellDialog(id: "project-discard") {
                CoreConfirmDialog(
                    "Leave without saving?", message: "The changes you made in Settings are not saved yet.",
                    confirmTitle: "Discard Changes", destructive: true,
                    onConfirm: { [weak self] in
                        shell.closeDialog()
                        self?.drafts.remove(id)
                        leave()
                    }, onCancel: { shell.closeDialog() })
            })
    }
}

/// Where "Open" takes a project's site.
enum SiteTarget: Equatable {
    /// The public link, in the browser.
    case browser(URL)
    /// The private preview on the Live site page: the link is for the person's own devices only.
    case preview
    case none
}

extension ProjectsModel {
    /// The public link opens in the browser only when the project is public; a private one opens its preview in the space.
    func siteTarget(_ p: ProjectItem) -> SiteTarget {
        if p.expose { return URL(string: "https://\(p.link)").map(SiteTarget.browser) ?? .none }
        return ProjectModule.rail(for: p.allKinds).contains(.live) ? .preview : .none
    }

    func openSite(_ p: ProjectItem) {
        switch siteTarget(p) {
        case .browser(let url): NSWorkspace.shared.open(url)
        case .preview: go(.live, in: p.id)
        case .none:
            host.shell.showToast(
                "\(p.name) is only for your devices. Turn the public link on in Settings to open it in a browser.",
                kind: .warn)
        }
    }
}
