#if DEBUG
import CoreKit
import Foundation
import Shell
import SwiftUI

/// Debug only: every Connections state on the stand-in data, for the snapshot walk (`CORE_ACC_SNAPSHOT`) and for
/// clicking through (`CORE_ACC_DEMO=conn-list`). Nothing here reaches a Core.
extension AccountsDemo {
    public static let connScenes = [
        "conn-list", "conn-empty", "conn-pick", "conn-github-code", "conn-github-repos", "conn-jira-sites",
        "conn-failed", "conn-done", "conn-token", "conn-access", "conn-access-write", "conn-rename",
        "conn-disconnect", "conn-activity", "conn-off", "conn-app-notset", "conn-app-set", "conn-app-saving",
        "conn-app-error", "conn-app-readonly", "conn-default-menu", "conn-default-cleared", "conn-replace",
        "conn-replace-working", "conn-replace-error", "conn-replace-done",
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
        m.page = scene == "conn-activity" ? .activity : .list
        m.opener = { _ in }
        m.pollEvery = .seconds(3600)  // the scenes set each step themselves
        let svc = SampleConnections(empty: scene == "conn-empty")
        if scene == "conn-off" { m.detach() } else { m.use(svc, sample: true) }
        m.show(m.page)
        try? await Task.sleep(for: .milliseconds(500))
        func open(_ kind: String?, then step: ConnFlow.Step? = nil) async {
            ConnDialogs.openConnect(m, kind: kind)
            guard let step, kind != nil else { return }
            try? await Task.sleep(for: .milliseconds(400))
            m.flow?.step = step
        }
        switch scene {
        case "conn-pick": await open(nil)
        case "conn-github-code": await open("github")
        case "conn-github-repos":
            await open(
                "github", then: .chooseResources(login: "@sample-dev", install: URL(string: "https://github.com/apps")!)
            )
        case "conn-jira-sites": await open("jira", then: .pickSite(["sample.atlassian.net", "other.atlassian.net"]))
        case "conn-failed":
            await open(
                "github",
                then: .failed(
                    title: "The code ran out before you approved it.",
                    fix: "Codes work for 15 minutes. Try again for a new code, then approve it on github.com."))
        case "conn-done": await open("github", then: .connected(1))
        case "conn-token":
            shell.present(
                ShellDialog(id: "connection-connect") {
                    TokenForm(model: m, kind: SampleConnections.kinds[1], back: {}, close: {})
                })
        case "conn-access", "conn-access-write":
            if scene == "conn-access-write" {
                try? await svc.setAccess(1, allowed: ["read", "write"], only: ["sample/core", "sample/app"])
            }
            await m.reload()
            if let c = m.item(1) { ConnDialogs.openAccess(m, c) }
        case "conn-rename": if let c = m.item(1) { ConnDialogs.openRename(m, c) }
        case "conn-disconnect": if let c = m.item(2) { ConnDialogs.openDisconnect(m, c) }
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
        case "conn-default-menu", "conn-default-cleared":
            if scene == "conn-default-cleared", let c = m.item(1) { await m.clearDefault(c) }
            m.cursor = 1
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
