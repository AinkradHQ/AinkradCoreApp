import Testing

@testable import CoreKit

@Suite struct CoreSkewTests {
    @Test func onlyAnOlderParsedCoreIsRefused() {
        #expect(CoreSkew.tooOld("0.9.0") && CoreSkew.tooOld("0.9.12-beta"))
        #expect(!CoreSkew.tooOld("0.10.0") && !CoreSkew.tooOld("0.10.3") && !CoreSkew.tooOld("1.0.0"))
        #expect(!CoreSkew.tooOld(nil) && !CoreSkew.tooOld("dev"), "an unknown version is not blocked")
        #expect(CoreSkew.tooOld("0.9.9", min: "0.10.0") && !CoreSkew.tooOld("0.10.0", min: "0.9.0"))
    }

    @Test func theAppIsOldOnlyWhenTheCoreSaysSo() {
        #expect(CoreSkew.appTooOld(app: "0.10.0", minApp: "0.10.1") && !CoreSkew.appTooOld(app: "0.10.1", minApp: "0.10.1"))
        #expect(!CoreSkew.appTooOld(app: "0.10.0", minApp: nil) && !CoreSkew.appTooOld(app: "dev", minApp: "0.10.1"))
    }

    @Test func theMessageNamesBothVersions() {
        let m = CoreSkew.message(core: "0.9.0")
        #expect(m.contains("0.9.0") && m.contains(CoreSkew.minCore))
    }
}
