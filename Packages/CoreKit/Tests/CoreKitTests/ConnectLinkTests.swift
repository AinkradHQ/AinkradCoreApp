import Foundation
import Testing

@testable import CoreKit

private let fp = Wire.b64(Data(repeating: 7, count: 32))
private let secret = Wire.b64(Data(repeating: 9, count: 16))
private func link(_ q: String) -> String { "ainkrad://connect?\(q)" }

@Suite struct ConnectLinkTests {
    @Test func parsesAValidLinkAndDefaultsToHTTPSPort() throws {
        let l = try ConnectLink.parse(link("host=core.example.com&fp=\(fp)&secret=\(secret)"))
        #expect(l.host == "core.example.com" && l.port == 443 && l.coreFingerprint == fp)
        #expect(l.address == "core.example.com")
        let p = try ConnectLink.parse(link("host=10.0.0.5:7700&fp=\(fp)&secret=\(secret)"))
        #expect(p.host == "10.0.0.5" && p.port == 7700 && p.address == "10.0.0.5:7700")
    }

    @Test func roundTripsThroughItsText() throws {
        let l = try ConnectLink(
            host: "core.example.com", port: 8443, coreFingerprint: fp, secret: Data(repeating: 9, count: 16))
        #expect(try ConnectLink.parse(l.text) == l)
    }

    @Test func aMissingFieldIsNamed() {
        #expect(throws: ConnectLinkError.missing("secret")) { try ConnectLink.parse(link("host=a.b&fp=\(fp)")) }
        #expect(throws: ConnectLinkError.missing("fp")) { try ConnectLink.parse(link("host=a.b&secret=\(secret)")) }
        #expect(throws: ConnectLinkError.missing("host")) { try ConnectLink.parse(link("fp=\(fp)&secret=\(secret)")) }
        #expect(throws: ConnectLinkError.missing("secret")) { try ConnectLink.parse(link("host=a.b&fp=\(fp)&secret=")) }
    }

