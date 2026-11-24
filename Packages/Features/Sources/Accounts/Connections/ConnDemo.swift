#if DEBUG
import CoreKit
import Foundation
import Shell
import SwiftUI

/// Debug only: every Connections state on the stand-in data, for the snapshot walk (`CORE_ACC_SNAPSHOT`) and for
/// clicking through (`CORE_ACC_DEMO=conn-list`). Nothing here reaches a Core.
extension AccountsDemo {
    public static let connScenes = [
        // The mockup's states (10-connections): the list, the empty page, the five steps, the error.
        "conn-list", "conn-empty", "conn-add-1", "conn-add-2", "conn-add-2-code", "conn-add-2-jira", "conn-add-3",
        "conn-add-3-write",
        "conn-add-4", "conn-add-4-error", "conn-add-5", "conn-error", "conn-jira-sites", "conn-off",
        // Around it: a token instead, rename, the app registration, replacing a token, the refusals.
        "conn-token", "conn-rename", "conn-app-notset", "conn-app-set", "conn-app-saving", "conn-app-error",
        "conn-app-readonly", "conn-replace", "conn-replace-working", "conn-replace-error", "conn-replace-done",
        "conn-error-service", "conn-error-signin-first", "conn-error-signin-again",
    ]

    func showConnections(_ scene: String) async {
        let m = model.connections
        let shell = m.host.shell
        shell.dialog = nil
        shell.overlay = nil  // Settings or another overlay must not sit over the pane
        shell.launcherOpen = false
        m.stopFlow()
        m.busy = nil
        m.writeError = [:]
        m.filter = .all
        m.opener = { _ in }
        m.pollEvery = .seconds(3600)  // the scenes set each step themselves
        let svc = SampleConnections(empty: scene == "conn-empty")
        if scene == "conn-off" { m.detach() } else { m.use(svc, sample: true) }
        m.show()
        try? await Task.sleep(for: .milliseconds(500))
        /// Opens the Add dialog on a service and sets the sign-in to `step` (the scene can't wait for a browser).
        func open(_ kind: String, then step: ConnFlow.Step? = nil) async {
            m.beginAdd(kind: kind)
            guard let step else { return }
            try? await Task.sleep(for: .milliseconds(400))
            m.flow?.step = step
        }
        /// The dialog on step `at` for a connection that is there.
        func edit(_ id: Int64, at step: ConnStep, write: Bool = false) async {
            guard let c = m.item(id) else { return }
            if write {
                try? await svc.setAccess(id, allowed: ["read_repo", "pr_write", "push"], only: ["maple/harbor-web"])
            }
            await m.reload()
            m.beginEdit(m.item(id) ?? c, at: step)
        }
        switch scene {
        case "conn-add-1": m.beginAdd()
        case "conn-add-2": await open("github")
        case "conn-add-2-jira": await open("jira")
        case "conn-add-2-code":
            await open("github")
            try? await Task.sleep(for: .milliseconds(400))
        case "conn-add-3": await edit(1, at: .allow)
        case "conn-add-3-write": await edit(1, at: .allow, write: true)
        case "conn-add-4", "conn-add-4-error":
            svc.failPicks = scene == "conn-add-4-error"
            await edit(1, at: .choose)
        case "conn-add-5":
            await edit(1, at: .choose)
            try? await Task.sleep(for: .milliseconds(300))
            m.add?.picked = ["maple/harbor-web", "maple/notes-app"]
            m.add?.step = .done
        case "conn-error", "conn-error-service":
            await open(
                "github",
                then: scene == "conn-error"
                    ? .failed(title: ConnSay.expiredTitle, fix: "Try again for a new one.")
                    : .failed(title: ConnSay.serviceDown, fix: "Nothing was connected."))
        case "conn-jira-sites": await open("jira", then: .pickSite(["maple.atlassian.net", "other.atlassian.net"]))
        case "conn-error-signin-first", "conn-error-signin-again":
            await open(
                "github",
                then: .failed(
                    title: scene == "conn-error-signin-first" ? ConnSay.signInFirst : ConnSay.signInAgain,
                    fix: "Press Try again to sign in."))
        case "conn-token":
            shell.present(
                ShellDialog(id: "connection-connect") {
                    TokenForm(model: m, kind: SampleConnections.kinds[1], back: {}, close: {})
                })
        case "conn-rename": if let c = m.item(1) { ConnDialogs.openRename(m, c) }
        case "conn-app-notset", "conn-app-set", "conn-app-saving", "conn-app-error", "conn-app-readonly":
            svc.appReadOnly = scene == "conn-app-readonly"
            if let k = m.kind(scene == "conn-app-notset" ? "jira" : "github") {
                ConnDialogs.openApp(m, k)
                try? await Task.sleep(for: .milliseconds(500))
                // Saving needs Touch ID, which a scene can't do: show the model state it would be in.
                if scene == "conn-app-saving" { m.busy = "app-\(k.id)" }
                if scene == "conn-app-error" {
                    m.writeError["app-\(k.id)"] = ConnSay.plain(CoreError.http(status: 500, code: "x", message: ""))
                }
            }
        case "conn-replace", "conn-replace-working", "conn-replace-error", "conn-replace-done":
            guard let c = m.item(2) else { break }
            ConnDialogs.openReplace(m, c, done: scene == "conn-replace-done")
            try? await Task.sleep(for: .milliseconds(400))
            if scene == "conn-replace-working" { m.busy = "replace-\(c.id)" }
            if scene == "conn-replace-error" {
                m.writeError["replace-\(c.id)"] = ConnSay.plain(
                    CoreError.http(status: 400, code: "bad_token", message: "Atlassian says this token has expired"))
            }
        default: break
        }
    }
}
#endif
