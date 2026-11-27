import Foundation
import Testing

@testable import Projects

/// One run model: the project's own setup is the Default configuration and the header Start runs it; Settings saves the limits
/// as one change.
@MainActor
struct RunOneModelTests {
    private func make(live: Bool = false) async -> (RunConfigsModel, FakeService, FakeConfigsService, ProjectItem) {
        let host = FakeHost()
        let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "run-one-\(UUID())")!)
        let s = FakeService()
        m.use(s)
        _ = await until { m.load == .ready }
        _ = await m.create(
            name: "Tidepool", slug: "tidepool", colour: .blue,
            repos: [PickRepo(org: "o", name: "api", url: "https://github.com/o/api")])
        let cfg = FakeConfigsService()
        if live {
            cfg.runs = [
                RunRecord(
                    id: "r_d", state: "running", configID: nil, environment: nil, runner: "d", startedAt: nil,
                    stoppedAt: nil, stopReason: nil, error: nil)
            ]
        }
        m.configsService = cfg
        let r = RunConfigsModel(model: m, projectID: m.projects[0].id)
        await r.load()
        return (r, s, cfg, m.projects[0])
    }

    @Test func theDefaultStartsThroughTheProjectRunRouteNotAConfiguration() async {
        let (r, s, cfg, p) = await make()
        #expect(r.defaultRun == nil && r.name(of: nil) == "Default")
        await r.startDefault(p)
        #expect(s.calls.last == "run start")
        #expect(!cfg.calls.contains { $0.hasPrefix("start") })
        #expect(r.tab == .live)
    }

    @Test func aLiveDefaultIsRestartedAndAConfigurationsRunIsNotTheDefault() async {
        let (r, s, _, p) = await make(live: true)
        #expect(r.defaultRun?.id == "r_d")
        await r.startDefault(p)
        #expect(s.calls.last == "run restart")
        let (other, _, cfg, _) = await make()
        cfg.runs = [
            RunRecord(
                id: "r_c", state: "running", configID: 1, environment: "Development", runner: "d", startedAt: nil,
                stoppedAt: nil, stopReason: nil, error: nil)
        ]
        await other.load()
        #expect(other.defaultRun == nil && other.isLive(other.configs[0]))
    }

    @Test func theServicesTableHasOneRowPerSpecServiceAndWordsForANotRunningOne() throws {
        let spec = try RunWire.specVersion(Data(#"{"version":1,"origin":"manual","spec":\#(DemoRunService.small)}"#.utf8))
        let up = ProjectLive.Service(
            name: "web", memory: "212 MB", state: .up, cpu: 12, restarts: 2, health: "none")
        let rows = ServicesTable.rows(spec: spec, live: [up], metrics: [:])
        #expect(rows.map(\.name) == ["api", "web"] && rows[1].state == .up && rows[0].state == nil)
        #expect(ServicesTable.detail(rows[1]) == "CPU 12 % · restarted 2 times")
        #expect(ServicesTable.detail(rows[0]) == "Not running")
    }

    @Test func limitsSaveAsOneChangeAndNothingWhenUnchanged() {
        let old = ProjectLimits.standard
        var new = old
        new.cpus = 4
        new.memoryMb = 8192
        new.idleMinutes = 60
        let p = ProjectsModel.limitsPatch(from: old, to: new)
        #expect(p.cpuLimit == 4 && p.memLimitMb == 8192 && p.idleMinutes == 60 && p.idleNever == nil)
        #expect(ProjectsModel.limitsPatch(from: old, to: old).isEmpty)
    }
}
