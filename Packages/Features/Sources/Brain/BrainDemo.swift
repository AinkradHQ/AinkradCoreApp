#if DEBUG
import AppKit
import Foundation
import Shell

/// Debug only: every Brain state of the approved prototype on the sample service, for screenshots and for clicking
/// through. Nothing here reaches a Core; every number is invented and the pane says so on every screen.
@MainActor
public final class BrainDemo {
    let model: BrainModel
    public init(model: BrainModel) { self.model = model }

    public static let scenes = [
        "overview", "overview-healthy", "overview-paused", "rooms", "room", "new-room", "sealed", "unavailable",
        "activity", "activity-blocked", "egress",
        "egress-local", "activity-empty", "activity-error", "checks", "checks-running", "checks-paused",
        "checks-offline",
        "empty", "error", "offline", "rebuilding", "embedding-down", "inbox",
        "inbox-conflict", "inbox-blocked", "inbox-noroom", "inbox-assign", "inbox-empty", "inbox-sealed", "inbox-error",
        "inbox-offline",
    ]

    private func inbox(_ list: InboxList, room: String? = nil) async {
        model.show(.inbox)
        if let room { model.view(room) }
        model.inboxState.list = list
        await model.loadInbox()
    }

    public func showInteractive(_ scene: String) async { await show(scene) }

    public func show(_ scene: String) async {
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.coreLink = .live
        model.detach()
        model.inboxState.list = .waiting
        var s = SampleBrainService.Scenario()
        switch scene {
        case "overview-healthy": s.healthy = true
        case "overview-paused", "paused": s.paused = true
        case "empty": s.empty = true
        case "error": s.error = true
        case "offline": s.offline = true
        case "rebuilding": s.rebuilding = true
        case "embedding-down": s.embeddingDown = true
        case "activity-empty": s.noActivity = true
        case "activity-error": s.activityError = true
        case "checks-paused": s.paused = true
        case "checks-offline": s.offline = true
        case "inbox-empty": s.emptyInbox = true
        case "inbox-error": s.inboxError = true
        case "inbox-offline": s.offline = true
        default: break
        }
        if scene != "unavailable" {
            model.use(SampleBrainService(s, pace: scene == "checks-running" ? .milliseconds(1200) : .milliseconds(250)))
            await model.reload()
        }
        switch scene {
        case "rooms": model.show(.rooms)
        case "room":
            model.show(.rooms)
            await model.inspect("workan-space")
        case "new-room":
            model.show(.rooms)
            BrainSheets.openNewRoom(model)
        case "sealed":
            model.show(.overview)
            model.view("althaqeel")
        case "inbox": model.show(.inbox)
        case "activity", "activity-empty", "activity-error": model.show(.activity)
        case "activity-blocked":
            model.show(.activity)
            let a = model.activity!
            a.enter()
            await a.load()
            a.filter.kind = .blocked
            a.filter.room = .all
            a.selectedID = "evt-2037"
        case "egress", "egress-local":
            model.show(.activity)
            let a = model.activity!
            a.enter()
            await a.load()
            a.view = .egress
            if scene == "egress-local" { a.egressRoom = "personal" }
            await a.loadEgress()
            if scene == "egress" { a.selectedID = "eg-0408" }
        case "checks", "checks-paused", "checks-offline": model.show(.checks)
        case "checks-running":
            model.show(.checks)
            let c = model.checks!
            await c.load()
            c.selectedID = "speed"
            Task { await c.run("speed") }
        case "inbox-conflict": await inbox(.conflicts, room: "workan-space")
        case "inbox-blocked": await inbox(.blocked, room: "automotive-ai")
        case "inbox-noroom": await inbox(.noRoom)
        case "inbox-assign":
            await inbox(.noRoom)
            BrainSheets.assign(model, ["u1"])
        case "inbox-empty", "inbox-error", "inbox-offline": await inbox(.waiting)
        case "inbox-sealed": await inbox(.waiting, room: "althaqeel")
        default: model.show(.overview)
        }
    }
}
#endif
