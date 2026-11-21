import Foundation
import Testing

@testable import Accounts

struct AccountDetailWireTests {
    let now = Date(timeIntervalSince1970: 1_795_262_400)  // 2026-11-21 12:00 UTC

    @Test func theSeriesFillsSevenDaysEndingTodayAndKeepsOnlyTheAsked() throws {
        let json = """
            [{"day": "2026-11-15", "provider": "claude-sub", "total_tokens": 100, "cost_usd_micros": 0},
             {"day": "2026-11-21", "provider": "claude-sub", "total_tokens": 7, "cost_usd_micros": 0},
             {"day": "2026-11-21", "provider": "anthropic", "total_tokens": 5, "cost_usd_micros": 900}]
            """
        let all = try #require(AccountDetailWire.days(Data(json.utf8), provider: nil, now: now))
        #expect(all.count == 7)
        #expect(all.map(\.tokens) == [100, 0, 0, 0, 0, 0, 12], "a day with no row is zero, today is last")
        let plan = try #require(AccountDetailWire.days(Data(json.utf8), provider: "claude-sub", now: now))
        #expect(plan.last?.tokens == 7 && plan.last?.usdMicros == 0)
        #expect(AccountDetailWire.days(Data("{}".utf8), provider: nil, now: now) == nil)
    }

    @Test func sessionsReadLenientlyAndUnknownIsTheDefaultModel() {
        let json = """
            [{"session_id": "as_1", "title": "Fix it", "model": "unknown", "runner_name": "box", "tokens": 42,
              "started_at": "2026-11-21T10:00:00Z", "moved_to_account": 2, "ended_at": "2026-11-21T10:30:00Z"},
             {"session_id": "as_2", "tokens": 1, "usd_micros": 30, "started_at": "2026-11-21T11:00:00Z"}]
            """
        let s = AccountDetailWire.sessions(Data(json.utf8))
        #expect(s.count == 2)
        #expect(s[0].model == nil && s[0].moved && !s[0].live)
        #expect(s[1].live && s[1].usdMicros == 30 && s[1].title == nil)
    }

    @Test func anOlderCorePicksTheAccountsRowsOutOfAgentSessions() {
        let json = """
            [{"id": "as_9", "runner": "d_1", "account": 3, "title": "Plan", "model": "claude-opus-4-1",
              "usage": {"input": 10, "output": 5, "cache_read": 1, "cache_write": 0, "cost_usd_micros": 77},
              "created_at": "2026-11-21T09:00:00Z", "failed_over_to": "as_10"},
             {"id": "as_8", "runner": "d_1", "account": 4, "created_at": "2026-11-21T09:00:00Z"}]
            """
        let s = AccountDetailWire.agentSessions(Data(json.utf8), account: 3, runners: ["d_1": "attic box"])
        #expect(s.map(\.id) == ["as_9"])
        #expect(s[0].tokens == 16 && s[0].usdMicros == 77 && s[0].runnerName == "attic box" && s[0].moved)
    }

