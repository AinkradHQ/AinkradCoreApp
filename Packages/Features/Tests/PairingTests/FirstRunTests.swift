import Foundation
import Testing

@testable import CoreKit
@testable import Pairing
@testable import Shell

@MainActor
struct FirstRunTests {
    private func model(_ d: FakeDriver = FakeDriver(), paired: @escaping @MainActor () -> Void = {}) -> FirstRunModel {
        FirstRunModel(driver: d, onPaired: paired)
    }

    private func fill(_ m: FirstRunModel, endpoint: String = "http://127.0.0.1:7700", code: String = "abcdefghjk") {
        m.endpointText = endpoint
        m.typeCode(code)
    }

    private func settle(_ m: FirstRunModel, until ok: @MainActor () -> Bool) async {
        for _ in 0..<200 where !ok() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func codeFormatting() {
        #expect(CodeFormat.format("abcdefghjk") == "ABCDE-FGHJK")
        #expect(CodeFormat.format("abc") == "ABC")
        #expect(CodeFormat.format("abcde") == "ABCDE")
        #expect(CodeFormat.format("ABCDE-FGHJKXYZ") == "ABCDE-FGHJK")
        #expect(CodeFormat.format("ilo01") == "11001")
        #expect(CodeFormat.format("ab cd-e fghjk") == "ABCDE-FGHJK")
        #expect(CodeFormat.format("ainkrad-pair:v1?h=a") == "ainkrad-pair:v1?h=a")
        #expect(CodeFormat.isComplete("ABCDE-FGHJK") && !CodeFormat.isComplete("ABCDE"))
        #expect(CodeFormat.isComplete("ainkrad-pair:v1?x"))
    }

    @Test func endpoints() throws {
        #expect(try EndpointInput.parse("core.example.net").absoluteString == "https://core.example.net")
        #expect(
            try EndpointInput.parse(" https://core.example.net:7443 ").absoluteString == "https://core.example.net:7443"
        )
        #expect(try EndpointInput.parse("127.0.0.1:7700").absoluteString == "http://127.0.0.1:7700")
        #expect(try EndpointInput.parse("localhost:7700").scheme == "http")
        #expect(throws: CoreError.self) { try EndpointInput.parse("http://core.example.net") }
        #expect(throws: CoreError.self) { try EndpointInput.parse("") }
        #expect(throws: CoreError.self) { try EndpointInput.parse("https://core.example.net/path") }
    }

    @Test func badInputStaysOnTheForm() async {
        let m = model()
        m.endpointText = "http://127.0.0.1:7700"
        m.typeCode("ABC")
        await m.submit()
        #expect(m.stage == .form && m.codeError != nil && m.endpointError == nil)
        fill(m, endpoint: "")
        await m.submit()
        #expect(m.stage == .form && m.endpointError != nil)
        #expect(!m.canSubmit)
    }

    @Test func happyPathWithTheApproverApprovingBeforeYouConfirm() async {
        let d = FakeDriver()
        var opened = false
        let m = model(d) { opened = true }
        fill(m)
        await m.submit()
        #expect(m.stage == .sas && m.claim?.sas == "K7QD-2M9X-R4TB-0W6E")
        #expect(d.claimedWith?.1?.absoluteString == "http://127.0.0.1:7700")
        await settle(m) { m.approverApproved }
        #expect(m.approverApproved && !m.matched && m.stage == .sas)
        await m.confirmMatch()
        #expect(d.confirmed && m.matched && m.stage == .approved)
        m.finish()
        #expect(opened)
    }

    @Test func confirmingBeforeTheApprovalWaitsThenFinishes() async {
        let d = FakeDriver()
        d.approvals = [.success(.paired)]
        let m = model(d)
        fill(m)
        await m.submit()
        await m.confirmMatch()
        await settle(m) { m.stage == .approved }
        #expect(m.stage == .approved && m.matched)
    }

    @Test func everyClaimErrorHasItsOwnState() async {
        let cases: [(CoreError, Failure.Kind)] = [
            (.offline("refused"), .offline("refused")),
            (.rateLimited(retryAfter: 42), .rateLimited(42)),
            (.coreIdentityMismatch(pinned: "a", served: "b"), .identityMismatch),
            (.coreUnproven("x"), .unproven),
            (.clockSkew(serverTime: 5), .clockSkew(5)),
            (.pairingFailed, .badCode),
            (.pairingExpired, .expired),
            (.sasMismatch, .sasMismatch),
            (.noSharedMinor(builtFor: 1, serverSupported: [9]), .oldApp),
            (.keyStore("no"), .keychain("no")),
            (.protocolViolation("odd"), .other("odd")),
        ]
        for (error, kind) in cases {
            let d = FakeDriver()
            d.claimResult = .failure(error)
            let m = model(d)
            fill(m)
            await m.submit()
            #expect(m.stage == .failed(Failure(kind: kind)), "\(error)")
        }
    }

