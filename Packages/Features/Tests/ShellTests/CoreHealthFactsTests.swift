import Foundation
import Testing

@testable import Shell

struct CoreHealthFactsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func certificateInDays() {
        func cert(_ d: Int?) -> String? {
            CoreHealthFacts(version: "0.2.1", uptimeSecs: 0, certDaysLeft: d).certificate
        }
        #expect(cert(62) == "62 days" && cert(1) == "1 day" && cert(0) == "Expires today" && cert(-3) == "Expired")
        #expect(cert(nil) == nil)
        #expect(CoreHealthFacts(version: "x", uptimeSecs: 0, certDaysLeft: 5).certificateLow)
        #expect(!CoreHealthFacts(version: "x", uptimeSecs: 0, certDaysLeft: 62).certificateLow)
    }

    @Test func backupAgeAndSize() {
        func f(_ ago: Double?, _ bytes: Int64? = nil) -> CoreHealthFacts {
            CoreHealthFacts(
                version: "x", uptimeSecs: 0, lastBackupAt: ago.map { now.addingTimeInterval(-$0) },
                lastBackupBytes: bytes)
        }
        #expect(f(10).backupAge(now: now) == "Just now")
        #expect(f(3 * 3600).backupAge(now: now) == "3 hours ago")
        #expect(f(3600).backupAge(now: now) == "1 hour ago")
        #expect(f(5 * 86_400).backupAge(now: now) == "5 days ago")
        #expect(f(nil).backup(now: now) == nil)
        #expect(f(120).backup(now: now) == "2 minutes ago")
        #expect(f(3 * 3600, 12_000_000).backup(now: now)?.hasPrefix("3 hours ago, 12") == true)
    }

    @Test func uptimeShowsTheTwoBiggestUnits() {
        func up(_ s: Int64) -> String { CoreHealthFacts(version: "x", uptimeSecs: s).uptime }
        #expect(up(3 * 86_400 + 4 * 3600 + 59) == "3 days 4 hours")
        #expect(up(86_400) == "1 day")
        #expect(up(2 * 3600 + 5 * 60) == "2 hours 5 minutes")
        #expect(up(300) == "5 minutes")
        #expect(up(40) == "40 seconds")
    }
}
