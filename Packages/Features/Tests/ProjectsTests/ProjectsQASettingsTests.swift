import Foundation
import Testing

@testable import Projects

private func project(_ id: Int64 = 1) -> ProjectItem {
    ProjectItem(id: id, slug: "demo", name: "Demo", description: "", expose: false, repos: [], updatedAt: Date())
}

struct SettingsWordsTests {
    @Test func oneSaveIsTheDefaultAction() {
        let both: [SettingsSave: Bool] = [.name: true, .running: true, .link: false]
        #expect(SettingsSave.defaultAction(touched: .running, showing: both) == .running)
        #expect(SettingsSave.defaultAction(touched: .link, showing: both) == .name)
        #expect(SettingsSave.defaultAction(touched: .name, showing: [.link: true]) == .link)
    }

    @Test func theLinkNameLockSaysWhy() {
        #expect(SettingsSave.linkLock(nil, running: false) == nil)
        #expect(SettingsSave.linkLock("running", running: false)?.contains("Stop the project") == true)
        #expect(SettingsSave.linkLock("has_secrets", running: false)?.contains("secrets") == true)
        #expect(SettingsSave.linkLock(nil, running: true) != nil)
    }

    @Test func aDefaultEnvironmentPatchGoesAsRawJson() throws {
        let body = try LiveProjectsService.patchBody(ProjectPatch(defaultEnvironment: "Staging"))
        let o = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(o["default_environment"] as? String == "Staging" && o.count == 1)
        #expect(!ProjectPatch(defaultEnvironment: "x").isEmpty)
    }

    @Test func idleOffReadsAsASentence() {
        #expect(ProjectRules.idleSentence(minutes: 30, never: true) == "It does not stop by itself.")
        #expect(ProjectRules.idleSentence(minutes: 30, never: false) == "It stops after 30 min with no visits.")
    }

    @Test func kindsHaveOneShortName() {
        #expect(ProjectKind.allCases.map(\.short) == ["Web", "App", "Infra", "Docs"])
        #expect(ProjectKind.allCases.map(\.tileTitle) == ProjectKind.allCases.map(\.short))
    }

    @Test func aFreshTimeIsJustNow() {
        let now = Date()
        #expect(runsAgo(now.addingTimeInterval(-5), now: now) == "just now")
        #expect(runsAgo(now.addingTimeInterval(-600), now: now) != "just now")
    }

    @Test @MainActor func aFixPromptCarriesTheFailure() {
        let t = ProjectsModel.fixPrompt(project: "Demo", what: "The build of Dev", details: ["boom", nil, ""])
        #expect(t.contains("The build of Dev of Demo failed.") && t.contains("boom") && t.hasSuffix("propose a fix."))
    }

    @Test func aCrashLoopIsSaidAsStopped() {
        let c = ServiceCrash(
            project: 1, run: "r", service: "api", exitCode: 1, restarts: 3, config: nil, environment: nil, at: Date())
        #expect(c.words == "api kept crashing and was stopped")
    }
}

@MainActor
struct DefaultEnvironmentTests {
    @Test func theDefaultEnvironmentSavesBehindTouchIDAndRollsBackWhenDeclined() async {
        let host = FakeHost()
        let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "qa3-\(UUID())")!)
        let s = MinService([project()])
        m.use(s)
        m.insightsService = FakeInsights()
        let i = ProjectInsightsModel(model: m, project: project())
        await i.loadTuning()
        await i.set(defaultEnvironment: "Staging")
        #expect(s.patches.contains { $0.defaultEnvironment == "Staging" })
        #expect(host.reasons.contains { $0.contains("default environment") })
        host.declines = true
        await i.set(defaultEnvironment: "Production")
        #expect(i.tuning.defaultEnvironment != "Production")
    }
}

@MainActor
struct RunsQATests {
    private func make(core112: Bool = true) async -> (RunConfigsModel, FakeConfigsService, FakeHost) {
        let host = FakeHost()
        let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "qa3-runs-\(UUID())")!)
        m.core112 = core112
        let svc = FakeConfigsService()
        m.configsService = svc
        let r = RunConfigsModel(model: m, projectID: 1)
        await r.load()
        return (r, svc, host)
    }

    @Test func theDefaultKeepsItsOwnVariables() async {
        let (r, svc, host) = await make()
        await r.pickConfig(RunConfigsModel.defaultID)
        #expect(r.envIsDefault && r.envReady && r.vars.map(\.key) == ["PORT"])
        #expect(await r.addVar(key: "token", value: "x"))
        #expect(svc.calls.contains("setDefault TOKEN Development"))
        await r.deleteVar(r.vars[0])
        #expect(svc.calls.contains { $0.hasPrefix("deleteDefault") })
        #expect(host.reasons.count >= 2)
        // Values are write-only: showing one asks the Core nothing.
        await r.toggleReveal(RunVarItem(key: "PORT", secret: nil, size: 4))
        #expect(r.revealed.isEmpty && !svc.calls.contains { $0.hasPrefix("reveal") })
    }

    @Test func theDefaultHasNoVariablesOnAnOlderCore() async {
        let (r, _, _) = await make(core112: false)
        await r.pickConfig(RunConfigsModel.defaultID)
        #expect(!r.envReady && r.vars.isEmpty)
    }

    @Test func aFailedReadOfVariablesIsAnErrorNotAnEmptyList() async {
        let (r, svc, _) = await make()
        svc.failDefaultVars = true
        await r.pickConfig(RunConfigsModel.defaultID)
        #expect(r.varsError != nil && r.vars.isEmpty)
        svc.failDefaultVars = false
        await r.loadVars()
        #expect(r.varsError == nil && !r.vars.isEmpty)
    }

    @Test func buildAgainUsesTheRunsOwnEnvironment() async {
        let (r, svc, _) = await make()
        await r.start(r.configs[0], project: project(), environment: "Staging")
        #expect(svc.calls.contains("start 1 Staging replace=false"))
        await r.start(r.configs[0], project: project(), environment: "Gone")
        #expect(svc.calls.contains("start 1 Development replace=false"))
    }

    @Test func writesAskForTouchID() async {
        let (r, _, host) = await make()
        await r.create()
        #expect(!host.reasons.isEmpty)
    }

    @Test func anEditSavesWhenThePageCloses() async {
        let (r, svc, _) = await make()
        r.edit(r.configs[0], RunConfigPatch(command: "npm start"))
        #expect(r.hasPending)
        await r.flushAll()
        #expect(svc.calls.contains("update command") && !r.hasPending)
    }

    @Test func anEditIsKeptWhileTheCoreCannotBeReached() async {
        let (r, svc, _) = await make()
        svc.updateError = URLError(.notConnectedToInternet)
        r.edit(r.configs[0], RunConfigPatch(command: "npm start"))
        await r.flushAll()
        #expect(r.hasPending && r.writeError?.contains("saves when the Core is back") == true)
        #expect(r.configs[0].command == "npm start")
        svc.updateError = nil
        await r.flushAll()
        #expect(!r.hasPending && svc.calls.contains("update command"))
    }
}
