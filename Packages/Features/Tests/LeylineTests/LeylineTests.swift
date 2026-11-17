import Admin
import CoreKit
import Foundation
import Shell
import Testing

@testable import Leyline

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    private(set) var reasons: [String] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw AdminDeclined() }
        return try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

/// An in-memory Core: records what the model asked.
final class FakeService: LeylineService, @unchecked Sendable {
    private let lock = NSLock()
    private var hostList: [HostItem] = []
    private var keyList: [KeyItem] = []
    private(set) var calls: [String] = []
    private(set) var patches: [HostPatch] = []
    func hosts() async throws -> [HostItem] { lock.withLock { hostList } }
    func keys() async throws -> [KeyItem] { lock.withLock { keyList } }
    func knownHosts() async throws -> [KnownHostItem] { [] }
    func createHost(_ d: HostDraft) async throws -> HostItem {
        lock.withLock {
            calls.append("create \(d.name) \(d.username)@\(d.address):\(d.port) \(d.aiRule.wire)")
            let h = HostItem(
                id: "h_\(hostList.count + 1)", name: d.name, address: d.address, port: d.port, username: d.username,
                keyID: d.keyID, jumpChain: d.jumpChain, viaRunner: nil, group: d.group, tags: d.tags,
                aiRule: d.aiRule, os: nil, createdAt: nil)
            hostList.append(h)
            return h
        }
    }
    func patchHost(_ id: String, _ patch: HostPatch) async throws -> HostItem {
        lock.withLock {
            calls.append("patch \(id)")
            patches.append(patch)
            let i = hostList.firstIndex { $0.id == id }!
            if case .string(let r)? = patch.fields["ai_rule"] { hostList[i].aiRule = AIRule(wire: r) }
            return hostList[i]
        }
    }
    func generateKey(name: String) async throws -> KeyItem {
        lock.withLock {
            calls.append("generate \(name)")
            let k = KeyItem(
                id: "k_\(keyList.count + 1)", name: name, algo: "ed25519", publicKey: "ssh-ed25519 AAAA",
                fingerprint: "SHA256:x", imported: false, createdAt: nil)
            keyList.append(k)
            return k
        }
    }
    func importKey(name: String, privateKey: String, passphrase: String?) async throws -> KeyItem {
        lock.withLock { calls.append("import \(name) passphrase=\(passphrase != nil)") }
        return try await generateKey(name: name)
    }
}

@MainActor
private func model(declines: Bool = false) -> (LeylineModel, FakeHost, FakeService) {
    let host = FakeHost()
    host.declines = declines
    let m = LeylineModel(host: host)
    let s = FakeService()
    m.service = s
    return (m, host, s)
}

@Suite("Leyline")
struct LeylineTests {
    @Test func theFingerprintPatternIsTheSameForTheSameKeyAndNotForAnother() {
        let a = "SHA256:Eph8ztpKgRLXQCd1/vZLwairT4nw5FOANWe6fl/2iWI"
        let b = "SHA256:zsTx/xGKNQBLkdpZaws9WihHeSFySIpdymqua3f95JM"
        #expect(FingerprintPattern.tones(a).count == 32)
        #expect(FingerprintPattern.tones(a) == FingerprintPattern.tones(a))
        #expect(FingerprintPattern.tones(a) != FingerprintPattern.tones(b))
        #expect(FingerprintPattern.tones(a).allSatisfy { (0...3).contains($0) })
        // Not a SHA256 string: a flat pattern, no crash.
        #expect(FingerprintPattern.tones("nonsense").allSatisfy { $0 == 0 })
        #expect(FingerprintPattern.short(a) == "SHA256:Eph…iWI")
    }

