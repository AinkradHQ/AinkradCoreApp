import Foundation
import Shell
import Testing

@testable import CoreKit
@testable import Pairing

@MainActor
struct AccountNoticeTests {
    private let names: [Int64: String] = [1: "Claude account Work", 2: "Claude account Personal"]
    private func make(_ kind: String, _ f: [String: String]) -> AccountNotice? {
        AccountNotice.make(kind: kind, fields: f, account: { names[$0] }, pool: { $0 == 7 ? "Team" : nil })
    }

    @Test func aFailoverReadsAsOneSentence() {
        let n = make(
            "account.failover", ["run": "r1", "from_account": "1", "to_account": "2", "to_session": "as_2", "hop": "1"])
        #expect(n?.title == "Claude account Work hit its limit, moved to Claude account Personal")
        #expect(n?.pushKind == "account_failover")
    }

    @Test func aFailoverWithNowhereToGoSaysSo() {
        let n = make("account.failover", ["run": "r1", "from_account": "1"])
        #expect(n?.title == "Claude account Work hit its limit and no other account was left")
        let waiting = make("account.failover", ["run": "r1", "from_account": "1", "to_session": "as_2"])
        #expect(waiting?.title.hasSuffix("a session is waiting for an account") == true)
    }

    @Test func limitsHealthAndExpiryUseTheirOwnWords() {
        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let limited = make("account.limited", ["account": "1", "class": "quota", "until": soon])
        #expect(limited?.title == "Claude account Work hit its quota" && limited?.sub?.hasPrefix("Back at") == true)
        #expect(limited?.pushKind == nil && limited?.isAlarm == false)
        let sick = make("account.health", ["account": "2", "reason": "auth_suspected"])
        #expect(sick?.title == "Claude account Personal is not working" && sick?.pushKind == "account_health")
        #expect(sick?.sub == "The provider may have refused its key.")
        let gone = make("account.expired", ["account": "1"])
        #expect(gone?.pushKind == "account_expired" && gone?.isAlarm == true)
    }

    @Test func budgetsNameTheAccountOrThePool() {
        #expect(
            make("account.budget", ["subject_kind": "pool", "subject": "7", "state": "warning"])?.title
                == "Team pool is close to its budget")
        let used = make("account.budget", ["subject_kind": "account", "subject": "1", "state": "exhausted"])
        #expect(used?.title == "Claude account Work used up its budget" && used?.isAlarm == true)
    }

    @Test func onlyTheFailoverStormAlarmAndUnknownAccountsAreHandled() {
        #expect(make("alarm.raised", ["alarm": "disk_free"]) == nil)
        #expect(make("alarm.raised", ["alarm": "failover_storm"])?.isAlarm == true)
        #expect(make("account.login.done", [:]) == nil)
        #expect(make("account.expired", ["account": "99"])?.title == "An account was turned off")
    }

    @Test func theBellKeepsOneEntryPerEventAndTheNewestTwenty() throws {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("account.health", ["account": "1", "reason": "upstream_errors"])
        m.accountNotice("account.health", ["account": "1", "reason": "auth_suspected"])
        #expect(m.shell.bell.items.count == 1 && m.shell.bell.items[0].kind == .alarm)
        for i in 0..<25 { m.accountNotice("account.expired", ["account": "\(i)"]) }
        #expect(m.shell.bell.items.count == 20)
    }

    @Test func aClearedAlarmTakesItsEntryOutOfTheBell() {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("alarm.raised", ["alarm": "failover_storm"])
        m.accountNotice("account.expired", ["account": "1"])
        #expect(m.shell.bell.items.count == 2)
        m.accountNotice("alarm.cleared", ["alarm": "disk_free"])
        #expect(m.shell.bell.items.count == 2)
        m.accountNotice("alarm.cleared", ["alarm": "failover_storm"])
        #expect(m.shell.bell.items.map(\.id) == ["account-expired-1"])
    }

    private func reapFields(in secs: Double, _ id: String = "t_1") -> [String: String] {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(secs))
        return ["terminal": id, "reason": "idle", "grace_secs": "120", "reap_at": at]
    }

    @Test func aTerminalAboutToCloseIsAToastAndABellEntry() {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("terminal.reap_warning", reapFields(in: 120))
        #expect(
            m.shell.toast?.message
                == "A terminal will close soon: nobody has used it for a while. Closes in about 2 minutes.")
        #expect(m.shell.toast?.actionTitle == "Keep it" && m.shell.toast?.undo != nil)
        #expect(m.shell.toast.map { $0.lifetime >= 100 } == true)
        #expect(m.shell.bell.items.map(\.id) == ["reap-t_1"])
        #expect(m.shell.bell.items[0].actions.map(\.label) == ["Keep it"])
        m.accountNotice("terminal.reap_warning", reapFields(in: 120))
        #expect(m.shell.bell.items.count == 1)
    }

    @Test func aShortGraceStillKeepsTheToastSevenSeconds() {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("terminal.reap_warning", reapFields(in: 3))
        #expect(m.shell.toast?.lifetime == 7)
        #expect(m.shell.toast?.message.hasSuffix("Closes in under a minute.") == true)
    }

    @Test func attachedOrClosedTakesBothAway() {
        for kind in ["terminal.attached", "terminal.closed"] {
            let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
            m.accountNotice("terminal.reap_warning", reapFields(in: 120))
            m.accountNotice(kind, ["terminal": "t_2"])
            #expect(m.shell.toast != nil && m.shell.bell.items.count == 1)
            m.accountNotice(kind, ["terminal": "t_1"])
            #expect(m.shell.toast == nil && m.shell.bell.items.isEmpty)
        }
    }

    @Test func keepItClearsBoth() throws {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("terminal.reap_warning", reapFields(in: 120))
        m.shell.bell.items[0].actions[0].run()
        #expect(m.shell.toast == nil && m.shell.bell.items.isEmpty)
    }

    @Test func theBellEntryGoesWhenReapAtPasses() async throws {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.accountNotice("terminal.reap_warning", reapFields(in: 1))
        #expect(m.shell.bell.items.count == 1)
        try await Task.sleep(for: .seconds(2.5))
        #expect(m.shell.bell.items.isEmpty && m.shell.toast == nil)
    }

    @Test func closesInIsPlainMinutes() {
        let now = Date()
        #expect(AccountNotice.closesIn(now.addingTimeInterval(60), now: now) == "Closes in about 1 minute")
        #expect(AccountNotice.closesIn(now.addingTimeInterval(119), now: now) == "Closes in about 2 minutes")
        #expect(AccountNotice.closesIn(now.addingTimeInterval(20), now: now) == "Closes in under a minute")
    }
}
