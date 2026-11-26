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
        "host-overview", "host-commands-running", "host-command-output", "host-access-panel", "host-terminal",
        "host-files", "host-runner-cannot-ssh", "host-offline", "host-key-waiting", "host-key-waiting-access",
        "host-key-trusted", "host-runner-match", "host-new-command", "wiz-server", "wiz-signin",
        "wiz-signin-file", "wiz-signin-text", "wiz-name", "wiz-check", "wiz-failed", "wiz-done", "hosts-empty",
        "hosts-loading",
        "hosts-offline", "hosts-absent", "hosts-failed", "keys", "keys-empty", "keys-generate", "keys-import",
        "keys-import-file", "keys-expanded",
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
        model.closeKeys()
        model.keySelected = nil
        model.keyFresh = nil
        model.section = .overview
        model.accessOpen = false
        model.commandForm = nil
        model.hostProblem = [:]
        model.debugRuns = [:]
        model.debugShown = nil
        model.debugRunner = nil
        model.deviceLookup = nil
        model.runners = nil
        model.openRunner = nil
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
        let service = Service(
            hosts: seeds.map(\.item), keys: keys, known: scene == "keys-empty" ? [] : Self.known(), health: health,
            history: history)
        if scene.hasPrefix("host-key-waiting"), let web = seeds.first(where: { $0.item.name == "lan-web-1" }) {
            service.hostKeysOf[web.item.id] = [HostKeyItem(fingerprint: Self.newHostKey, state: "seen")]
        }
        if scene == "host-runner-match" {
            // Made apart from the host: no runner_device, matched by name.
            model.runners = { [RunnerSummary(id: "d_00000000000000aa", name: "build-box", online: true)] }
            if let b = seeds.first(where: { $0.item.name == "build-box" }) {
                service.hostKeysOf[b.item.id] = [HostKeyItem(fingerprint: Self.newHostKey, state: "trusted")]
            }
            model.openRunner = { _ in }
        }
        await model.useNow(service)
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
        case "keys", "keys-empty": model.keysOpen = true
        case "keys-expanded":
            model.keysOpen = true
            model.keySelected = model.keyList.first { $0.name == "lanterna-deploy" }?.id
        case "keys-generate": model.openKeyForm(.generate)
        case "keys-import": model.openKeyForm(.importing)
        case "keys-import-file":
            // A dropped encrypted key: its type and pattern show, and the passphrase field.
            model.openKeyForm(.importing)
            model.keyDraft.load(
                file: "id_ed25519_ops",
                text: KeyText.sample(cipher: "aes256-ctr", publicFields: [Data((0..<32).map { UInt8($0 * 7) })]),
                taken: model.keyNames)
        case "add-advanced": HostDialogs.openAdd(model, login: "ops@198.51.100.40")
        case "host-overview":
            model.debugRuns = Self.runs(running: false)
            model.openHost(named("lan-web-1")!)
        case "host-commands-running":
            model.debugRuns = Self.runs(running: true)
            model.debugShown = "lc_restart"
            model.openHost(named("lan-web-1")!)
        case "host-command-output":
            model.debugRuns = Self.runs(running: false)
            model.debugShown = "builtin-disk"
            model.openHost(named("lan-web-1")!)
        case "host-new-command":
            model.openHost(named("lan-web-1")!)
            model.commandForm = CommandDraft(name: "Restart the queue", command: "sudo systemctl restart app-queue")
        case "host-access-panel": model.openHost(named("lan-web-1")!, .access)
        case "host-terminal": model.openHost(named("lan-web-1")!, .terminal)
        case "host-files": model.openHost(named("lan-web-1")!, .files)
        case "host-runner-cannot-ssh":
            model.hostProblem[named("lan-web-1")!] = LeylineFailure(
                sentence: "", code: "runner_cannot_ssh", status: 409)
            model.openHost(named("lan-web-1")!, .terminal)
        case "host-offline":
            model.openHost(named("backup-box")!)
        case "host-access-allowed": model.openHost(named("lan-staging")!, .access)
        case "host-key-waiting": model.openHost(named("lan-web-1")!)
        case "host-key-waiting-access", "host-key-trusted": model.openHost(named("lan-web-1")!, .access)
        case "host-runner-match": model.openHost(named("build-box")!, .access)
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
        case "wiz-signin":
            f.step = .signIn
            f.focus = .keys
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
        case "wiz-failed":
            f.step = .check
            f.reach = .failed("Connection refused on port 22. Is ssh running there, or on another port?")
            f.failure = .reach
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