    @Test func theQuickFieldTakesUserAtAddressAndRefusesWhatTheCoreWould() {
        #expect(HostRules.login("deploy@10.0.0.4") == .init(username: "deploy", address: "10.0.0.4", port: 22))
        #expect(
            HostRules.login("ops@db.example.com:2222") == .init(username: "ops", address: "db.example.com", port: 2222))
        #expect(HostRules.login("web-1.example.com")?.username == "root")
        #expect(HostRules.login("ops@fe80::1%en0")?.address == "fe80::1%en0")
        for bad in [
            "", "deploy@", "@host", "a b@host", "-o@host", "host;rm", "ops@host:0", "ops@host:70000", "ops@host:x",
        ] {
            #expect(HostRules.login(bad) == nil, "\(bad)")
        }
        #expect(HostRules.label(fromAddress: "db-1.internal") == "db-1")
        #expect(HostRules.label(fromAddress: "10.0.0.4") == "10.0.0.4")
    }

    @Test func tagsAreLowercasedAndRepeatsDropped() {
        #expect(HostRules.tags("PHP, eu-west php") == ["php", "eu-west"])
        #expect(HostRules.tags("a b!") == nil)
        #expect(HostRules.tags("") == [])
    }

    @Test func theGalleryGroupsByGroupWithTheUngroupedLast() {
        func h(_ n: String, _ g: String?) -> HostItem {
            HostItem(
                id: n, name: n, address: "a", port: 22, username: "u", keyID: nil, jumpChain: [], viaRunner: nil,
                group: g, tags: [], aiRule: .ask, os: nil, createdAt: nil)
        }
        let groups = HostGroup.grouping([h("z", nil), h("b", "Northwind"), h("a", "Lanterna"), h("c", "Lanterna")])
        #expect(groups.map(\.title) == ["Lanterna", "Northwind", "Shared"])
        #expect(groups[0].hosts.map(\.name) == ["a", "c"])
        #expect(groups[2].sub == "not in a group · 1 host")
    }

    @Test func aPatchSendsNullToClearAndOmitsWhatItDoesNotOwn() throws {
        let p = HostPatch.edit(HostDraft(name: "w", address: "a", username: "u"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(json["key_id"] is NSNull)
        #expect(json["group"] is NSNull)
        #expect(json["ai_rule"] == nil)
        let rule = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(HostPatch.rule(.readOnly))) as? [String: Any])
        #expect(rule.keys.sorted() == ["ai_rule"])
        #expect(rule["ai_rule"] as? String == "read_only")
    }

    @MainActor @Test func anAddedHostIsAskFirstAndNeedsNoTouchID() async throws {
        let (m, host, s) = model()
        let l = try #require(HostRules.login("deploy@192.0.2.40"))
        let ok = await m.addHost(
            HostDraft(name: HostRules.label(fromAddress: l.address), address: l.address, username: l.username))
        #expect(ok)
        #expect(s.calls == ["create 192.0.2.40 deploy@192.0.2.40:22 ask"])
        #expect(host.reasons.isEmpty)
        #expect(await until { m.hosts.count == 1 })
    }

    @MainActor @Test func aBadAddressIsRefusedBeforeAnythingIsSent() async {
        let (m, _, s) = model()
        let ok = await m.addHost(HostDraft(name: "x", address: "a b", username: "u"))
        #expect(!ok)
        #expect(s.calls.isEmpty)
        #expect(m.writeError != nil)
    }

    @MainActor @Test func allowedAsksForTouchIDAndTheSaferRulesDoNot() async {
        let (m, host, s) = model()
        _ = try? await s.createHost(HostDraft(name: "w", address: "a", username: "u"))
        await m.reload()
        let h = m.hosts[0]
        await m.setRule(h, .readOnly)
        #expect(host.reasons.isEmpty)
        await m.reload()
        await m.setRule(m.hosts[0], .allowed)
        #expect(host.reasons.count == 1)
        #expect(host.reasons[0].contains("without asking"))
        await m.reload()
        #expect(m.hosts[0].aiRule == .allowed)
    }

    @MainActor @Test func declinedTouchIDChangesNothing() async {
        let (m, host, s) = model(declines: true)
        _ = try? await s.createHost(HostDraft(name: "w", address: "a", username: "u"))
        await m.reload()
        await m.setRule(m.hosts[0], .allowed)
        #expect(host.reasons.count == 1)
        #expect(s.patches.isEmpty)
        #expect(m.hosts[0].aiRule == .ask)
    }

    @MainActor @Test func generatingAndImportingAKeyAskForTouchID() async {
        let (m, host, s) = model()
        #expect(await m.generateKey(name: "deploy"))
        #expect(
            await m.importKey(
                name: "ops", privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\nx\n-----END OPENSSH PRIVATE KEY-----",
                passphrase: ""))
        #expect(host.reasons.count == 2)
        #expect(s.calls == ["generate deploy", "import ops passphrase=false", "generate ops"])
        // Not an OpenSSH key: refused here, nothing sent, no Touch ID.
        #expect(!(await m.importKey(name: "rsa", privateKey: "-----BEGIN RSA PRIVATE KEY-----", passphrase: "")))
        #expect(host.reasons.count == 2)
    }

    @MainActor @Test func aKeyShowsTheHostsThatUseIt() async {
        let (m, _, s) = model()
        _ = try? await s.generateKey(name: "deploy")
        _ = try? await s.createHost(HostDraft(name: "w", address: "a", username: "u", keyID: "k_1"))
        _ = try? await s.createHost(HostDraft(name: "x", address: "b", username: "u"))
        await m.reload()
        #expect(m.usedBy(m.keys[0]).map(\.name) == ["w"])
    }
}
