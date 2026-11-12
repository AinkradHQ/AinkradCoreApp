import Foundation
import Testing

@testable import Accounts

@MainActor
struct PlacementTests {
    func seat(_ id: String, _ labels: [String], pool: Int64? = nil, provider: String = "anthropic", new: Bool = false)
        -> OrderSeat
    {
        OrderSeat(id: id, labels: labels, provider: provider, poolID: pool, isNew: new)
    }

    @Test func aNewAccountGoesLastByDefaultAndFirstOnRequest() {
        let seats = [seat("a", ["tech"], pool: 1, provider: "claude-sub")]
        let new = seat("n", ["creative"], pool: 2, new: true)
        #expect(Placement.inserting(new, into: seats, at: nil).map(\.title) == ["tech", "creative"])
        #expect(Placement.inserting(new, into: seats, at: 0).map(\.title) == ["creative", "tech"])
        #expect(Placement.inserting(new, into: seats, at: 99).map(\.title) == ["tech", "creative"])
        #expect(Placement.inserting(new, into: seats, at: -3).map(\.title) == ["creative", "tech"])
    }

    @Test func anAccountThatJoinsAPoolInTheOrderSharesItsSeat() {
        let seats = [seat("a", ["creative"], pool: 2), seat("b", ["tech"], pool: 1)]
        let out = Placement.inserting(seat("n", ["extra"], pool: 2, new: true), into: seats, at: 1)
        #expect(out.map(\.title) == ["creative + extra", "tech"])
    }

    @Test func thePreviewReadsLikeTheDesign() {
        let seats = [seat("a", ["tech"]), seat("b", ["creative"])]
        #expect(Placement.preview(seats) == "Agents will try: 1. tech → 2. creative")
        #expect(Placement.preview([]) == "Agents will try: nothing yet")
    }

    @Test func positionsAndUsedWords() {
        let seats = [seat("a", ["tech"]), seat("b", ["creative"])]
        #expect(Placement.positionWords(0, in: seats) == "First")
        #expect(Placement.positionWords(1, in: seats) == "After tech")
        #expect(Placement.positionWords(2, in: seats) == "Last")
        #expect(Placement.usedWords(seat: 0) == "Used first")
        #expect(Placement.usedWords(seat: 2) == "Used third")
        #expect(Placement.usedWords(seat: nil) == nil)
    }

