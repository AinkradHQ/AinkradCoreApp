import Foundation
import Testing

@testable import Admin

/// Accessibility label audit (A-29): the Admin filters carry a name VoiceOver can read.
struct AdminLabelAuditTests {
    @Test func everyActorFilterHasAName() {
        for f in ActorFilter.allCases { #expect(!f.rawValue.isEmpty) }
    }
}
