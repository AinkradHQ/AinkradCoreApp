#if DEBUG
import Foundation
import Shell
import SwiftUI

/// Debug only: every Leyline state on sample data and a stand-in service, for screenshots and for the reviewer to click through.
/// Nothing here reaches a Core. The names are made up; the addresses are documentation addresses (RFC 5737) and the
/// fingerprints are hashes of the host names, not of any real key.
@MainActor
public final class LeylineDemo {
    final class Service: LeylineService, @unchecked Sendable {
        private let lock = NSLock()
        private var hostList: [HostItem]
        private var keyList: [KeyItem]
        private let known: [KnownHostItem]
        private var next = 100
        init(hosts: [HostItem], keys: [KeyItem], known: [KnownHostItem]) {
            hostList = hosts
            keyList = keys
            self.known = known
        }
        func hosts() async throws -> [HostItem] { lock.withLock { hostList } }
        func keys() async throws -> [KeyItem] { lock.withLock { keyList } }
        func knownHosts() async throws -> [KnownHostItem] { known }
        func createHost(_ d: HostDraft) async throws -> HostItem {
            try lock.withLock {
                if hostList.contains(where: { $0.name.lowercased() == d.name.lowercased() }) {
                    throw LeylineFailure(
                        sentence: "That name is already taken. Pick another.", code: "conflict", status: 409)
                }
                next += 1
                let h = HostItem(
                    id: "h_\(String(format: "%016x", next))", name: d.name, address: d.address, port: d.port,
                    username: d.username, keyID: d.keyID, jumpChain: d.jumpChain, viaRunner: d.viaRunner,
                    group: d.group, tags: d.tags, aiRule: d.aiRule, os: nil, createdAt: Date())
                hostList.append(h)
                return h
            }
        }
        func patchHost(_ id: String, _ patch: HostPatch) async throws -> HostItem {
            try lock.withLock {
                guard let i = hostList.firstIndex(where: { $0.id == id }) else {
                    throw LeylineFailure(sentence: "That is gone.", code: "not_found", status: 404)
                }
                if case .string(let r)? = patch.fields["ai_rule"] { hostList[i].aiRule = AIRule(wire: r) }
                if case .strings(let t)? = patch.fields["tags"] { hostList[i].tags = t }
                if case .string(let g)? = patch.fields["group"] { hostList[i].group = g }
                return hostList[i]
            }
        }
        func generateKey(name: String) async throws -> KeyItem {
            lock.withLock {
                next += 1
                let k = KeyItem(
                    id: "k_\(String(format: "%016x", next))", name: name, algo: "ed25519",
                    publicKey: "ssh-ed25519 AAAA…",
                    fingerprint: "SHA256:arnx6499M4j0+dWG9m6Z/VQIDfLERvDlhmiwnAihbdA", imported: false,
                    createdAt: Date())
                keyList.append(k)
                return k
            }
        }
        func importKey(name: String, privateKey: String, passphrase: String?) async throws -> KeyItem {
            try await generateKey(name: name)
        }
    }

    public static let scenes = [
        "hosts", "hosts-hover", "hosts-selected", "hosts-filtered", "hosts-empty", "hosts-loading", "hosts-offline",
        "hosts-absent", "hosts-failed", "add-quick-empty", "add-quick", "add-quick-error", "add-advanced", "keys",
        "keys-empty", "key-generate", "key-import", "host-overview", "host-terminal", "host-access",
        "host-access-allowed", "host-access-bare",
    ]

    private let model: LeylineModel
    public init(model: LeylineModel) { self.model = model }

    private static func id(_ n: Int) -> String { "h_\(String(format: "%016x", n))" }
    private static func kid(_ n: Int) -> String { "k_\(String(format: "%016x", n))" }

    private static func keys() -> [KeyItem] {
        let now = Date()
        func k(_ n: Int, _ name: String, _ algo: String, _ fp: String, imported: Bool, days: Double) -> KeyItem {
            KeyItem(
                id: kid(n), name: name, algo: algo, publicKey: "ssh-\(algo) AAAA", fingerprint: fp, imported: imported,
                createdAt: now.addingTimeInterval(-days * 86400))
        }
        return [
            k(
                1, "lanterna-deploy", "ed25519", "SHA256:arnx6499M4j0+dWG9m6Z/VQIDfLERvDlhmiwnAihbdA", imported: false,
                days: 14),
            k(
                2, "ops-personal", "ed25519", "SHA256:AV9+a8Wur0g3JAieklLME7UJUaa2lBJSJ2XP9NeAMG4", imported: true,
                days: 36),
            k(
                3, "northwind-db", "ecdsa-p256", "SHA256:L1BSyf0VsZoYxYTQE2NWgZhhPww06EQJ73k4cJoVnsI", imported: true,
                days: 48),
        ]
    }

