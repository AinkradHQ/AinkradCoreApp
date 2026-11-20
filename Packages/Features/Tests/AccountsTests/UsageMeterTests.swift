import CoreKit
import Foundation
import Testing

@testable import Accounts

struct UsageWireTests {
    @Test func theCoresUsageObjectReadsIntoAMeterPerAccount() {
        let json = """
            [{"id": 1, "label": "a", "usage": {"state": "limit_hit", "state_until": "2026-11-20T09:00:00.000Z",
              "fraction": 1.0, "used": 100, "limit": 100, "unit": "percent", "window": "week",
              "resets_at": "2026-11-20T09:00:00Z", "source": "plan"}},
             {"id": 2, "label": "b"},
             {"id": 3, "usage": {"state": "ready", "fraction": 0.24, "used": 12000000, "limit": 50000000,
              "unit": "usd_micros", "window": "month"}}]
            """
        let m = AccountUsageProbe.meters(Data(json.utf8))
        #expect(m.keys.sorted() == [1, 3], "an account with no usage object has no meter")
        #expect(m[1]?.limitHit == true)
        #expect(m[1]?.stateUntil == Date(timeIntervalSince1970: 1_795_165_200))
        #expect(m[1]?.windowSecs == 604_800)
        #expect(m[3]?.unit == "usd_micros" && m[3]?.windowSecs == 2_592_000)
    }

    @Test func modelRowsReadPriceAndTheAllowFlagDefaultingToAllowed() {
        let json = """
            {"models": ["a"], "items": [
              {"model": "a", "allowed": false, "input_per_mtok_micro": 3000000, "output_per_mtok_micro": 15000000},
              {"model": "b"}]}
            """
        let rows = ModelRowsProbe.rows(Data(json.utf8))
        #expect(
            rows == [
                ModelRowItem(model: "a", allowed: false, inputMicro: 3_000_000, outputMicro: 15_000_000),
                ModelRowItem(model: "b", allowed: true, inputMicro: nil, outputMicro: nil),
            ])
        #expect(ModelRowsProbe.rows(Data(#"{"models": ["a"]}"#.utf8)).isEmpty, "an older Core has no items")
    }

    @Test func aMessageCapOrFiveHourPeriodIsWrittenAsTheCoreTakesIt() throws {
        let d = AccountLimitRules.draft(account: 7, period: "hour5", messages: 60, warn: 90)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BudgetPut(d))) as? [String: Any]
        #expect(json?["period"] as? String == "hour5")
        #expect(json?["message_cap"] as? Int == 60)
        #expect(json?["token_cap"] as? Int == 0)
        #expect(json?["subject"] as? String == "7")
        #expect(json?["hard_stop"] as? Bool == true)
        #expect(BudgetWords.periods.first?.title == "Every 5 hours")
    }
}

struct UsageSentenceMeterTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func aMeterInDollarsMessagesOrTokensSaysUsedOfLimit() {
        #expect(
            UsageSentence.of(
                UsageFacts(windowSecs: 2_592_000, used: 12_000_000, limit: 50_000_000, unit: "usd_micros"), tz: utc)
                == "$12 of $50 this month")
        #expect(
            UsageSentence.of(UsageFacts(windowSecs: 18_000, used: 60, limit: 900, unit: "messages"), tz: utc)
                == "60 of 900 messages these 5 hours")
        #expect(
            UsageSentence.of(
                UsageFacts(share: 0.38, windowSecs: 604_800, used: 38, limit: 100, unit: "percent"), tz: utc)
                == "38% of this week used")
    }
}

@MainActor
struct MeterModelTests {
    func make(_ configure: (FakeService) -> Void) async -> (AccountsModel, FakeService) {
        let model = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [account(1, "claude-main"), account(2, "spare")]
        configure(svc)
        model.use(svc)
        await model.reload()
        return (model, svc)
    }

