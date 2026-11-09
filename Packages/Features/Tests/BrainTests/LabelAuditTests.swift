import Foundation
import Testing

@testable import Brain

/// Accessibility label audit (A-29): every Brain tab is named.
struct BrainLabelAuditTests {
    @Test func everyTabIsNamed() {
        for t in BrainTab.allCases { #expect(!t.title.isEmpty, "\(t) has no title") }
    }
}
