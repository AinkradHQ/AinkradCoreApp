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
        "inbox-offline", "loading", "inbox-noroom-selected", "worst-overview", "worst-rooms", "worst-inbox",
        // The Brain M3 states of brain-m3.html, in the mockup's order.
        "m3-inbox", "m3-edit", "m3-queued", "m3-rules", "m3-local", "m3-room-queued", "m3-sources", "m3-runner-on",
    ]

    private func inbox(_ list: InboxList, room: String? = nil) async {
        model.show(.inbox)
        if let room { model.view(room) }
        model.inboxState.list = list
        await model.loadInbox()
    }

    private func showM3(_ scene: String) async {
        let c = model.candidates!
        c.paneMode = .items
        switch scene {
        case "m3-inbox", "m3-edit", "m3-queued":
            model.show(.inbox)
            await c.load()
            for r in model.rooms { await c.loadPolicy(r.id) }
            if scene == "m3-edit", let first = c.items.first { c.startEdit(first.id) }
        case "m3-rules", "m3-local", "m3-room-queued":
            let id = scene == "m3-rules" ? "core" : scene == "m3-local" ? "workan-space" : "personal"
            model.show(.rooms)
            model.view(id)
            await model.inspect(id)
            for r in model.rooms { await c.loadPolicy(r.id) }
            c.paneMode = .settings
        default:
            model.show(.sources)
            await model.sync?.reload()
            await c.loadRunners()
            if scene == "m3-runner-on" {
                await c.toggleRunner("vps-1")
                BrainSheets.runnerHistory(model)
            }
        }
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
        case "worst-overview", "worst-rooms", "worst-inbox": s.worst = true
        default: break
        }
        if scene.hasPrefix("m3-") {
            s.m3 = true
            s.noLocalModel = scene == "m3-queued" || scene == "m3-room-queued"
            s.autoAccept = scene == "m3-local"
        }
        if scene != "unavailable", scene != "loading" {
            model.use(SampleBrainService(s, pace: scene == "checks-running" ? .milliseconds(1200) : .milliseconds(250)))
            await model.reload()
        }
        if scene.hasPrefix("m3-") {
            await showM3(scene)
            return
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
        case "inbox-noroom-selected":
            await inbox(.noRoom)
            model.inboxState.selected = ["u1", "u2"]
        case "loading":
            model.load = .loading
            model.show(.overview)
        case "worst-overview": model.show(.overview)
        case "worst-rooms": model.show(.rooms)
        case "worst-inbox": await inbox(.noRoom)
        default: model.show(.overview)
        }
    }
}
#endif
