import Foundation
import Testing

@testable import Accounts

/// Accessibility label audit (A-29): every Accounts page and filter is named.
struct AccountsLabelAuditTests {
    @Test func everyPageIsNamed() {
        for p in AccountsPage.allCases { #expect(!p.title.isEmpty, "\(p) has no title") }
    }

    @Test func healthLinesNeverComeBackEmpty() {
        let now = Date()
        for h in [
            AccountHealthItem(), AccountHealthItem(failStreak: 2), AccountHealthItem(authStreak: 1),
            AccountHealthItem(lastSuccessAt: now), AccountHealthItem(planStatus: "rejected"),
        ] {
            #expect(!AccountHealthWords.line(h, now: now).text.isEmpty)
        }
    }
}
