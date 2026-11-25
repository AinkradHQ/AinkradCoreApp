#if DEBUG
import Foundation

/// Debug only: the made-up fleet of the approved mockup (8 hosts, or 46 for the big map) and a stand-in Core that answers
/// for it. Documentation addresses (RFC 5737); fingerprints are hashes of names, not of any real key.
extension LeylineDemo {
    final class Service: LeylineService, @unchecked Sendable {
        private let lock = NSLock()
        private var hostList: [HostItem]
        private var keyList: [KeyItem]
        private let known: [KnownHostItem]
        private let healthOf: [String: HostHealth]
        private let historyOf: [String: [HostEvent]]
        private var next = 100
        init(
            hosts: [HostItem], keys: [KeyItem], known: [KnownHostItem], health: [String: HostHealth] = [:],
            history: [String: [HostEvent]] = [:]
        ) {
            hostList = hosts
            keyList = keys
            self.known = known
            healthOf = health
            historyOf = history
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
                    group: d.group, tags: d.tags, aiRule: d.aiRule, os: nil, createdAt: Date(),
                    reach: HostReach(up: true, latencyMS: 31, checkedAt: Date(), seenAt: Date()))
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
        func health(host: String) async throws -> HostHealth {
            guard let h = healthOf[host] else { throw LeylineFailure.notYet }
            return h
        }
        func files(host: String, path: String) async throws -> [RemoteFile] {
            func f(_ n: String, _ k: RemoteFile.Kind, _ size: Int64?) -> RemoteFile {
                RemoteFile(
                    path: RemotePath.join(path, n), name: n, kind: k, size: size,
                    modified: Date().addingTimeInterval(-86400 * 3), target: nil)
            }
            return [
                f("app", .dir, nil), f("logs", .dir, nil), f("releases", .dir, nil), f("current", .link, nil),
                f("docker-compose.yml", .file, 2_048), f(".env", .file, 612),
            ]
        }
        func history(host: String) async throws -> [HostEvent] { historyOf[host] ?? [] }
        func makeRunner(host: String, rows: Int, cols: Int) async throws -> RunnerInstall {
            RunnerInstall(terminal: "t_demo", expiresAt: Date().addingTimeInterval(840))
        }
        func checkHost(address: String, port: Int) async throws -> HostCheck {
            try await Task.sleep(for: .milliseconds(900))
            return HostCheck(ok: true, ms: 31, reason: nil)
        }
        func hostKeys(host: String) async throws -> [HostKeyItem] {
            [HostKeyItem(fingerprint: LeylineDemo.newHostKey, state: "seen")]
        }
        func trustHostKey(host: String, fingerprint: String) async throws {}
    }

    nonisolated static let newHostKey = "SHA256:Eph4qztpKgRLXQCd1/vZLwairT4nw5FOANWe6f7Xk2i"

    static func id(_ n: Int) -> String { "h_\(String(format: "%016x", n))" }
    static func kid(_ n: Int) -> String { "k_\(String(format: "%016x", n))" }

    static func keys() -> [KeyItem] {
        let now = Date()
        func k(_ n: Int, _ name: String, _ algo: String, _ fp: String, bits: Int? = nil, days: Double) -> KeyItem {
            KeyItem(
                id: kid(n), name: name, algo: algo, publicKey: "ssh-\(algo) AAAA", fingerprint: fp, imported: n != 1,
                createdAt: now.addingTimeInterval(-days * 86400), bits: bits)
        }
        return [
            k(1, "lanterna-deploy", "ed25519", "SHA256:arnx6499M4j0+dWG9m6Z/VQIDfLERvDlhmiwnAihbdA", days: 14),
            k(2, "ops-admin", "ed25519", "SHA256:AV9+a8Wur0g3JAieklLME7UJUaa2lBJSJ2XP9NeAMG4", days: 36),
            k(3, "legacy-rsa", "rsa", "SHA256:L1BSyf0VsZoYxYTQE2NWgZhhPww06EQJ73k4cJoVnsI", bits: 4096, days: 48),
        ]
    }

    /// One host of the fleet, with its numbers.
    struct Seed {
        var item: HostItem
        var cpu: Double
        var mem: Double
        var disk: Double
        var ms: Int?
    }

