import CoreKit
import Foundation
import Testing

@testable import Accounts

@MainActor
struct LimitsTests {
    func make(limits: [LimitItem] = []) async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.accountList = [account(1, "claude-main")]
        svc.usageList = [
            UsageItem(
                accountID: 1, fiveHours: .zero, sevenDays: .zero, limitShare: 0, limitsExhausted: false,
                hasLimits: !limits.isEmpty, drops: 0, companies: [], limits: limits)
        ]
        model.use(svc)
        await model.reload()
        return (model, svc, host)
    }

    static let day = LimitItem(
        unit: "tokens", windowSecs: 86_400, cap: 1_000, used: 400, warnPercent: 80, exhausted: false)

    @Test func readsTheLimitsOfOneAccount() async {
        let (m, _, _) = await make(limits: [Self.day])
        await m.reloadLimits()
        #expect(m.limitsLoad == .ready)
        #expect(m.limits(of: m.account(1)!) == [Self.day])
        #expect(Self.day.standing == .fine)
    }

    @Test func standingFollowsTheWarningAndTheCap() {
        func l(_ used: Int64, exhausted: Bool = false) -> LimitItem {
            LimitItem(unit: "messages", windowSecs: 60, cap: 100, used: used, warnPercent: 80, exhausted: exhausted)
        }
        #expect(l(79).standing == .fine)
        #expect(l(80).standing == .warning)
        #expect(l(100).standing == .reached)
        #expect(l(10, exhausted: true).standing == .reached)
    }

    @Test func addingALimitAsksForTouchIDThenReloads() async {
        let (m, svc, host) = await make()
        let ok = await m.setLimit(
            m.account(1)!, LimitDraft(unit: "tokens", windowSecs: 18_000, cap: 5_000_000, warnPercent: 75))
        #expect(ok)
        #expect(svc.log.contains("setLimit 1 tokens 18000 5000000 75"))
        #expect(host.reasons.count == 1)
        #expect(m.limits(of: m.account(1)!).isEmpty)
    }

    @Test func clearingALimitSendsUnitAndWindow() async {
        let (m, svc, host) = await make(limits: [Self.day])
        #expect(await m.clearLimit(m.account(1)!, Self.day))
        #expect(svc.log.contains("clearLimit 1 tokens 86400"))
        #expect(host.reasons.first?.hasPrefix("Remove the 1K tokens limit") == true)
    }

    @Test func aDeclinedTouchIDChangesNothing() async {
        let (m, svc, host) = await make()
        host.declines = true
        #expect(await m.clearLimit(m.account(1)!, Self.day) == false)
        #expect(!svc.log.contains { $0.hasPrefix("clearLimit") })
    }

    @Test func aDeviceWithoutAdminSeesForbiddenAndCannotWrite() async {
        let (m, svc, _) = await make()
        svc.usageFailure = CoreError.forbiddenScope
        await m.reloadLimits()
        #expect(m.limitsLoad == .forbidden)
        svc.usageFailure = nil
        svc.failure = CoreError.forbiddenScope
        #expect(
            await m.setLimit(m.account(1)!, LimitDraft(unit: "tokens", windowSecs: 60, cap: 1, warnPercent: 80))
                == false)
        #expect(m.readOnly)
    }

    @Test func aFailedReadShowsTheError() async {
        let (m, svc, _) = await make()
        svc.usageFailure = CoreError.http(status: 500, code: "internal", message: "boom")
        await m.reloadLimits()
        guard case .failed(let code, _) = m.limitsLoad else {
            Issue.record("expected failed")
            return
        }
        #expect(code == "internal")
    }

    @Test func wordsAndParsing() {
        #expect(UsageLimitWords.window(18_000) == "Every 5 hours")
        #expect(UsageLimitWords.window(172_800) == "Every 2 days")
        #expect(UsageLimitWords.window(90) == "Every 90 seconds")
        #expect(UsageLimitWords.amount(1, unit: "messages") == "1 message")
        #expect(UsageLimitWords.parseCap("5,000,000") == 5_000_000)
        #expect(UsageLimitWords.parseCap("0") == nil)
        #expect(UsageLimitWords.parseCap("abc") == nil)
    }
}
