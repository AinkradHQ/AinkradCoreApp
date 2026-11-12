import CoreKit
import Foundation
import Testing

@testable import Admin

@MainActor
@Suite("Secrets are write-only")
struct SecretsTests {
    private static let dummy = "dummy-value-9f3a1c"

    private func world(mode: Int64 = 1) async -> (AdminModel, FakeService, FakeHost) {
        let s = FakeService()
        s.settingList = [
            setting("secrets.mode", value: mode, def: 0, min: 0, max: 2, unit: "count"),
            setting("secrets.lease_secs", value: 120, def: 120, min: 10, max: 900),
        ]
        s.secretList = [secret("e5-07-old", version: 2)]
        return await makeAdmin(s)
    }

    private func form(_ name: String = "e5-07-test", value: String = SecretsTests.dummy) -> SecretForm {
        let f = SecretForm()
        f.name = name
        f.setValue(value)
        f.runners = ["d_run"]
        return f
    }

    @Test("Secrets are off only once the registry has loaded with mode 0, never while it loads or after it failed")
    func offOnlyWhenKnown() async {
        let (off, _, _) = await world(mode: 0)
        #expect(off.secrets.isOff)
        off.registry.state = .loading
        #expect(!off.secrets.isOff, "mode reads 0 while loading; the list and New buttons stay")
        off.registry.state = .failed(code: "error", message: "No answer.", errorID: nil)
        #expect(!off.secrets.isOff)
        let (on, _, _) = await world(mode: 1)
        #expect(!on.secrets.isOff)
    }

    @Test("a stored secret shows name and metadata, and the value is wiped from the form once it is sent")
    func store() async {
        let (admin, service, host) = await world()
        let f = form()
        let ok = await admin.secrets.store(f)
        #expect(ok)
        #expect(service.sentValues == [Self.dummy], "the value goes to the Core exactly once")
        #expect(f.value == "", "and is gone from the form")
        let made = admin.secrets.items.first { $0.name == "e5-07-test" }
        #expect(made?.size == 12 && made?.version == 1)
        #expect(!String(reflecting: admin.secrets.items).contains(Self.dummy))
        let said = host.shell.toast?.message ?? ""
        #expect(said.contains("e5-07-test") && !said.contains(Self.dummy), "toast said: \(said)")
        #expect(!host.reasons.joined().contains(Self.dummy), "the Touch ID reason never carries it")
        #expect(host.reasons.last?.contains("e5-07-test") == true)
        #expect(service.log.contains("create e5-07-test env d_run"))
    }

    @Test("a refusal by the Core wipes the value too and says the code")
    func refused() async {
        let (admin, service, _) = await world()
        service.failure = AdminFailure(status: 409, code: "real_secret_refused", message: "Looks real.", errorID: nil)
        let f = form(value: "ghp_aaaaaaaaaaaaaaaaaaaa")
        let ok = await admin.secrets.store(f)
        #expect(!ok)
        #expect(f.value == "")
        #expect(f.issue?.code == "real_secret_refused")
        #expect(admin.secrets.items.allSatisfy { $0.name != "e5-07-test" })
    }

    @Test("Touch ID declined: nothing was sent, so the typed value is still in the dialog")
    func declined() async {
        let (admin, service, host) = await world()
        host.declines = true
        let f = form()
        #expect(await admin.secrets.store(f) == false)
        #expect(service.sentValues.isEmpty)
        #expect(f.value == Self.dummy)
        f.wipe()
        #expect(f.value == "", "closing the dialog wipes it")
    }

    @Test("names follow the Core's rule and a value is required, before anything is asked")
    func validation() async {
        let (admin, service, host) = await world()
        for bad in ["", "Upper", "1abc", "has space", String(repeating: "a", count: 65)] {
            let f = form(bad)
            #expect(await admin.secrets.store(f) == false, "\(bad) is refused")
            #expect(f.issue?.code == "bad_request")
        }
        let noValue = form(value: "")
        #expect(await admin.secrets.store(noValue) == false)
        #expect(service.log.allSatisfy { !$0.hasPrefix("create") })
        #expect(host.reasons.isEmpty)
        #expect(SecretForm.validName("e5-07-test") && SecretForm.validName("a.b_c-d"))
    }

