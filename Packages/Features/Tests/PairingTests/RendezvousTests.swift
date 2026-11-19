import CoreKit
import CryptoKit
import Foundation
import Testing

@testable import Pairing

private let fp = Wire.b64(Data(repeating: 7, count: 32))
private let secret = Wire.b64(Data(repeating: 9, count: 16))
private let link = "ainkrad://connect?host=core.example.com&fp=\(fp)&secret=\(secret)"

/// What the installer does (`rendezvous.rs` in the Core): seal `text` to the session's key.
private func seal(_ text: String, to s: RendezvousSession, code: Data? = nil) throws -> (epk: Data, ct: Data) {
    let eph = Curve25519.KeyAgreement.PrivateKey()
    let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: s.publicKey)
    let epk = eph.publicKey.rawRepresentation
    let sym = try eph.sharedSecretFromKeyAgreement(with: peer).hkdfDerivedSymmetricKey(
        using: SHA256.self, salt: code ?? s.code, sharedInfo: RendezvousSession.context + epk + s.publicKey,
        outputByteCount: 32)
    let box = try ChaChaPoly.seal(
        Data(text.utf8), using: sym, nonce: ChaChaPoly.Nonce(data: Data(count: 12)),
        authenticating: RendezvousSession.context)
    // A fresh Data: the sum of two slices keeps the first one's start index, and `bad[0]` would trap.
    return (epk, Data(box.ciphertext + box.tag))
}

private final class FakeRendezvous: RendezvousClient, @unchecked Sendable {
    var answers: [Result<(epk: Data, ct: Data)?, Error>]
    private(set) var asked: [String] = []
    init(_ a: [Result<(epk: Data, ct: Data)?, Error>]) { answers = a }
    func fetch(id: String) async throws -> (epk: Data, ct: Data)? {
        asked.append(id)
        guard !answers.isEmpty else { return nil }
        return try answers.removeFirst().get()
    }
}

@MainActor
private final class FakeDiscovery: CoreDiscovery {
    var report: (@MainActor ([NearbyCore]) -> Void)?
    private(set) var stopped = 0
    func start(_ found: @escaping @MainActor ([NearbyCore]) -> Void) { report = found }
    func stop() { stopped += 1 }
}

@MainActor
struct RendezvousTests {
    @Test func theInstallerSealedLinkOpensOnlyForThisSession() throws {
        let s = RendezvousSession()
        let m = try seal(link, to: s)
        #expect(!String(decoding: m.ct, as: UTF8.self).contains("ainkrad://"))
        #expect(s.open(epk: m.epk, ct: m.ct) == link)
        #expect(RendezvousSession().open(epk: m.epk, ct: m.ct) == nil, "another app's key")
        let other = try seal(link, to: s, code: Data(repeating: 1, count: 16))
        #expect(s.open(epk: other.epk, ct: other.ct) == nil, "sealed with another code")
        var bad = m.ct
        bad[0] ^= 1
        #expect(s.open(epk: m.epk, ct: bad) == nil, "altered")
    }

    private func hex(_ h: String) -> Data {
        Data(
            stride(from: 0, to: h.count, by: 2).map { i in
                let a = h.index(h.startIndex, offsetBy: i)
                return UInt8(h[a..<h.index(a, offsetBy: 2)], radix: 16)!
            })
    }

