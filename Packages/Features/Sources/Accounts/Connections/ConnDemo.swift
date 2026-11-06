#if DEBUG
import Foundation
import Shell
import SwiftUI

/// Debug only: every Connections state on the stand-in data, for the snapshot walk (`CORE_ACC_SNAPSHOT`) and for
/// clicking through (`CORE_ACC_DEMO=conn-list`). Nothing here reaches a Core.
extension AccountsDemo {
    public static let connScenes = [
        "conn-list", "conn-empty", "conn-pick", "conn-github-code", "conn-github-repos", "conn-jira-sites",
        "conn-failed", "conn-done", "conn-token", "conn-access", "conn-access-write", "conn-rename",
        "conn-disconnect", "conn-activity", "conn-off",
    ]

    func showConnections(_ scene: String) async {
        let m = model.connections
        let shell = m.host.shell
        shell.dialog = nil
        m.stopFlow()
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
        case "conn-github-repos": await open("github", then: .chooseResources(login: "@sample-dev"))
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
        default: break
        }
    }
}
#endif
