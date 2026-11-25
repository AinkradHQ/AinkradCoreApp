import CoreGraphics
import Foundation
import Testing

@testable import Leyline

private func host(
    _ id: String, group: String? = nil, hops: [String] = [], up: Bool? = true, ms: Int? = 20, tags: [String] = []
) -> HostItem {
    HostItem(
        id: id, name: id, address: "10.0.0.1", port: 22, username: "deploy", keyID: nil, jumpChain: hops,
        viaRunner: nil, group: group, tags: tags, aiRule: .ask, os: nil, createdAt: nil,
        reach: up.map { HostReach(up: $0, latencyMS: ms, checkedAt: nil, seenAt: nil) })
}

@Suite("Leyline page")
struct LeylineFleetTests {
    @Test func aPastedSSHLineFillsUserHostAndPort() {
        #expect(
            SSHLine.parse("ssh deploy@192.0.2.40 -p 2222") == SSHLine(user: "deploy", host: "192.0.2.40", port: 2222))
        #expect(
            SSHLine.parse("ssh -p 2222 ops@db.example.com") == SSHLine(user: "ops", host: "db.example.com", port: 2222))
        #expect(SSHLine.parse("ssh -p2200 web-1") == SSHLine(user: nil, host: "web-1", port: 2200))
        #expect(SSHLine.parse("ops@host:2222") == SSHLine(user: "ops", host: "host", port: 2222))
        #expect(SSHLine.parse("  10.0.0.4 ") == SSHLine(user: nil, host: "10.0.0.4", port: nil))
        #expect(SSHLine.parse("ops@fe80::1%en0")?.host == "fe80::1%en0")
        for bad in ["", "ssh", "ssh -i key host", "ssh host -p x", "ssh host -p 70000", "a b", "-o@host", "host;rm"] {
            #expect(SSHLine.parse(bad) == nil, "\(bad)")
        }
        #expect(SSHLine.fills("ssh web-1"))
        #expect(SSHLine.fills("ops@web-1"))
        #expect(!SSHLine.fills("web-1"))
    }

    @Test func theHostFieldFillsTheOthersAndTheName() {
        var f = AddHostFlow()
        f.setHost("ssh deploy@192.0.2.40 -p 2222")
        #expect(f.user == "deploy" && f.host == "192.0.2.40" && f.port == "2222")
        #expect(f.name == "server-40")
        f.setHost("web-1.example.com")
        #expect(f.user == "deploy" && f.host == "web-1.example.com" && f.port == "2222" && f.name == "web-1")
        f.name = "mine"
        f.nameTouched = true
        f.setHost("10.0.0.9")
        #expect(f.name == "mine")
    }

    @Test func theWizardOnlyGoesOnWhenTheStepIsFilled() {
        var f = AddHostFlow()
        f.next()
        #expect(f.step == .server)
        f.setHost("deploy@192.0.2.40")
        f.next()
        #expect(f.step == .signIn)
        f.key = .importing
        f.next()
        #expect(f.step == .signIn)
        f.keyText = "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----"
        f.next()
        #expect(f.step == .name)
        #expect(f.draft(keyID: "k_1").group == nil)
        f.project = "Lanterna"
        let d = f.draft(keyID: "k_1")
        #expect(d.name == "server-40" && d.keyID == "k_1" && d.group == "Lanterna" && d.jumpChain.isEmpty)
        f.back()
        #expect(f.step == .signIn)
    }

    @Test func aSealedKeyAsksForItsPassphrase() {
        func openssh(_ cipher: String) -> String {
            var b = Array("openssh-key-v1".utf8) + [0]
            let c = Array(cipher.utf8)
            b += [0, 0, 0, UInt8(c.count)] + c + [0, 0, 0, 0]
            return
                "-----BEGIN OPENSSH PRIVATE KEY-----\n\(Data(b).base64EncodedString())\n-----END OPENSSH PRIVATE KEY-----"
        }
        #expect(AddHostFlow.needsPassphrase(openssh("aes256-ctr")))
        #expect(!AddHostFlow.needsPassphrase(openssh("none")))
        #expect(AddHostFlow.needsPassphrase("-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\n"))
        #expect(!AddHostFlow.needsPassphrase("not a key"))
    }

    @Test func aLightComesFromTheLastCheck() {
        #expect(host("a", ms: 31).light == .ok)
        #expect(host("a", ms: 182).light == .slow)
        #expect(host("a", up: false).light == .off)
        #expect(host("a", up: nil).light == .unknown)
        #expect(host("a", up: false).latencyWord == "offline")
        #expect(host("a", up: nil).latencyWord == nil)
    }

    @Test func aGroupSummaryCountsSlowOfflineAndApprovals() {
        let s = GroupSummary(
            [host("a"), host("b", ms: 200), host("c", up: false), host("d", up: nil)], approvals: ["a", "x"])
        #expect(s.hosts == 4 && s.slow == 1 && s.offline == 1 && s.approvals == 1)
        #expect(s.words == ["4 hosts", "1 slow", "1 offline"])
        #expect(GroupSummary([host("a")]).words == ["1 host"])
    }

    @Test func theMapPutsAHostBehindAJumpHostBesideIt() {
        let p = RouteLayout.place([
            host("web-1", hops: ["bastion"]), host("db"), host("bastion"), host("web-2", hops: ["bastion"]),
            host("orphan", hops: ["gone"]),
        ])
        #expect(p["bastion"]?.col == 0 && p["bastion"]?.row == 0)  // jump hosts come first
        #expect(p["db"]?.col == 0 && p["orphan"]?.col == 0)  // a missing jump host: straight from the Core
        #expect(p["web-1"]?.col == 1 && p["web-2"]?.col == 1)
        #expect(abs((p["web-1"]!.row + p["web-2"]!.row) / 2 - p["bastion"]!.row) < 0.5)
        #expect(p["web-2"]!.row - p["web-1"]!.row >= 0.8)
    }

    @Test func arrowsStepAndWrap() {
        #expect(FleetNav.step(["a", "b", "c"], from: "c", by: 1) == "a")
        #expect(FleetNav.step(["a", "b", "c"], from: "a", by: -1) == "c")
        #expect(FleetNav.step(["a", "b", "c"], from: nil, by: 1) == "a")
        #expect(FleetNav.step(["a", "b", "c"], from: "zz", by: -1) == "c")
        #expect(FleetNav.step([], from: nil, by: 1) == nil)
        let pts: [String: CGPoint] = [
            "right": CGPoint(x: 10, y: 0), "far": CGPoint(x: 30, y: 0), "upRight": CGPoint(x: 8, y: -9),
            "down": CGPoint(x: 0, y: 10),
        ]
        #expect(FleetNav.nearest(from: .zero, in: pts, dx: 1, dy: 0) == "right")
        #expect(FleetNav.nearest(from: .zero, in: pts, dx: 0, dy: 1) == "down")
        #expect(FleetNav.nearest(from: .zero, in: pts, dx: 0, dy: -1) == "upRight")
        #expect(FleetNav.nearest(from: .zero, in: pts, dx: -1, dy: 0) == nil)
    }

    @MainActor @Test func findingSelectsTheFirstMatchAndTheListSkipsTheRest() {
        let m = LeylineModel(host: FakeHost())
        m.hosts = [
            host("lan-web", group: "Lanterna"), host("ledger", group: "Northwind", tags: ["postgres"]), host("box"),
        ]
        m.load = .ready
        m.select("box")
        m.type("post")
        #expect(m.shown.map(\.id) == ["ledger"])
        #expect(m.selected == "ledger")
        m.filter = "lanterna"
        m.filterChanged()
        #expect(m.selected == "lan-web")
        m.filter = ""
        m.layout = .list
        #expect(m.listGroups.map(\.title) == ["Lanterna", "Northwind", "Shared"])
        m.move(dx: 0, dy: 1)
        #expect(m.selected == "ledger")
        m.move(dx: 0, dy: 1)
        m.move(dx: 0, dy: 1)
        #expect(m.selected == "lan-web")  // wraps
        #expect(!m.move(dx: 1, dy: 0))  // the list only goes up and down
    }

    @MainActor @Test func onABigMapSidewaysMovesBetweenGroups() {
        let m = LeylineModel(host: FakeHost())
        m.hosts =
            (1...8).map { host("a\($0)", group: "Acme") } + (1...6).map { host("n\($0)", group: "Northwind") }
        m.load = .ready
        #expect(m.bigMap)
        m.select("a1")
        m.move(dx: 1, dy: 0)
        #expect(m.currentGroup == "Northwind" && m.selected == "n1")
        m.move(dx: 0, dy: -1)
        #expect(m.selected == "n6")
        m.move(dx: 1, dy: 0)
        #expect(m.currentGroup == "Acme")
    }

    @MainActor @Test func anOfflineHostOpensOnItsOverviewOnly() {
        let m = LeylineModel(host: FakeHost())
        m.hosts = [host("down", up: false), host("up")]
        m.openHost("down", .terminal)
        #expect(m.openID == "down" && m.section == .overview)
        m.go(.files)
        #expect(m.section == .overview)
        m.openHost("up", .files)
        #expect(m.openID == "up" && m.section == .files && !m.accessOpen)
        m.openHost("up", .access)
        #expect(m.section == .overview && m.accessOpen)
        m.go(.access)
        #expect(!m.accessOpen)
    }
}