    @Test func theLastCheckIsReadFromTheAccountRow() {
        let c = AccountDetailWire.lastCheck(
            Data(#"{"id": 1, "last_check": {"at": "2026-11-21T11:48:00Z", "ok": true, "answer_ms": 3200}}"#.utf8))
        #expect(c?.ok == true && c?.answerMs == 3200)
        #expect(AccountDetailWire.lastCheck(Data(#"{"id": 1}"#.utf8)) == nil, "an older Core says nothing")
    }
}

struct AccountDetailFactsTests {
    let now = Date(timeIntervalSince1970: 1_795_262_400)

    @Test func ordinals() {
        #expect(
            [1, 2, 3, 4, 11, 12, 13, 21, 22].map(DetailFacts.ordinal) == [
                "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd",
            ])
    }

    @Test func timeGoneComesFromTheResetAndTheWindowLength() {
        let reset = now.addingTimeInterval(9_000)  // half of 5 hours left
        #expect(DetailFacts.gone(resetsAt: reset, length: DetailFacts.fiveHours, now: now) == 0.5)
        #expect(DetailFacts.gone(resetsAt: nil, length: DetailFacts.fiveHours, now: now) == nil)
    }

    @Test func paceSaysWhenTheWindowFillsBeforeItResets() {
        let reset = now.addingTimeInterval(9_000)
        let fast = DetailFacts.pace(
            used: 0.8, gone: 0.5, resetsAt: reset, length: DetailFacts.fiveHours, now: now, short: true)
        #expect(fast.hasPrefix("Faster than the clock: full around"))
        #expect(
            DetailFacts.pace(
                used: 0.2, gone: 0.5, resetsAt: reset, length: DetailFacts.fiveHours, now: now, short: true)
                == "Well inside")
        #expect(
            DetailFacts.pace(used: 0.45, gone: 0.5, resetsAt: reset, length: DetailFacts.week, now: now, short: false)
                == "On pace")
        #expect(
            DetailFacts.pace(used: 0.7, gone: 0.5, resetsAt: reset, length: DetailFacts.week, now: now, short: false)
                == "Ahead of the clock")
    }

    @Test func spendIsCarriedOnAtTodaysRate() {
        #expect(DetailFacts.projected(spend: 52_800_000, gone: 0.7) == 75_428_571)
        #expect(DetailFacts.dollars(80_000_000) == "$80" && DetailFacts.dollars(52_800_000) == "$52.80")
        #expect(DetailFacts.compact(4_100_000) == "4.1M" && DetailFacts.compact(69_800) == "70k")
    }

    @Test func whoComesBefore() {
        #expect(DetailFacts.above([("Studio plan", true), ("Side plan", true)]) == "both plans are")
        #expect(DetailFacts.above([("Studio plan", true)]) == "Studio plan is")
        #expect(DetailFacts.above([("A", true), ("B", false), ("C", false)]) == "the 3 accounts above it are")
    }
}

@MainActor
struct AccountDetailStateTests {
    func make(_ list: [AccountItem]) async -> AccountsModel {
        let model = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = list
        svc.orderEntries = list.map { AIOrderEntry(account: $0.id, provider: nil, harness: nil, model: nil) }
        model.use(svc)
        await model.reload()
        return model
    }

    @Test func aReadyAccountInTheOrderIsNeverNotInAPool() async {
        let m = await make([account(1, "plan", provider: "claude-sub"), account(2, "key")])
        #expect(m.verdict(m.account(2)!).kind == .ready, "each AI order entry is a hidden one-account pool")
        #expect(m.detailState(m.account(1)!) == .ready)
        #expect(m.detailWords(m.account(1)!).title == "AI sessions use it first")
        #expect(m.detailWords(m.account(2)!).title == "Used when \(m.title(m.account(1)!)) is full")
        #expect(m.primaryAction(m.account(1)!) == .check)
    }

    @Test func eachStateHasItsOneMainAction() async {
        var full = account(1, "plan", provider: "claude-sub", state: "limited")
        full.health = AccountHealthItem(windows: [PlanWindowItem(name: "five_hour", utilization: 1, resetsAt: nil)])
        var out = account(2, "out", provider: "claude-sub")
        out.health = AccountHealthItem(authStreak: 1)
        let off = account(3, "off", provider: "claude-sub", state: "disabled")
        let m = await make([full, out, off, account(4, "key")])
        #expect(m.detailState(m.account(1)!) == .full && m.primaryAction(m.account(1)!) == .order)
        #expect(m.detailWords(m.account(1)!).title == "The 5-hour window is full")
        #expect(m.detailWords(m.account(1)!).line.hasPrefix("\(m.title(m.account(4)!)) takes new work"))
        #expect(m.detailState(m.account(2)!) == .signedOut && m.primaryAction(m.account(2)!) == .signIn)
        #expect(m.detailState(m.account(3)!) == .off && m.primaryAction(m.account(3)!) == .turnOn)
        #expect(!m.moreActions(m.account(4)!).contains(.signIn), "a key has no sign-in")
        #expect(!m.moreActions(m.account(1)!).contains(.key), "a plan has no key")
    }
}