    @Test func aWrongSchemeOrNonLinkIsRefused() {
        #expect(throws: ConnectLinkError.wrongScheme) {
            try ConnectLink.parse("https://connect?host=a.b&fp=\(fp)&secret=\(secret)")
        }
        #expect(throws: ConnectLinkError.wrongScheme) { try ConnectLink.parse("ainkrad://pair?host=a.b") }
        #expect(throws: ConnectLinkError.notALink) { try ConnectLink.parse("hello there") }
    }

    @Test func damagedFieldsAndRepeatsAreRefused() {
        #expect(throws: ConnectLinkError.badFingerprint) {
            try ConnectLink.parse(link("host=a.b&fp=short&secret=\(secret)"))
        }
        #expect(throws: ConnectLinkError.badSecret) { try ConnectLink.parse(link("host=a.b&fp=\(fp)&secret=abc")) }
        #expect(throws: ConnectLinkError.badHost) {
            try ConnectLink.parse(link("host=a.b:x&fp=\(fp)&secret=\(secret)"))
        }
        #expect(throws: ConnectLinkError.duplicate("host")) {
            try ConnectLink.parse(link("host=a.b&host=c.d&fp=\(fp)&secret=\(secret)"))
        }
    }

    @Test func findsTheLinkInPastedInstallerOutput() {
        let out = "Core is ready.\n  Link:  ainkrad://connect?host=a.b&fp=\(fp)&secret=\(secret)\nKeep it safe.\n"
        #expect(ConnectLink.find(in: out)?.hasPrefix("ainkrad://connect?host=a.b") == true)
        #expect(ConnectLink.find(in: "nothing here") == nil)
    }

    @Test func neverPrintsTheSecret() throws {
        let l = try ConnectLink.parse(link("host=a.b&fp=\(fp)&secret=\(secret)"))
        #expect(!"\(l)".contains(secret) && !String(reflecting: l).contains(secret))
        var dumped = ""
        dump(l, to: &dumped)
        #expect(!dumped.contains(secret))
    }

    // The claim itself is DevicePairing's: a link's fingerprint is what the Core must prove before anything is sent.
    @Test func aLinkWhoseFingerprintIsNotTheCoresClaimsNothing() async throws {
        let core = FakeCore(clock: TestClock(unix: 1000), host: "core.example:8443")
        let store = makeMemoryKeyStore()
        let wrong = Wire.b64(Data(repeating: 1, count: 32))
        let l = try ConnectLink.parse(link("host=core.example:8443&fp=\(wrong)&secret=\(secret)"))
        let p = DevicePairing(keyStore: store, clock: core.clock) { _ in core }
        do {
            _ = try await p.claim(l.credential)
            Issue.record("paired")
        } catch {
            if case CoreError.coreIdentityMismatch = error {} else { Issue.record("\(error)") }
        }
        #expect(core.requests(to: "/pair/claim").isEmpty)
        #expect(try store.loadIdentity() == nil)
    }

    @Test func aLinkWithTheRightFingerprintClaimsWithItsSecretAndNeverExpires() async throws {
        let core = FakeCore(clock: TestClock(unix: 1000), host: "core.example:8443")
        let l = try ConnectLink.parse(link("host=core.example:8443&fp=\(core.coreFP)&secret=\(secret)"))
        let store = makeMemoryKeyStore()
        let p = DevicePairing(keyStore: store, clock: TestClock(unix: 4_000_000_000)) { _ in core }
        let claim = try await p.claim(l.credential)
        #expect(claim.coreFingerprint == core.coreFP)
        let body = try #require(
            try JSONSerialization.jsonObject(with: core.requests(to: "/pair/claim").first!.body) as? [String: String])
        #expect(body["secret"] == secret && body["code"] == nil)
        // The Core pinned by the link: no SAS to confirm, so approval ends in `.paired`.
        #expect(try #require(try store.loadPending()).sasConfirmed)
    }

    @Test func bracketedIPv6HostsParseWithAndWithoutAPort() throws {
        let a = try ConnectLink.parse(link("host=[::1]&fp=\(fp)&secret=\(secret)"))
        #expect(a.host == "[::1]" && a.port == 443 && a.address == "[::1]")
        let b = try ConnectLink.parse(link("host=[fd00::5]:7700&fp=\(fp)&secret=\(secret)"))
        #expect(b.host == "[fd00::5]" && b.port == 7700 && b.address == "[fd00::5]:7700")
        #expect(try ConnectLink.parse(b.text) == b)
        #expect(b.qr.host == "[fd00::5]", "still the HTTPS-only pairing credential with the same pin")
        #expect(throws: ConnectLinkError.badHost) {
            try ConnectLink.parse(link("host=[nope]&fp=\(fp)&secret=\(secret)"))
        }
        #expect(throws: ConnectLinkError.badHost) { try ConnectLink.parse(link("host=[::1&fp=\(fp)&secret=\(secret)")) }
    }

    @Test func nonASCIIHostsAreRefused() {
        // Cyrillic "а" in place of Latin "a", raw and percent-encoded.
        for host in ["c\u{0430}re.example.com", "c%D0%B0re.example.com"] {
            do {
                _ = try ConnectLink.parse(link("host=\(host)&fp=\(fp)&secret=\(secret)"))
                Issue.record("accepted \(host)")
            } catch {
                let e = error as? ConnectLinkError
                #expect(e == .nonASCIIHost || e == .notALink, "\(host): \(error)")
            }
        }
        #expect(throws: ConnectLinkError.nonASCIIHost) {
            try ConnectLink(host: "c\u{0430}re.example.com", coreFingerprint: fp, secret: Data(repeating: 9, count: 16))
        }
        // The punycode form is plain ASCII and is shown as it is.
        #expect(throws: Never.self) {
            try ConnectLink.parse(link("host=xn--cre-6ve.example.com&fp=\(fp)&secret=\(secret)"))
        }
    }
}
