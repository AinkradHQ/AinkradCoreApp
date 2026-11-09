import Foundation
import Testing

@testable import Pairing

/// Accessibility label audit (A-29): the Devices filters are words, not codes.
struct PairingLabelAuditTests {
    @Test func everyFilterIsAWord() {
        for f in DeviceFilter.allCases { #expect(!f.rawValue.isEmpty && !f.rawValue.contains("_")) }
    }
}