    private static func hosts() -> [HostItem] {
        let now = Date()
        func h(
            _ n: Int, _ name: String, _ address: String, user: String = "deploy", key: Int?, group: String?,
            hops: [Int] = [], tags: [String] = [], rule: AIRule = .ask
        ) -> HostItem {
            HostItem(
                id: id(n), name: name, address: address, port: 22, username: user, keyID: key.map(kid),
                jumpChain: hops.map(id), viaRunner: nil, group: group, tags: tags, aiRule: rule, os: nil,
                createdAt: now.addingTimeInterval(-Double(n) * 86400))
        }
        return [
            h(1, "lan-web-1", "192.0.2.11", key: 1, group: "Lanterna", hops: [6], tags: ["php", "eu-west"]),
            h(2, "lan-web-2", "192.0.2.12", key: 1, group: "Lanterna", hops: [6], tags: ["php", "eu-west"]),
            h(3, "lan-staging", "192.0.2.13", key: 1, group: "Lanterna", tags: ["staging"], rule: .allowed),
            h(4, "ledger-db", "198.51.100.21", key: 3, group: "Northwind", tags: ["postgres"], rule: .readOnly),
            h(5, "ledger-app", "198.51.100.22", key: 3, group: "Northwind", tags: ["staging"]),
            h(6, "bastion", "203.0.113.5", user: "ops", key: 2, group: nil, tags: ["jump"], rule: .readOnly),
            h(7, "backup-box", "203.0.113.9", user: "ops", key: 2, group: nil, tags: ["backups"]),
            h(8, "build-box", "203.0.113.14", user: "ops", key: 2, group: nil, tags: ["runner"]),
        ]
    }

    private static func known() -> [KnownHostItem] {
        let now = Date()
        func k(_ host: String, _ fp: String, _ state: KnownHostItem.State = .trusted, days: Double) -> KnownHostItem {
            KnownHostItem(host: host, fingerprint: fp, state: state, since: now.addingTimeInterval(-days * 86400))
        }
        return [
            k("lan-web-1", "SHA256:Eph8ztpKgRLXQCd1/vZLwairT4nw5FOANWe6fl/2iWI", days: 14),
            k("lan-web-2", "SHA256:zsTx/xGKNQBLkdpZaws9WihHeSFySIpdymqua3f95JM", days: 14),
            k("lan-staging", "SHA256:zNJHblwAqgEFH8fTLgmCjvptDXBTFs9gBrASwrmtyiM", days: 12),
            k("ledger-db", "SHA256:cbkWKfrvkKSTTpSkt//bZobfMMhsUCJSkkyZN2FuR2I", days: 30),
            k("ledger-app", "SHA256:ei9uYwmqGpTNXK32L5JDW2ocrWCFdQggjz3LnvmW4bo", .changed, days: 30),
            k("bastion", "SHA256:ocUJ3yHOxJr2aFq449utYN/LA3zAqzsLUsYS8q5uzKQ", days: 40),
        ]
    }

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
        model.quickOpen = false
        model.quickText = ""
        model.filter = ""
        model.cursor = nil
        model.openID = nil
        model.selection = []
        model.page = .hosts
        model.section = .overview
        model.debugHover = nil
        model.clearWriteError()
        var hosts = Self.hosts()
        var keys = Self.keys()
        switch scene {
        case "hosts-empty": hosts = []
        case "keys-empty":
            keys = []
            for i in hosts.indices { hosts[i].keyID = nil }
        case "host-access-bare":
            hosts[4].keyID = nil
            hosts[4].group = nil
            hosts[4].tags = []
            hosts[4].jumpChain = []
        default: break
        }
        await model.useNow(Service(hosts: hosts, keys: keys, known: scene == "keys-empty" ? [] : Self.known()))
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "hosts-hover": model.debugHover = Self.id(2)
        case "hosts-selected": model.selection = [Self.id(1), Self.id(2), Self.id(5)]
        case "hosts-filtered": model.filter = "lan"
        case "hosts-loading": model.setLoad(.loading)
        case "hosts-offline": model.setLoad(.notConnected)
        case "hosts-absent": model.setLoad(.absent)
        case "hosts-failed": model.setLoad(.failed("The Core did not answer in time (timeout)."))
        case "add-quick-empty": model.quickOpen = true
        case "add-quick":
            model.quickText = "deploy@192.0.2.40"
            model.quickOpen = true
        case "add-quick-error":
            model.quickText = "deploy@"
            model.quickOpen = true
        case "add-advanced": HostDialogs.openAdd(model, login: "ops@198.51.100.40")
        case "keys", "keys-empty": model.page = .keys
        case "key-generate":
            model.page = .keys
            KeyDialogs.openGenerate(model)
        case "key-import":
            model.page = .keys
            KeyDialogs.openImport(model)
        case "host-overview": model.openID = Self.id(1)
        case "host-terminal":
            model.openID = Self.id(1)
            model.section = .terminal
        case "host-access":
            model.openID = Self.id(1)
            model.section = .access
        case "host-access-allowed":
            model.openID = Self.id(3)
            model.section = .access
        case "host-access-bare":
            model.openID = Self.id(5)
            model.section = .access
        default: break
        }
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