    /// The same vector the Core's `rendezvous.rs` pins: sealed there (and by an independent implementation), opened here.
    @Test func theVectorSealedByTheInstallerSideOpens() throws {
        let key = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"))
        let s = RendezvousSession(code: Data(repeating: 7, count: 16), key: key)
        #expect(s.spec == "BwcHBwcHBwcHBwcHBwcHBw.3p7bfXt9wbTTW2HC7OQ1Nz-DQ8hbeGdNrfx-FG-IK08")
        #expect(s.id == "12HUBq8qSloV9nySQ3jtiNH4XBPxo3_HNm9ZeJs7zWU")
        let epk = try #require(Wire.unb64("hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"))
        let ct = try #require(
            Wire.unb64("rBL1S5cKm3hdu54gCEaoH51O343FmiVAKIZp0hurr2NGiMlq9YW-qXbI7lhtVvKrn3askCu1qcmh8FhkA5PS2e4c_rqnPQ")
        )
        #expect(s.open(epk: epk, ct: ct) == "ainkrad://connect?host=core.example.com&fp=FP&secret=S")
    }

    @Test func theCommandCarriesTheCodeAndTheKeyAndTheIdHidesTheCode() {
        let s = RendezvousSession()
        let cmd = SetupWizardModel.installCommand(rendezvous: s.spec)
        #expect(
            cmd.hasPrefix(
                "sudo AINKRAD_MIN_VERSION=\(SetupWizardModel.minCoreVersion) AINKRAD_RENDEZVOUS=\(s.spec) sh -c"))
        let parts = s.spec.split(separator: ".")
        #expect(Wire.unb64(String(parts[0]))?.count == 16 && Wire.unb64(String(parts[1]))?.count == 32)
        #expect(!s.id.contains(String(parts[0])) && s.id.count == 43)
    }

    private func wizard(_ r: FakeRendezvous, _ d: FakeDiscovery = FakeDiscovery()) -> SetupWizardModel {
        let m = SetupWizardModel(driver: FakeDriver(), rendezvous: r, discovery: d) {}
        m.pollEvery = .milliseconds(1)
        m.waitFor = .milliseconds(80)
        return m
    }

    private func settle(_ m: SetupWizardModel, until done: @MainActor () -> Bool) async {
        for _ in 0..<400 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func theWaitMovesOnByItselfWhenTheLinkArrivesAndNeverConnectsByItself() async throws {
        let r = FakeRendezvous([])
        let m = wizard(r)
        m.chooseNew()
        let s = try #require(m.rendezvous)
        r.answers = [.success(nil), .success(try seal(link, to: s))]
        m.startWaiting()
        #expect(m.stage == .waiting)
        await settle(m) { m.stage == .found }
        #expect(m.stage == .found && m.link?.host == "core.example.com" && m.canConnect)
        #expect(r.asked.allSatisfy { $0 == s.id })
    }

    @Test func aMessageNotForThisSetupOrAUsedCodeSaysSoAndLeavesPaste() async throws {
        let r = FakeRendezvous([])
        let m = wizard(r)
        m.chooseNew()
        r.answers = [.success(try seal(link, to: RendezvousSession()))]
        m.startWaiting()
        await settle(m) { m.waitEnded != nil }
        #expect(m.stage == .waiting && m.waitEnded?.contains("not for this setup") == true)

        let used = wizard(FakeRendezvous([.failure(RendezvousError.used)]))
        used.chooseNew()
        used.startWaiting()
        await settle(used) { used.waitEnded != nil }
        #expect(used.waitEnded?.contains("used already") == true)
    }

    @Test func nothingArrivingEndsTheWaitAndPasteStillWorks() async {
        let m = wizard(FakeRendezvous([]))
        m.chooseNew()
        m.startWaiting()
        await settle(m) { m.waitEnded != nil }
        #expect(m.waitEnded?.hasPrefix("Nothing arrived") == true)
        m.haveLink()
        #expect(m.stage == .connect)
        m.back()
        #expect(m.stage == .install)
    }

    @Test func aCoreFromTheListOnlyTakesItsOwnLink() {
        let d = FakeDiscovery()
        let m = wizard(FakeRendezvous([]), d)
        m.chooseExisting()
        #expect(m.stage == .nearby)
        let mine = NearbyCore(name: "Home server", fingerprint: fp, host: "home.example.com")
        d.report?([mine])
        #expect(m.nearby == [mine])
        m.pick(mine)
        #expect(m.stage == .connect && m.picked == mine)
        m.linkText = link
        #expect(m.canConnect)
        m.linkText =
            "ainkrad://connect?host=other.example.com&fp=\(Wire.b64(Data(repeating: 3, count: 32)))&secret=\(secret)"
        #expect(m.pickedMismatch && !m.canConnect)
        m.back()
        #expect(m.stage == .nearby && m.picked == nil)
    }
}
