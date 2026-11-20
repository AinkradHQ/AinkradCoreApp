import Foundation
import Testing

@testable import Projects

struct RunConfigsWireTests {
    @Test func aConfigurationIsReadByHand() throws {
        let c = try RunConfigsWire.config(
            Data(
                #"{"id":7,"name":"Dev server","command":"npm run dev","workdir":"./app","runner":"automatic","service":null,"port":3000,"restart":true}"#
                    .utf8))
        #expect(
            c
                == RunConfigItem(
                    id: 7, name: "Dev server", command: "npm run dev", workdir: "./app", runner: "automatic",
                    port: 3000, restart: true))
        #expect(throws: RunFailure.self) { try RunConfigsWire.config(Data("{}".utf8)) }
    }

    @Test func variablesNeverCarryAValue() throws {
        let v = try RunConfigsWire.vars(
            Data(
                #"[{"key":"A","kind":"plain","secret":null,"size":4},{"key":"DB","kind":"secret","secret":"database_url","size":null}]"#
                    .utf8))
        #expect(
            v == [RunVarItem(key: "A", secret: nil, size: 4), RunVarItem(key: "DB", secret: "database_url", size: 0)])
    }

    @Test func diffAndRunsAndEnvs() throws {
        let d = try RunConfigsWire.diff(Data(#"[{"key":"A","change":"same"},{"key":"B","change":"only_b"}]"#.utf8))
        #expect(d.map(\.change) == [.same, .onlyB])
        #expect(
            try RunConfigsWire.envs(Data(#"{"environments":["Development","Staging"]}"#.utf8)) == [
                "Development", "Staging",
            ])
        let r = try RunConfigsWire.runs(
            Data(
                #"[{"id":"r_1","state":"running","runner":"d_1","config_id":7,"environment":"Staging","started_at":"2026-11-19T10:00:00Z"}]"#
                    .utf8))
        #expect(r[0].live && r[0].configID == 7 && r[0].environment == "Staging" && r[0].startedAt != nil)
        #expect(
            try RunConfigsWire.imported(Data(#"{"imported":3,"skipped":[{"line":2,"reason":"x"}]}"#.utf8))
                == EnvImport(imported: 3, skipped: 1))
        #expect(
            try RunConfigsWire.runners(Data(#"[{"id":"d_1","name":"Mac"}]"#.utf8)) == [
                RunnerOption(id: "d_1", name: "Mac")
            ])
    }

    @Test func aPatchSendsOnlyWhatChanged() {
        #expect(RunConfigPatch(port: 0).json as NSDictionary == ["port": 0])
        #expect(RunConfigPatch(name: "x", restart: true).json as NSDictionary == ["name": "x", "restart": true])
        #expect(RunConfigPatch().json.isEmpty)
    }

    @Test @MainActor func namesAndImportCounts() {
        #expect(RunConfigsModel.varName(" api url ") == "API_URL")
        #expect(ImportEnvSheet.count("# c\nA=1\n\nB=2\nnope\n") == 2)
    }
}

final class FakeConfigsService: RunConfigsService, @unchecked Sendable {
    private let lock = NSLock()
    var items = [
        RunConfigItem(
            id: 1, name: "Dev", command: "npm run dev", workdir: "", runner: "automatic", port: nil, restart: false)
    ]
    var envs = ["Development", "Staging"]
    var plain: [String: String] = ["A": "secret-ish"]
    var linked: [String: String] = ["DB": "database_url"]
    private(set) var calls: [String] = []

    func configs(project: Int64) async throws -> [RunConfigItem] { lock.withLock { items } }
    func createConfig(project: Int64, name: String, command: String) async throws -> RunConfigItem {
        lock.withLock {
            let c = RunConfigItem(
                id: Int64(items.count + 1), name: name, command: command, workdir: "", runner: "automatic", port: nil,
                restart: false)
            items.append(c)
            calls.append("create \(name)")
            return c
        }
    }
    func updateConfig(project: Int64, id: Int64, _ patch: RunConfigPatch) async throws -> RunConfigItem {
        lock.withLock {
            calls.append("update \(patch.json.keys.sorted().joined(separator: ","))")
            return items[0]
        }
    }
    func deleteConfig(project: Int64, id: Int64) async throws {
        lock.withLock {
            calls.append("delete \(id)")
            items.removeAll { $0.id == id }
        }
    }
    func duplicateConfig(project: Int64, id: Int64) async throws -> RunConfigItem { items[0] }
    func start(project: Int64, config: Int64, environment: String?, replace: Bool) async throws -> RunRecord {
        lock.withLock {
            calls.append("start \(config) \(environment ?? "-") replace=\(replace)")
            return RunRecord(
                id: "r", state: "starting", configID: config, environment: environment, runner: "d", startedAt: nil,
                stoppedAt: nil, stopReason: nil, error: nil)
        }
    }
    func environments(project: Int64) async throws -> [String] { lock.withLock { envs } }
    func addEnvironment(project: Int64, name: String) async throws -> [String] {
        lock.withLock {
            envs.append(name)
            return envs
        }
    }
    func deleteEnvironment(project: Int64, name: String) async throws -> [String] {
        lock.withLock {
            envs.removeAll { $0 == name }
            return envs
        }
    }
    func vars(project: Int64, config: Int64, env: String) async throws -> [RunVarItem] {
        lock.withLock {
            plain.map { RunVarItem(key: $0.key, secret: nil, size: $0.value.count) }
                + linked.map { RunVarItem(key: $0.key, secret: $0.value, size: 0) }
        }
    }
    func setVar(project: Int64, config: Int64, env: String, key: String, value: String?, secret: String?) async throws {
        lock.withLock {
            calls.append("set \(key)")
            if let value {
                plain[key] = value
                linked[key] = nil
            }
            if let secret {
                linked[key] = secret
                plain[key] = nil
            }
        }
    }
    func deleteVar(project: Int64, config: Int64, env: String, key: String) async throws {
        lock.withLock {
            plain[key] = nil
            linked[key] = nil
        }
    }
    func reveal(project: Int64, config: Int64, env: String, key: String) async throws -> String {
        lock.withLock {
            calls.append("reveal \(key)")
            return plain[key] ?? ""
        }
    }
    func importEnv(project: Int64, config: Int64, env: String, text: String) async throws -> EnvImport {
        EnvImport(imported: 1, skipped: 0)
    }
    func diff(project: Int64, config: Int64, a: String, b: String) async throws -> [EnvDiffItem] {
        [EnvDiffItem(key: "A", change: .different)]
    }
    var runs: [RunRecord] = []
    func history(project: Int64) async throws -> [RunRecord] { lock.withLock { runs } }
    func logs(project: Int64, run: String, after: Int) async throws -> RunLogPage {
        RunLogPage(lines: [ProjectLive.LogLine(service: "web", text: "from \(run)")], next: after + 1)
    }
    func stop(project: Int64, run: String) async throws { lock.withLock { calls.append("stop \(run)") } }
    func runners() async throws -> [RunnerOption] { [] }
}

@MainActor
struct RunConfigsModelTests {
    private func make() async -> (RunConfigsModel, FakeConfigsService, FakeHost) {
        let host = FakeHost()
        let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "cfg-tests-\(UUID())")!)
        let svc = FakeConfigsService()
        m.configsService = svc
        let r = RunConfigsModel(model: m, projectID: 1)
        await r.load()
        return (r, svc, host)
    }

    @Test func loadPicksTheFirstConfigurationAndEnvironment() async {
        let (r, _, _) = await make()
        #expect(r.loaded && r.selectedConfig?.id == 1 && r.env == "Development" && r.envs.count == 2)
        #expect(r.vars.count == 2)
    }

    @Test func aRevealedValueIsReadOnRequestAndDroppedWhenHidden() async {
        let (r, svc, _) = await make()
        let a = r.vars.first { $0.key == "A" }!
        #expect(r.revealed.isEmpty)
        await r.toggleReveal(a)
        #expect(r.revealed["A"] == "secret-ish")
        await r.toggleReveal(a)
        #expect(r.revealed.isEmpty)
        // A linked variable has no value to show and the Core is not asked.
        await r.toggleReveal(r.vars.first { $0.key == "DB" }!)
        #expect(r.revealed.isEmpty && svc.calls == ["reveal A"])
    }

    @Test func switchingEnvironmentDropsRevealedValues() async {
        let (r, _, _) = await make()
        await r.toggleReveal(r.vars.first { $0.key == "A" }!)
        await r.pickEnv("Staging")
        #expect(r.env == "Staging" && r.revealed.isEmpty)
    }

    @Test func runningIsOneTouchIDAndReplacesNothingWhenNothingRuns() async {
        let (r, svc, host) = await make()
        let p = ProjectItem(
            id: 1, slug: "demo", name: "Demo", description: "", expose: false, repos: [], updatedAt: Date())
        await r.start(r.configs[0], project: p)
        #expect(svc.calls.contains("start 1 Development replace=false"))
        #expect(host.reasons.count == 1 && host.reasons[0].contains("Development"))
        #expect(r.tab == .live)
    }

    @Test func aDeclinedTouchIDStartsNothing() async {
        let (r, svc, host) = await make()
        host.declines = true
        let p = ProjectItem(
            id: 1, slug: "demo", name: "Demo", description: "", expose: false, repos: [], updatedAt: Date())
        await r.start(r.configs[0], project: p)
        #expect(!svc.calls.contains { $0.hasPrefix("start") })
    }

    @Test func editsSaveOnceAfterTheLastKeystroke() async throws {
        let (r, svc, _) = await make()
        let c = r.configs[0]
        r.edit(c, RunConfigPatch(command: "npm run"))
        r.edit(c, RunConfigPatch(command: "npm run dev", port: 3000))
        #expect(r.configs[0].port == 3000)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(svc.calls.filter { $0.hasPrefix("update") } == ["update command,port"])
    }

    @Test func addingAVariableUppercasesItsName() async {
        let (r, svc, _) = await make()
        #expect(await r.addVar(key: "api url", value: "x"))
        #expect(svc.calls.contains("set API_URL"))
        #expect(await !r.addVar(key: "  ", value: "x"))
    }

    @Test func compareListsDifferencesAgainstAnotherEnvironment() async {
        let (r, _, _) = await make()
        await r.toggleCompare()
        #expect(r.comparing && r.compareWith == "Staging" && r.differences == 1)
    }

    @Test func severalLiveRunsEachKeepTheirOwnLogAndStopByID() async {
        let (r, svc, host) = await make()
        let live = { (id: String, cfg: Int64) in
            RunRecord(
                id: id, state: "running", configID: cfg, environment: "Development", runner: "d", startedAt: nil,
                stoppedAt: nil, stopReason: nil, error: nil)
        }
        svc.runs = [live("r_b", 2), live("r_a", 1)]
        await r.load()
        #expect(r.liveRuns.map(\.id) == ["r_b", "r_a"])
        #expect(r.isLive(r.configs[0]))
        let task = Task { await r.watchLive() }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        #expect(r.logLines["r_a"]?.first?.text == "from r_a" && r.logLines["r_b"]?.first?.text == "from r_b")
        let p = ProjectItem(
            id: 1, slug: "demo", name: "Demo", description: "", expose: false, repos: [], updatedAt: Date())
        await r.stop(r.liveRuns[1], project: p)
        #expect(svc.calls.contains("stop r_a") && host.reasons.last?.contains("Stop") == true)
        // Running the config that is already live replaces only that one.
        await r.start(r.configs[0], project: p)
        #expect(svc.calls.contains("start 1 Development replace=true"))
    }
}