    @Test func theCoresTwoRulesAreCheckedBeforeSending() {
        let full = (0..<4).map { seat("s\($0)", ["x\($0)"], pool: Int64($0 + 1)) }
        #expect(Placement.issue(adding: seat("n", ["y"], pool: 9, new: true), to: full) != nil)
        #expect(
            Placement.issue(adding: seat("n", ["y"], pool: 2, new: true), to: full) == nil, "an existing seat is shared"
        )
        let plan = [seat("p", ["tech"], pool: 1, provider: "claude-sub")]
        #expect(Placement.issue(adding: seat("n", ["me"], pool: 5, provider: "claude-sub", new: true), to: plan) != nil)
        #expect(Placement.issue(adding: seat("n", ["me"], pool: 5, new: true), to: plan) == nil)
    }

    @Test func dragReorderMovesOneItem() {
        #expect(Placement.reordered([1, 2, 3], moving: 3, to: 0) == [3, 1, 2])
        #expect(Placement.reordered([1, 2, 3], moving: 1, to: 9) == [2, 3, 1])
        #expect(Placement.reordered([1, 2, 3], moving: 7, to: 0) == [1, 2, 3])
    }

    @Test func theMonthlyLimitDefaultsToTwentyDollars() {
        #expect(AccountPlacement().monthlyLimitMicros == 20_000_000)
        #expect(Placement.limitMicros("20") == 20_000_000)
        #expect(Placement.limitMicros("$12.50") == 12_500_000)
        #expect(Placement.limitMicros("") == 0)
        #expect(Placement.limitMicros("0") == 0)
        #expect(Placement.limitMicros("abc") == nil)
        #expect(Placement.limitMicros("-1") == nil)
        #expect(Placement.limitWords(20_000_000) == "$20")
        #expect(Placement.limitWords(0) == "No limit")
    }

    // MARK: provider readiness

    func provider(_ id: String, plan: Bool = false) -> ProviderItem {
        ProviderItem(
            id: id, name: id, harness: "claude", authVar: "X", baseURL: "https://x", delivery: ["env"],
            loginMethods: plan ? ["browser_code"] : ["paste"], models: [], pricedAt: nil, builtin: true)
    }

    @Test func readinessComesFromWhatTheRunnersOffer() {
        let gw = AccountRunner(id: "r1", name: "oracle", online: true, commands: ["gateway"], drivers: ["agent"])
        let bare = AccountRunner(id: "r2", name: "bare", online: true)
        let off = AccountRunner(id: "r3", name: "off", online: false, commands: ["gateway", "login"])
        let key = provider("anthropic")
        let plan = provider("claude-sub", plan: true)
        #expect(ProviderReadiness.of(key, runners: [bare, gw]) == .ready(runner: "oracle", runnerID: "r1"))
        #expect(ProviderReadiness.of(plan, runners: [gw]) == .notInstalled)
        #expect(ProviderReadiness.of(key, runners: [bare]) == .notInstalled)
        #expect(ProviderReadiness.of(key, runners: [off]) == .needsRunner)
        #expect(ProviderReadiness.of(key, runners: []) == .needsRunner)
    }

    @Test func theKeyShapeIsCheckedWhileTyping() {
        #expect(ProviderWords.keyShape("anthropic", "sk-ant-api03-x")?.ok == true)
        #expect(ProviderWords.keyShape("anthropic", "hello")?.ok == false)
        #expect(ProviderWords.keyShape("anthropic", "  ") == nil)
        #expect(ProviderWords.keyShape("custom", "abc") == nil)
    }

    // MARK: the wizard writes

    func make() async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.gateState = GateState(mode: 1, providerAccounts: 1)
        svc.poolList = [pool(1, "anthropic", def: true, members: [1])]
        svc.accountList = [account(1, "tech")]
        svc.chainList = [
            ChainItem(
                id: 5, name: "default", isDefault: true,
                entries: [ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: nil)])
        ]
        model.use(svc)
        try? await Task.sleep(for: .milliseconds(80))
        return (model, svc, host)
    }

    @Test func theStandardPlacementLeavesTheDefaultsToTheCore() async throws {
        let (m, svc, _) = await make()
        let f = KeyEntryFlow()
        await f.load(m)
        f.key = "k"
        f.placement = AccountPlacement(position: 1)
        await f.connect(m, provider: "anthropic")
        let p = try #require(svc.placements.first)
        #expect(p.pool == 1 && p.chain == 5 && p.position == 1 && p.monthlyLimitMicros == 20_000_000)
    }

    @Test func aNewPoolAndANewOrderAreMadeFirstInTheOneTouchID() async throws {
        let (m, svc, host) = await make()
        let f = KeyEntryFlow()
        await f.load(m)
        f.key = "k"
        f.label = "creative"
        var place = AccountPlacement(monthlyLimitMicros: 0)
        place.pool = .new("Team Keys")
        place.chain = .new("night work")
        f.placement = place
        await f.connect(m, provider: "anthropic")
        let log = svc.log
        let iPool = try #require(log.firstIndex { $0.hasPrefix("createPool team-keys") })
        let iChain = try #require(log.firstIndex { $0.hasPrefix("createChain night-work") })
        let iAcc = try #require(log.firstIndex { $0.hasPrefix("createAccount") })
        #expect(iPool < iChain && iChain < iAcc)
        let p = try #require(svc.placements.first)
        #expect(p.pool != nil && p.chain != nil && p.monthlyLimitMicros == 0)
        #expect(host.reasons.filter { $0.hasPrefix("Add creative") }.count == 1, "one elevation for all three writes")
    }
}

@MainActor @Suite struct InstallAndCheckTests {
    @Test func aToolInstallEventBecomesProgressForTheRunnerAndTool() {
        let m = AccountsModel(host: FakeHost())
        m.toolInstall(["runner": "r1", "tool": "claude", "state": "running", "percent": "40", "step": "Downloading"])
        #expect(m.installs["r1|claude"] == ToolProgress(state: .running, percent: 40, step: "Downloading", reason: nil))
        m.toolInstall(["runner": "r1", "tool": "claude", "state": "done", "percent": "100"])
        #expect(m.installs["r1|claude"]?.state == .done)
    }

    @Test func installGoesToAnOnlineRunnerThatLacksTheTool() {
        let m = AccountsModel(host: FakeHost())
        let p = ProviderItem(
            id: "claude-sub", name: "Claude", harness: "claude", authVar: "X", baseURL: "https://x", delivery: ["env"],
            loginMethods: ["browser_code"], models: [], pricedAt: nil, builtin: true)
        let has = AccountRunner(id: "a", name: "has", online: true, tools: ["claude": "2.1.318"])
        let lacks = AccountRunner(id: "b", name: "lacks", online: true)
        let off = AccountRunner(id: "c", name: "off", online: false)
        #expect(m.installTarget(p, [has, lacks, off])?.id == "b")
        #expect(m.installTarget(p, [off]) == nil)
    }

    @Test func everyCheckResultHasPlainWordsAndOnlyOkIsGood() {
        for r in [
            "ok", "token_expired", "limit_reached", "no_runner", "runner_outdated", "runner_busy", "egress_not_proven",
            "unreachable", "timeout", "failed", "something_new",
        ] {
            #expect(!PlanCheckWords.of(r).title.isEmpty && PlanCheckWords.of(r).ok == (r == "ok"))
        }
    }
}
