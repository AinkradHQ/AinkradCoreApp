import Foundation
import Testing

@testable import Projects

private let composeSpec = """
    {"services": {
      "web": {"image": "node:22-alpine", "ports": [{"port": 3000, "expose": true}]},
      "api": {"build": {"repo": "api"}, "ports": [{"port": 8000}],
              "env": {"KEY": "${secret:app_key}", "URL": "x-${secret:db_password}-${secret:app_key}", "PLAIN": "1"}}}}
    """

private func version(_ n: Int, _ origin: String, _ spec: String = composeSpec) -> SpecVersionItem {
    try! RunWire.specVersion(Data(#"{"version": \#(n), "origin": "\#(origin)", "spec": \#(spec)}"#.utf8))
}

struct RunWireTests {
    @Test func aSpecVersionIsReadByHand() {
        let v = version(2, "compose")
        #expect(v.version == 2 && v.drafted && v.source == "docker-compose.yml")
        #expect(v.services.map(\.name) == ["api", "web"])
        let web = v.services[1]
        #expect(web.image == "node:22-alpine" && web.port == 3000 && web.isPublic)
        #expect(v.services[0].image == "build api" && !v.services[0].isPublic)
        // Every secret the env refers to, once, sorted.
        #expect(v.secretNames == ["app_key", "db_password"])
        #expect(!version(1, "manual").drafted)
    }

    @Test func secretReferences() {
        #expect(RunWire.secretRefs("${secret:a}-${secret:b.c}") == ["a", "b.c"])
        #expect(RunWire.secretRefs("plain $HOME ${other}").isEmpty)
        #expect(RunWire.secretRefs("${secret:open").isEmpty)
    }

    @Test func secretsAndRunNeverCarryAValue() throws {
        let s = try RunWire.secrets(
            Data(#"[{"name":"app_key","kind":"text","version":2,"size":9,"updated_at":"2026-11-18T10:00:00Z"}]"#.utf8))
        #expect(s == [SecretItem(name: "app_key", version: 2, updatedAt: RunWire.date("2026-11-18T10:00:00Z"))])
        #expect(s[0].updatedAt != nil)
        let r = try RunWire.run(Data(#"{"state":"failed","error":"boom","idle_stop_at":null}"#.utf8))
        #expect(r == RunStatus(state: "failed", error: "boom", idleStopAt: nil))
        #expect(throws: RunFailure.self) { try RunWire.secrets(Data("{}".utf8)) }
    }

    @Test func servicesReadTheCoresFields() throws {
        let json = #"""
            {"run":"r_1","services":[
              {"name":"web","state":"running","health":"healthy","cpu_percent":12.6,"memory_bytes":134217728,"memory_limit_bytes":0,"restarts":0},
              {"name":"api","state":"exited","health":"none","cpu_percent":null,"memory_bytes":0,"memory_limit_bytes":0,"restarts":3},
              {"name":"db","state":"created","health":"starting","cpu_percent":null,"memory_bytes":0,"memory_limit_bytes":0,"restarts":1}]}
            """#
        let s = try RunWire.services(Data(json.utf8))
        #expect(s.map(\.state) == [.up, .exited, .down])
        #expect(s[0].cpu == 13 && s[0].health == "healthy" && s[0].memory.contains("128"))
        #expect(s[1].cpu == nil && s[1].restarts == 3 && s[2].health == "starting")
        let logs = try RunWire.logs(
            Data(#"{"run":"r_1","lines":[{"seq":4,"service":"web","at":"x","text":"up"}],"next":5,"lost":0}"#.utf8),
            after: 0)
        #expect(logs.next == 5 && logs.lines == [ProjectLive.LogLine(service: "web", text: "up")])
    }

    @Test func secretNamesFollowTheCoresRule() {
        #expect(SecretRules.nameProblem("stripe_secret") == nil)
        #expect(SecretRules.nameProblem("a.b-c_1") == nil)
        #expect(SecretRules.nameProblem("") != nil)
        #expect(SecretRules.nameProblem("Stripe") != nil)
        #expect(SecretRules.nameProblem("1key") != nil)
        #expect(SecretRules.nameProblem("key name") != nil)
        #expect(SecretRules.nameProblem(String(repeating: "a", count: 65)) != nil)
    }

    @Test func failuresUseTheCoresWordsOrOurs() {
        let bad = LiveProjectRunService.failure(
            status: 400, code: "invalid_spec", message: "services.web.image: not an image")
        #expect(bad.sentence == "services.web.image: not an image")
        #expect(
            LiveProjectRunService.failure(status: 409, code: "secrets_disabled", message: "").sentence.contains("off"))
        #expect(LiveProjectRunService.seg("a/b?c") == "a%2Fb%3Fc")
    }

    @Test func changesAreTheLinesThatDiffer() {
        let a = "{\n  \"a\": 1,\n  \"b\": 2\n}"
        let b = "{\n  \"a\": 1,\n  \"b\": 3\n}"
        let d = SpecDiff.lines(from: a, to: b)
        #expect(Set(d) == [.init(added: false, text: "  \"b\": 2"), .init(added: true, text: "  \"b\": 3")])
        #expect(SpecDiff.lines(from: a, to: a).isEmpty)
        // The first version: everything is new.
        #expect(SpecDiff.lines(from: nil, to: "x\ny").allSatisfy { $0.added })
    }
}

/// An in-memory Core for the Run page: records writes. The value of a secret is kept only to prove it is never shown.
final class FakeRunService: ProjectRunService, @unchecked Sendable {
    private let lock = NSLock()
    var versions: [SpecVersionItem]
    var stored: [SecretItem]
    var status: RunStatus?
    private(set) var calls: [String] = []
    private(set) var values: [String: String] = [:]
    var refuse: RunFailure?

    init(versions: [SpecVersionItem], stored: [SecretItem] = [], status: RunStatus? = nil) {
        self.versions = versions
        self.stored = stored
        self.status = status
    }
    func spec(project: Int64) async throws -> SpecVersionItem? { lock.withLock { versions.last } }
    func specVersion(project: Int64, _ version: Int) async throws -> SpecVersionItem {
        lock.withLock { versions.first { $0.version == version }! }
    }
    func saveSpec(project: Int64, json: String, origin: String) async throws -> SpecVersionItem {
        try lock.withLock {
            if let refuse { throw refuse }
            calls.append("save \(origin)")
            let v = SpecVersionItem(
                version: versions.count + 1, origin: origin, createdAt: nil, json: json,
                services: versions.last?.services ?? [])
            versions.append(v)
            return v
        }
    }
    func secrets(project: Int64) async throws -> [SecretItem] { lock.withLock { stored } }
    func setSecret(project: Int64, name: String, value: String) async throws {
        try lock.withLock {
            if let refuse { throw refuse }
            calls.append("secret \(name)")
            values[name] = value
            stored.removeAll { $0.name == name }
            stored.append(SecretItem(name: name, version: 1, updatedAt: Date()))
        }
    }
    func run(project: Int64) async throws -> RunStatus? { lock.withLock { status } }
    func touch(project: Int64) async throws { lock.withLock { calls.append("touch") } }
}

@MainActor
private func make(_ svc: FakeRunService, _ host: FakeHost = FakeHost()) async -> (RunPageModel, FakeHost) {
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "run-tests-\(UUID())")!)
    m.runService = svc
    let run = RunPageModel(model: m, projectID: 1)
    await run.load()
    return (run, host)
}

@MainActor
struct RunPageModelTests {
    @Test func missingSecretsComeFirstAndStoredOnesFollow() async {
        let svc = FakeRunService(
            versions: [version(1, "compose")],
            stored: [
                SecretItem(name: "app_key", version: 1, updatedAt: nil),
                SecretItem(name: "zzz", version: 1, updatedAt: nil),
            ])
        let (run, _) = await make(svc)
        #expect(run.loaded && run.drafted)
        #expect(run.secretRows.map(\.name) == ["app_key", "db_password", "zzz"])
        #expect(run.missingSecrets == ["db_password"])
    }

    @Test func settingASecretIsOneTouchIDAndTheValueIsNotInIt() async {
        let svc = FakeRunService(versions: [version(1, "manual")])
        let (run, host) = await make(svc)
        let ok = await run.setSecret(name: "db_password", value: "hunter2", replacing: false, projectName: "Demo")
        #expect(ok)
        #expect(svc.calls == ["secret db_password"])
        #expect(host.reasons.count == 1 && host.reasons[0].contains("db_password"))
        #expect(!host.reasons[0].contains("hunter2"))
        // The spec also names app_key, which is still missing.
        #expect(run.missingSecrets == ["app_key"])
        // Nothing the model holds is the value.
        #expect(run.secretRows.allSatisfy { !"\($0)".contains("hunter2") })
    }

    @Test func aDeclinedTouchIDWritesNothing() async {
        let host = FakeHost()
        host.declines = true
        let svc = FakeRunService(versions: [version(1, "manual")])
        let (run, _) = await make(svc, host)
        #expect(await run.setSecret(name: "x", value: "v", replacing: false, projectName: "Demo") == false)
        #expect(svc.calls.isEmpty && run.writeError == nil)
    }

    @Test func aRefusalStaysInTheSheetInWords() async {
        let svc = FakeRunService(versions: [version(1, "manual")])
        svc.refuse = RunFailure(sentence: "services.web.image: not an image", code: "invalid_spec", status: 400)
        let (run, _) = await make(svc)
        #expect(await run.saveSpec("{}", reason: "r", done: "d") == false)
        #expect(run.writeError == "services.web.image: not an image")
    }

    @Test func undoGoesBackToTheVersionBeforeTheDraftAsANewVersion() async {
        let before = version(1, "manual", #"{"services": {"web": {"image": "nginx"}}}"#)
        let svc = FakeRunService(versions: [before, version(2, "compose")])
        let (run, _) = await make(svc)
        #expect(run.drafted && run.previous?.version == 1)
        #expect(await run.undoDraft("Demo"))
        #expect(svc.calls == ["save manual"])
        #expect(svc.versions.count == 3 && svc.versions.last?.json == before.json)
        #expect(!run.drafted)
    }

    @Test func theFirstVersionHasNothingToUndo() async {
        let svc = FakeRunService(versions: [version(1, "compose")])
        let (run, _) = await make(svc)
        #expect(run.drafted && run.previous == nil)
        #expect(await run.undoDraft("Demo") == false)
        #expect(svc.calls.isEmpty)
    }
}