@Suite("Add Host wizard")
struct AddHostWizardTests {
    @Test func aWholeSSHLinePastedIntoAnyServerFieldFillsAllThree() {
        for field in [AddHostFlow.Field.user, .host, .port] {
            var f = AddHostFlow()
            f.setServer(field, "ssh ops@db.example.com -p 2200")
            #expect(f.user == "ops" && f.host == "db.example.com" && f.port == "2200", "\(field)")
        }
        var f = AddHostFlow()
        f.setServer(.user, "deploy")
        f.setServer(.port, "22a2")
        #expect(f.user == "deploy" && f.port == "222" && f.host.isEmpty)
    }

    @Test func problemsSpeakOnlyAboutWhatWasTyped() {
        var f = AddHostFlow()
        f.user = ""
        f.port = ""
        #expect(f.problems.isEmpty)
        f.user = "a b"
        f.host = "bad host"
        f.port = "70000"
        #expect(Set(f.problems.keys) == [.user, .host, .port])
        f.name = ""
        f.nameTouched = true
        #expect(f.problems[.name] != nil)
        f.key = .importing
        f.keyText = "ssh-ed25519 AAAA public"
        #expect(f.problems[.keys] != nil)
    }

    @Test func arrowsMoveThroughTheKeysAndStopAtTheEnds() {
        var f = AddHostFlow()
        let ids = ["k1", "k2"]
        f.moveKey(-1, keyIDs: ids)
        #expect(f.key == .none)
        f.moveKey(1, keyIDs: ids)
        #expect(f.key == .saved("k1"))
        f.moveKey(1, keyIDs: ids)
        f.moveKey(1, keyIDs: ids)
        f.moveKey(1, keyIDs: ids)
        #expect(f.key == .importing)
        f.moveKey(-1, keyIDs: ids)
        #expect(f.key == .saved("k2"))
    }

