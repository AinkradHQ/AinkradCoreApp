#if DEBUG
import Foundation
import Shell
import SwiftUI

/// Debug only: every Leyline state on the mockup's made-up fleet and a stand-in Core, for screenshots and for clicking
/// through. Nothing here reaches a Core. The demo also fills what a live Core does not send yet (`HostExtras`, the wizard's
/// password and sign-in test), so the shots show the whole approved design.
@MainActor
public final class LeylineDemo {
    public static let scenes = [
        "map", "map-filtered", "peek-offline", "map-many", "map-many-acme", "list", "list-many",
        "host-terminal", "host-files", "host-history", "host-access", "host-commands", "wiz-server", "wiz-signin",
        "wiz-signin-file", "wiz-signin-text", "wiz-name", "wiz-check", "wiz-done", "hosts-empty", "hosts-loading",
        "hosts-offline", "hosts-absent", "hosts-failed", "keys", "keys-empty", "key-generate", "key-import",
        "add-advanced", "host-access-allowed", "runner-waiting", "runner-paired",
    ]

    private let model: LeylineModel
    public init(model: LeylineModel) { self.model = model }

    /// For clicking through by hand.
    public func showInteractive(_ scene: String) async { await show(scene) }

    public func show(_ scene: String) async {
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.linkNotice = nil
        shell.coreLink = .live
        shell.home.coreName = "core-oracle"
        model.host.clearElevationNotice()
        model.filter = ""
        model.openID = nil
        model.selected = nil
        model.openGroup = nil
        model.layout = scene.hasPrefix("list") ? .list : .map
        model.page = .hosts
        model.section = .terminal
        model.debugRunner = nil
        model.deviceLookup = nil
        model.previewGaps = true
        model.wizard = nil
        model.clearWriteError()
        let many = scene.contains("many")
        var seeds = Self.fleet(many: many)
        var keys = Self.keys()
        switch scene {
        case "hosts-empty": seeds = []
        case "keys-empty":
            keys = []
            for i in seeds.indices { seeds[i].item.keyID = nil }
        case "runner-paired":
            seeds[7].item.runnerDevice = "d_0000000000000001"
            model.deviceLookup = { _ in
                RunnerClaimer(
                    id: "d_0000000000000001", name: "build-box runner", platform: "linux x86_64",
                    fingerprint: "SHA256:zNJHblwAqgEFH8fTLgmCjvptDXBTFs9gBrASwrmtyiM")
            }
        default: break
        }
        var health: [String: HostHealth] = [:]
        var history: [String: [HostEvent]] = [:]
        for (i, s) in seeds.enumerated() {
            health[s.item.id] = Self.health(s, i)
            history[s.item.id] = Self.history(s)
        }
        model.extras = Dictionary(uniqueKeysWithValues: seeds.map { ($0.item.id, Self.extras($0)) })
        model.activity = [:]
        await model.useNow(
            Service(
                hosts: seeds.map(\.item), keys: keys, known: scene == "keys-empty" ? [] : Self.known(), health: health,
                history: history))
        await model.refreshHealth(force: true)
        model.show()
        let named = { (n: String) in seeds.first { $0.item.name == n }?.item.id }
        model.select(many ? named("lan-api-1") : named("lan-web-1"))
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "map-filtered":
            model.filter = "lan"
            model.filterChanged()
        case "peek-offline": model.select(named("backup-box"))
        case "map-many-acme": model.showGroup("Acme Retail")
        case "hosts-loading": model.setLoad(.loading)
        case "hosts-offline": model.setLoad(.notConnected)
        case "hosts-absent": model.setLoad(.absent)
        case "hosts-failed": model.setLoad(.failed("The Core did not answer in time (timeout)."))
        case "keys", "keys-empty": model.page = .keys
        case "key-generate":
            model.page = .keys
            KeyDialogs.openGenerate(model)
        case "key-import":
            model.page = .keys
            KeyDialogs.openImport(model)
        case "add-advanced": HostDialogs.openAdd(model, login: "ops@198.51.100.40")
        case "host-terminal": model.openHost(named("lan-web-1")!, .terminal)
        case "host-files": model.openHost(named("lan-web-1")!, .files)
        case "host-history": model.openHost(named("lan-web-1")!, .history)
        case "host-access": model.openHost(named("lan-web-1")!, .access)
        case "host-commands": model.openHost(named("lan-web-1")!, .commands)
        case "host-access-allowed": model.openHost(named("lan-staging")!, .access)
        case "runner-waiting":
            model.debugRunner = .waiting(until: Date().addingTimeInterval(840))
            model.openHost(named("build-box")!, .access)
        case "runner-paired": model.openHost(named("build-box")!, .access)
        default: break
        }
        if scene.hasPrefix("wiz-") { wizard(scene) }
    }

    /// The wizard at each step, filled as the mockup is.
    private func wizard(_ scene: String) {
        AddHostWizard.open(model)
        var f = AddHostFlow()
        f.user = "deploy"
        f.setHost("192.0.2.40")
        f.key = .saved(Self.kid(1))
        f.project = "Lanterna"
        switch scene {
        case "wiz-signin": f.step = .signIn
        case "wiz-signin-file":
            f.step = .signIn
            f.key = .importing
        case "wiz-signin-text":
            f.step = .signIn
            f.key = .importing
            f.importFrom = .text
            f.keyText = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ…\n"
        case "wiz-name": f.step = .name
        case "wiz-check":
            f.step = .check
            f.reach = .done("31 ms")
            f.signIn = .done("Signed in")
            f.hostKey = .asks(Self.newHostKey)
        case "wiz-done":
            f.step = .check
            f.reach = .done("31 ms")
            f.signIn = .done("Signed in")
            f.made = model.hosts.first
            f.name = "server-40"
            f.made?.name = "server-40"
            f.trusted = Self.newHostKey
            f.hostKey = .done(nil)
        default: break
        }
        model.wizard = f
    }
}

extension LeylineModel {
    /// Debug only: attaches a stand-in service and reads it before returning (no background reload to race a scene).
    func useNow(_ s: any LeylineService) async {
        service = s
        load = .loading
        await reload()
    }
    func setLoad(_ l: LeylineLoad) { load = l }
}
#endif