    @Test func fatalOnesCannotBeRetried() {
        #expect(Failure(kind: .identityMismatch).fatal)
        #expect(Failure(kind: .sasMismatch).fatal)
        #expect(!Failure(kind: .offline("x")).fatal)
        #expect(!Failure(kind: .rejected).fatal)
    }

    @Test func rateLimitSetsTheClock() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.rateLimited(retryAfter: 42))
        let m = model(d)
        fill(m)
        await m.submit()
        let wait = m.retryAt?.timeIntervalSinceNow ?? 0
        #expect(wait > 40 && wait <= 42)
    }

    @Test func rejectedAndExpiredWhileWaiting() async {
        for (status, kind) in [("rejected", Failure.Kind.rejected), ("expired", .expired)] {
            let d = FakeDriver()
            d.approvals = [.failure(CoreError.notApproved(status))]
            let m = model(d)
            fill(m)
            await m.submit()
            await settle(m) { m.stage != .sas }
            #expect(m.stage == .failed(Failure(kind: kind)))
        }
    }

    @Test func aRevokedDeviceIsToldSo() async {
        let d = FakeDriver()
        d.approvals = [.failure(CoreError.revoked)]
        let m = model(d)
        fill(m)
        await m.submit()
        await settle(m) { m.stage != .sas }
        #expect(m.stage == .failed(Failure(kind: .revokedHere)))
    }

    @Test func cancelBeforeApprovalGoesBackToTheForm() async {
        let m = model()
        fill(m)
        await m.submit()
        await m.cancel()
        #expect(m.stage == .form && m.codeText.isEmpty && m.claim == nil)
        #expect(m.endpointText == "http://127.0.0.1:7700")
    }

    @Test func cancelAfterApprovalSaysToRevokeThere() async {
        let d = FakeDriver()
        d.cancelResult = .revokeDeviceOnApprover(deviceID: "d_new")
        let m = model(d)
        fill(m)
        await m.submit()
        await m.cancel()
        #expect(m.stage == .failed(Failure(kind: .cancelledAfterApproval("d_new"))))
        #expect(Failure(kind: .cancelledAfterApproval("d_new")).text.contains("d_new"))
    }

    @Test func resumeShowsTheWaitingPairing() async {
        let d = FakeDriver()
        let m = model(d)
        await m.resume()
        #expect(m.stage == .form)
        d.resumeResult = FakeDriver.claim
        await m.resume()
        #expect(m.stage == .sas && m.claim?.sas == FakeDriver.claim.sas)
    }

    @Test func aQRNeedsNoAddress() {
        let m = model()
        m.typeCode("ainkrad-pair:v1?h=core.example.net&p=443")
        #expect(m.usesQR && m.canSubmit)
    }

    @Test func startOverKeepsTheAddressDropsTheCode() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.pairingFailed)
        let m = model(d)
        fill(m)
        await m.submit()
        m.reset()
        #expect(m.stage == .form && m.codeText.isEmpty && m.endpointText == "http://127.0.0.1:7700")
    }

    @Test func forgettingStartsFromTheFirstStepWithNothingTyped() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.pairingFailed)
        let m = model(d)
        fill(m)
        await m.submit()
        m.resetAll()
        #expect(m.step == .name && m.stage == .form && m.codeText.isEmpty && m.endpointText.isEmpty)
    }

    @Test func nameThenAddressThenCode() {
        let name = "test.firstrun.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let profile = UserProfile(defaults: d)
        let m = FirstRunModel(driver: FakeDriver(), profile: profile) {}
        #expect(m.step == .name)
        m.nameText = "  Ahmed "
        m.submitName()
        #expect(profile.name == "Ahmed" && m.step == .address)
        m.endpointText = ""
        m.submitAddress()
        #expect(m.step == .address && m.endpointError != nil)
        m.endpointText = "core.example.net"
        m.submitAddress()
        #expect(m.step == .code && m.endpointError == nil)
        m.editAddress()
        #expect(m.step == .address)
        // A Mac that already has a name goes straight to the address.
        #expect(FirstRunModel(driver: FakeDriver(), profile: profile) {}.step == .address)
    }

    @Test func skippingTheNameKeepsItEmpty() {
        let name = "test.firstrun.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let profile = UserProfile(defaults: d)
        let m = FirstRunModel(driver: FakeDriver(), profile: profile) {}
        m.submitName()
        #expect(!profile.hasName && m.step == .address)
    }
}
