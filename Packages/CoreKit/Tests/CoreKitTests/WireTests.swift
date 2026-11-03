import Foundation
import Testing

@testable import CoreKit

@Suite struct WireTests {
    @Test func codesFoldAsTheSpecSays() {
        #expect(Wire.canonicalCode("ilo0O-abcde") == "11000ABCDE")
        #expect(Wire.canonicalCode("4DTTJ F9NW0") == "4DTTJF9NW0")
        #expect(Wire.canonicalCode(" 4dttj-f9nwo".trimmingCharacters(in: .whitespaces)) == "4DTTJF9NW0")
        for bad in ["", "ABCDE", "ABCDE-FGHJKX", "ABCDE-FGHJU", "ABCDE_FGHJK", "ÄBCDE-FGHJK"] {
            #expect(Wire.canonicalCode(bad) == nil, "\(bad)")
        }
    }

    @Test func base64urlIsStrict() {
        #expect(Wire.b64(Data([0xfb, 0xff])) == "-_8")
        #expect(Wire.unb64("-_8") == Data([0xfb, 0xff]))
        for bad in ["-_9", "-_8=", "a+b", "a/b", "a b", "é"] { #expect(Wire.unb64(bad) == nil, "\(bad)") }
    }

    @Test func spkiIsCheckedByExactPrefix() throws {
        let k = SoftwareKey(key: .init())
        #expect(k.spki.count == 91)
        #expect(Wire.publicKey(spki: k.spki) != nil)
        var bad = k.spki
        bad[10] ^= 1
        #expect(Wire.publicKey(spki: bad) == nil)
        #expect(Wire.publicKey(spki: k.spki.dropLast()) == nil)
        // A point that is not on the curve.
        var off = k.spki
        off[off.count - 1] ^= 1
        #expect(Wire.publicKey(spki: off) == nil)
    }

    @Test func timestampsParse() {
        #expect(Wire.parseTimestamp("1970-01-01T00:00:00.000Z") == 0)
        #expect(Wire.parseTimestamp("2025-10-29T09:26:40.250Z") == 1_761_730_000)
        #expect(Wire.parseTimestamp("2025-10-29T09:26:40Z") == 1_761_730_000)
        #expect(Wire.parseTimestamp("nope") == nil)
    }

    @Test func qrParsesStrictly() throws {
        let secret = Wire.b64(Data(repeating: 7, count: 16))
        let fp = Wire.b64(Data(repeating: 1, count: 32))
        let ok = "ainkrad-pair:v1?h=core.example&p=443&c=\(fp)&s=\(secret)&e=9"
        let qr = try #require(PairingQR.parse(ok))
        #expect(qr.host == "core.example" && qr.port == 443 && qr.coreFingerprint == fp && qr.expires == 9)
        #expect(!qr.description.contains(secret), "the description hides the secret")
        let bads = [
            ok.replacingOccurrences(of: "v1", with: "v2"), ok.replacingOccurrences(of: "&e=9", with: ""), ok + "&e=9",
            ok.replacingOccurrences(of: secret, with: "short"), ok.replacingOccurrences(of: "p=443", with: "p=x"),
            ok.replacingOccurrences(of: "p=443", with: "p=0"), ok.replacingOccurrences(of: "p=443", with: "p=70000"),
            ok + "&x=1", ok.replacingOccurrences(of: "h=core.example", with: "h="),
            ok.replacingOccurrences(of: "h=core.example", with: "h=a/b"),
            ok.replacingOccurrences(of: fp, with: "short"),
        ]
        for bad in bads { #expect(PairingQR.parse(bad) == nil, "\(bad)") }
        guard case .qr = try PairingCredential.parse(ok) else {
            Issue.record("not a qr")
            return
        }
        guard case .code("4DTTJF9NW0") = try PairingCredential.parse("4dttj-f9nwo") else {
            Issue.record("not a code")
            return
        }
        #expect(throws: CoreError.self) { try PairingCredential.parse("ainkrad-pair:v1?nope") }
        #expect(throws: CoreError.self) { try PairingCredential.parse("hello") }
    }

    @Test func endpointsAreValidated() throws {
        #expect(try CoreEndpoint(URL(string: "http://127.0.0.1:7700")!).host == "127.0.0.1:7700")
        #expect(try CoreEndpoint(URL(string: "https://core.example")!).host == "core.example")
        #expect(try CoreEndpoint(URL(string: "https://core.example:443/")!).host == "core.example")
        #expect(try CoreEndpoint(host: "core.example", port: 8443).host == "core.example:8443")
        // IPv6 loopback: one pair of brackets, lower case, default ports dropped.
        let v6 = try CoreEndpoint(URL(string: "http://[::1]:7700")!)
        #expect(v6.host == "[::1]:7700" && v6.url.absoluteString == "http://[::1]:7700")
        #expect(try CoreEndpoint(URL(string: "http://[::1]")!).host == "[::1]")
        #expect(try CoreEndpoint(URL(string: "HTTPS://CORE.Example:443")!).host == "core.example")
        #expect(try CoreEndpoint(URL(string: "http://LOCALHOST:80")!).host == "localhost")
        #expect(try CoreEndpoint(host: "[2001:db8::1]", port: 8443).host == "[2001:db8::1]:8443")
        #expect(try CoreEndpoint(host: "2001:db8::1", port: 8443).url.absoluteString == "https://[2001:db8::1]:8443")
        for bad in [
            "http://core.example", "http://[2001:db8::1]:7700", "ftp://x", "https://u@x", "https://x/api",
            "https://x?q=1", "https://x#f", "x",
        ] {
            #expect(throws: CoreError.self, "\(bad)") { try CoreEndpoint(URL(string: bad)!) }
        }
    }

    @Test func errorsMapPerSpec14() {
        func e(_ status: Int, _ code: String, _ extra: [String: Any] = [:], h: [String: String] = [:]) -> CoreError {
            CoreError.from(
                status: status, headers: h,
                body: jsonBody(["code": code, "message": "m", "error_id": "x"].merging(extra) { $1 }))
        }
        #expect(e(401, "auth_failed") == .authFailed)
        #expect(e(401, "clock_skew", ["server_time": 5]) == .clockSkew(serverTime: 5))
        #expect(e(401, "session_expired") == .sessionExpired)
        #expect(e(401, "pairing_failed") == .pairingFailed)
        #expect(e(403, "step_up_required") == .stepUpRequired)
        #expect(e(403, "forbidden_scope") == .forbiddenScope)
        #expect(e(429, "rate_limited", h: ["retry-after": "12"]) == .rateLimited(retryAfter: 12))
        #expect(e(409, "sas_mismatch") == .sasMismatch)
        #expect(e(409, "pairing_expired") == .pairingExpired)
        #expect(e(410, "past_retention", ["floor": 42]) == .pastRetention(floor: 42))
        #expect(e(400, "bad_request") == .badRequest(message: "m"))
        #expect(e(500, "internal") == .http(status: 500, code: "internal", message: "m"))
        #expect(
            CoreError.from(status: 502, headers: [:], body: Data("<html>".utf8))
                == .http(status: 502, code: "unknown", message: "HTTP 502"))
    }
}