    /// The mockup's eight hosts (`many`: its 46).
    static func fleet(many: Bool) -> [Seed] {
        let now = Date()
        func h(
            _ n: Int, _ name: String, _ address: String, user: String = "deploy", key: Int?, group: String?,
            hops: [Int] = [], tags: [String] = [], rule: AIRule = .ask, ms: Int?, _ cpu: Double, _ mem: Double,
            _ disk: Double
        ) -> Seed {
            Seed(
                item: HostItem(
                    id: id(n), name: name, address: address, port: 22, username: user, keyID: key.map(kid),
                    jumpChain: hops.map(id), viaRunner: nil, group: group, tags: tags, aiRule: rule, os: "linux",
                    createdAt: now.addingTimeInterval(-Double(n) * 86400),
                    reach: HostReach(
                        up: ms != nil, latencyMS: ms, checkedAt: now.addingTimeInterval(-40),
                        seenAt: ms == nil
                            ? Calendar.current.date(bySettingHour: 9, minute: 12, second: 0, of: now) : now)),
                cpu: cpu, mem: mem, disk: disk, ms: ms)
        }
        if !many {
            return [
                h(
                    1, "lan-web-1", "192.0.2.11", key: 1, group: "Lanterna", hops: [6], tags: ["php"], ms: 31, 58, 62,
                    61),
                h(
                    2, "lan-web-2", "192.0.2.12", key: 1, group: "Lanterna", hops: [6], tags: ["php"], ms: 29, 22, 48,
                    58),
                h(
                    3, "lan-staging", "192.0.2.13", key: 1, group: "Lanterna", tags: ["staging"], rule: .allowed,
                    ms: 182, 91, 77, 83),
                h(
                    4, "ledger-db", "198.51.100.21", key: 3, group: "Northwind", tags: ["postgres"], rule: .readOnly,
                    ms: 24, 18, 66, 71),
                h(5, "ledger-app", "198.51.100.22", key: 3, group: "Northwind", tags: ["staging"], ms: 22, 35, 51, 40),
                h(
                    6, "bastion", "203.0.113.5", user: "ops", key: 2, group: nil, tags: ["jump"], rule: .readOnly,
                    ms: 14, 12, 31, 44),
                h(7, "backup-box", "203.0.113.9", user: "ops", key: 2, group: nil, tags: ["backups"], ms: nil, 0, 0, 0),
                h(8, "build-box", "203.0.113.14", user: "ops", key: 2, group: nil, tags: ["runner"], ms: 17, 7, 20, 35),
            ]
        }
        var out = [h(6, "bastion", "203.0.113.5", user: "ops", key: 2, group: nil, tags: ["jump"], ms: 14, 12, 31, 44)]
        let groups: [(String?, String, Int)] = [
            ("Lanterna", "lan", 12), ("Northwind", "nw", 9), ("Acme Retail", "acme", 14), ("Orbit", "orb", 6),
            (nil, "ops", 5),
        ]
        let roles = ["web", "api", "db", "worker", "cache", "cron"]
        var k = 0
        var n = 100
        for (g, p, count) in groups {
            for i in 1...count {
                k += 1
                if g == nil, i == 1 { continue }
                n += 1
                let off = k % 17 == 0
                let slow = !off && k % 11 == 0
                let ms = off ? nil : slow ? 160 + k % 40 : 12 + (k * 7) % 130
                out.append(
                    h(
                        n, "\(p)-\(roles[i % 6])-\(i)", "10.\(k % 7).\(i).\(10 + k)", key: g == "Lanterna" ? 1 : 2,
                        group: g, hops: g == "Lanterna" && i <= 6 ? [6] : [], ms: ms, Double(k * 13 % 90),
                        Double(k * 29 % 85), Double(k * 31 % 92)))
            }
        }
        return out
    }

    /// A made-up trend ending at `v` (percent), like the mockup's lines.
    static func trend(_ v: Double, _ seed: Int) -> [Double] {
        var x = v
        var pts: [Double] = []
        for i in 0..<16 {
            x = min(98, max(3, x + Double((i * 31 + seed) % 13 - 6)))
            pts.append(x)
        }
        return pts + [v]
    }

    static func health(_ s: Seed, _ seed: Int) -> HostHealth? {
        guard s.ms != nil else { return nil }
        return HostHealth(
            state: .up, checkedAt: Date().addingTimeInterval(-40), load1: s.cpu / 100 * 4, cpus: 4, memPct: s.mem,
            diskPct: s.disk, failedUnits: 0, cpuSeries: trend(s.cpu, 3 + seed), memSeries: trend(s.mem, 7 + seed),
            diskSeries: trend(s.disk, 11 + seed))
    }

    static func extras(_ s: Seed) -> HostExtras {
        var pts: [Double] = []
        if let ms = s.ms {
            var v = Double(ms)
            for i in 0..<18 {
                v = max(8, v + Double((i * 37 + ms) % 23 - 11))
                pts.append(v)
            }
        }
        return HostExtras(
            latencyHistory: pts, osName: "Ubuntu 24.04", uptime: "23 days", memoryTotal: "8 GB",
            diskFree: "\(Int((100 - s.disk) * 0.8)) GB free",
            approval: s.item.name == "lan-web-1" || s.item.name == "lan-cron-11" ? "systemctl reload nginx" : nil)
    }

    static func history(_ s: Seed) -> [HostEvent] {
        let now = Date()
        func e(_ i: Int, _ who: HostEvent.Who, _ what: String, _ ago: Double) -> HostEvent {
            HostEvent(
                id: "\(s.item.id)-\(i)", who: who, what: what, detail: "", at: now.addingTimeInterval(-ago),
                recording: nil, minutes: nil)
        }
        let first: HostEvent =
            switch s.item.name {
            case "lan-web-1": e(0, .ai, "AI session “fix cache headers”", 240)
            case "lan-staging": e(0, .system, "Disk 83% full", 3600)
            case "backup-box": e(0, .system, "Offline since 09:12", 3 * 3600)
            default: e(0, .you, "You · ssh", 2 * 3600)
            }
        return [first, e(1, .fleet, "Deploy v2.4.1", 86400), e(2, .you, "You opened logs", 2 * 86400)]
    }

    static func known() -> [KnownHostItem] {
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
}
#endif