    @Test func theStartingKeyIsTheLastOneElseTheMostUsed() {
        #expect(AddHostFlow.defaultKey(keyIDs: ["a", "b"], usage: ["a": 1, "b": 3], last: "a") == .saved("a"))
        #expect(AddHostFlow.defaultKey(keyIDs: ["a", "b"], usage: ["a": 1, "b": 3], last: "gone") == .saved("b"))
        #expect(AddHostFlow.defaultKey(keyIDs: ["a"], usage: [:], last: nil) == .none)
        #expect(AddHostFlow.defaultKey(keyIDs: [], usage: [:], last: nil) == .none)
    }

    @Test func aFailureSendsYouToTheFieldThatFixesItAndKeepsWhatYouTyped() {
        #expect(AddHostFlow.fix(for: .reach).step == .server && AddHostFlow.fix(for: .reach).field == .host)
        #expect(AddHostFlow.fix(for: .key).step == .signIn)
        #expect(AddHostFlow.fix(for: .save("That name is already taken. Pick another.")).field == .name)
        #expect(AddHostFlow.fix(for: .save("The address is not allowed.")).step == .server)
        var f = AddHostFlow()
        f.setHost("deploy@192.0.2.40:2222")
        f.step = .check
        f.reach = .failed("refused")
        f.failure = .reach
        f.applyFix()
        #expect(f.step == .server && f.focus == .host && f.reach == .waiting && f.failure == nil)
        #expect(f.host == "192.0.2.40" && f.port == "2222" && f.user == "deploy")
        f.next()
        #expect(f.step == .signIn && f.focus == .keys)
        f.back()
        #expect(f.step == .server && f.focus == .user && f.host == "192.0.2.40")
    }
}