    @Test func theCoresMeterDrivesTheSentenceTheBarAndTheLimitHitChip() async throws {
        let back = Date(timeIntervalSince1970: 1_795_165_200)
        let (m, _) = await make {
            $0.meterList = [
                1: AccountMeterItem(
                    state: "limit_hit", stateUntil: back, fraction: 1, used: 100, limit: 100, unit: "percent",
                    window: "week", resetsAt: back),
                2: AccountMeterItem(
                    state: "ready", fraction: 0.24, used: 12_000_000, limit: 50_000_000, unit: "usd_micros",
                    window: "month"),
            ]
        }
        let rows = m.orderRows
        #expect(rows[0].chip == .limitHit, "the account looks ready by state, the meter says it hit a limit")
        #expect(rows[0].sentence.hasPrefix("Used all of this week. Back "))
        #expect(rows[0].meter == 1)
        #expect(rows[1].sentence == "$12 of $50 this month")
        #expect(rows[1].meter == 0.24)
        #expect(rows[1].chip == .inUse, "the first row that can take work is the one in use")
    }

    @Test func withoutAMeterTheRowKeepsItsOlderWords() async {
        let (m, _) = await make { _ in }
        #expect(m.orderRows[0].sentence == "No use yet this month")
    }
}

@MainActor
struct ModelAllowTests {
    func make() async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [account(1, "claude-main")]
        svc.modelRowList = [
            1: [
                ModelRowItem(model: "sonnet", allowed: true, inputMicro: 3_000_000, outputMicro: 15_000_000),
                ModelRowItem(model: "opus", allowed: true, inputMicro: 15_000_000, outputMicro: 75_000_000),
            ]
        ]
        model.use(svc)
        await model.reload()
        await model.reloadModels(model.account(1)!)
        return (model, svc, host)
    }

    @Test func theSwitchWritesOnceBehindTouchIDAndTheRowFollows() async {
        let (m, svc, host) = await make()
        #expect(m.modelRows[1]?.allSatisfy(\.allowed) == true)
        await m.setModelAllowed(m.account(1)!, "opus", false)
        #expect(svc.log.contains("setModelAllowed 1 opus false"))
        #expect(m.modelRows[1]?.first { $0.model == "opus" }?.allowed == false)
        #expect(m.modelRows[1]?.first { $0.model == "sonnet" }?.allowed == true)
        #expect(host.reasons.count == 1)
    }

    @Test func aRefusedSwitchGoesBackAndSaysWhy() async {
        let (m, svc, _) = await make()
        svc.failure = CoreError.http(status: 400, code: "bad_request", message: "no")
        await m.setModelAllowed(m.account(1)!, "opus", false)
        #expect(m.modelRows[1]?.first { $0.model == "opus" }?.allowed == true)
        #expect(m.writeError["model-1-opus"] != nil)
    }

    @Test func aDeclinedTouchIDChangesNothing() async {
        let (m, svc, host) = await make()
        host.declines = true
        await m.setModelAllowed(m.account(1)!, "opus", false)
        #expect(m.modelRows[1]?.first { $0.model == "opus" }?.allowed == true)
        #expect(!svc.log.contains { $0.hasPrefix("setModelAllowed") })
    }
}

@MainActor
struct LimitBudgetTests {
    @Test func theLimitsRowsAreTheAccountsMessageCapBudgetsShortestWindowFirst() {
        func b(_ id: Int64, _ subject: String, _ period: String, cap: Int64?) -> BudgetItem {
            BudgetItem(
                id: id, kind: "account", subject: subject, company: nil, period: period, periodKey: "k", tokenCap: 0,
                usdCap: nil, spent: 0, usdSpent: 0, held: 0, raised: 0, raisedUSD: 0, warnAt: 80, hardStop: true,
                exhausted: false, messageCap: cap, messages: 30)
        }
        let all = [
            b(1, "7", "week", cap: 900), b(2, "7", "hour5", cap: 60), b(3, "8", "day", cap: 5),
            b(4, "7", "month", cap: nil),
        ]
        #expect(AccountLimitRules.rows(all, account: 7).map(\.id) == [2, 1])
        #expect(all[1].messageShare == 0.5)
        #expect(all[1].share == 0.5)
    }
}