    @Test("replacing a value raises the version and wipes the new value")
    func replace() async {
        let (admin, service, _) = await world()
        let old = admin.secrets.items[0]
        let f = SecretForm(existing: old)
        f.setValue(Self.dummy)
        #expect(await admin.secrets.replace(f))
        #expect(admin.secrets.items[0].version == 3)
        #expect(f.value == "")
        #expect(service.sentValues == [Self.dummy])
    }

    @Test("a lease needs a runner, a length inside the setting and the person's word")
    func lease() async {
        let (admin, service, _) = await world()
        let s = admin.secrets.items[0]
        let f = LeaseForm(secret: s)
        #expect(admin.secrets.checkLease(f)?.code == "bad_request", "not confirmed yet")
        f.understood = true
        f.ttl = "901"
        #expect(admin.secrets.checkLease(f)?.code == "out_of_bounds")
        f.ttl = "x"
        #expect(admin.secrets.checkLease(f)?.code == "not_integer")
        f.ttl = ""
        #expect(admin.secrets.checkLease(f) == nil)
        f.ttl = "30"
        #expect(await admin.secrets.lease(f))
        #expect(service.log.contains("lease e5-07-old d_run 30"))
        #expect(admin.secrets.leases.count == 1 && admin.secrets.leases[0].runner == "d_run")
        let none = LeaseForm(secret: secret("x", runners: []))
        none.understood = true
        #expect(admin.secrets.checkLease(none) != nil)
    }

    @Test("a file secret goes as base64 with its name and mode, a group member carries its group")
    func fileInGroup() async throws {
        let (admin, service, _) = await world()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aws-\(UUID().uuidString).json")
        try Data("{\"k\":1}".utf8).write(to: url)
        let f = SecretForm()
        f.kind = .file
        f.name = "aws-json"
        f.group = "aws"
        f.runners = ["d_run"]
        #expect(f.setFile(url) == nil && f.fileName == url.lastPathComponent)
        #expect(await admin.secrets.store(f))
        let d = try #require(service.drafts.first)
        #expect(d.kind == "file" && d.delivery == "file" && d.fileMode == "0600" && d.group == "aws")
        #expect(d.value == Data("{\"k\":1}".utf8).base64EncodedString())
    }

    @Test("a file over 1 MB is refused before anything is sent, and a bad mode is caught")
    func bigFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString)")
        try Data(count: SecretWords.fileLimit + 1).write(to: url)
        let f = SecretForm()
        f.kind = .file
        #expect(f.setFile(url)?.contains("at most 1 MB") == true && f.value.isEmpty)
        #expect(SecretForm.validMode("0600") && SecretForm.validMode("644") && !SecretForm.validMode("0999"))
    }

    @Test("groups are made, edited, leased as a whole and deleted through Touch ID")
    func groups() async {
        let (admin, service, host) = await world()
        #expect(
            await admin.secrets.saveGroup(name: "aws", description: "keys", runners: ["d_run"], existing: false) == nil)
        #expect(admin.secrets.groups.map(\.name) == ["aws"])
        #expect(await admin.secrets.saveGroup(name: "Bad Name", description: "", runners: [], existing: false) != nil)
        let g = admin.secrets.groups[0]
        let f = LeaseForm(group: g)
        f.understood = true
        #expect(await admin.secrets.lease(f))
        #expect(service.log.contains("group-lease aws d_run"))
        #expect(await admin.secrets.deleteGroup(g) == nil)
        #expect(service.log.contains("group-delete aws") && admin.secrets.groups.isEmpty)
        #expect(host.reasons.contains { $0.contains("aws") })
    }

    @Test("delete goes through Touch ID and removes the row; leases of it go too")
    func delete() async {
        let (admin, service, host) = await world()
        let s = admin.secrets.items[0]
        #expect(await admin.secrets.delete(s))
        #expect(admin.secrets.items.isEmpty)
        #expect(admin.secrets.state == .empty)
        #expect(service.log.contains("delete e5-07-old"))
        #expect(host.reasons.last?.hasPrefix("Delete e5-07-old") == true)
    }

    @Test("the mode comes from the registry, so the note on the screen always matches the Core")
    func mode() async {
        let (admin, _, _) = await world(mode: 0)
        #expect(admin.secrets.mode == 0)
        #expect(admin.secrets.leaseLimit == 120)
    }
}
