import CryptoKit
import Foundation
import Testing

@testable import Leyline

@Suite("Leyline keys panel")
struct KeyTextTests {
    @Test func aNewKeyGetsTheFirstFreeName() {
        #expect(KeyText.uniqueName([]) == "key-1")
        #expect(KeyText.uniqueName(["key-1", "key-2", "deploy"]) == "key-3")
        #expect(KeyText.uniqueName(["key-2"]) == "key-1")
        #expect(KeyText.uniqueName(["Key-1"]) == "key-2")
    }

    @Test func anImportedKeyIsNamedAfterItsFile() {
        #expect(KeyText.name(fromFile: "id_ed25519", taken: []) == "id_ed25519")
        #expect(KeyText.name(fromFile: "deploy.pem", taken: []) == "deploy")
        #expect(KeyText.name(fromFile: "deploy.pem", taken: ["deploy"]) == "deploy-2")
        #expect(KeyText.name(fromFile: "my key.pem", taken: []) == "my-key")
        #expect(KeyText.name(fromFile: ".hidden", taken: []) == "key")
    }

    @Test func anOpenSSHKeySaysItsTypeLockAndFingerprint() {
        let pub = Data(repeating: 9, count: 32)
        let blob = Self.field(Data("ssh-ed25519".utf8)) + Self.field(pub)
        let fp = "SHA256:" + Data(SHA256Probe.hash(blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        #expect(
            KeyText.detect(KeyText.sample(publicFields: [pub]))
                == .privateKey(type: "ed25519", encrypted: false, fingerprint: fp))
        #expect(
            KeyText.detect(KeyText.sample(cipher: "aes256-ctr", publicFields: [pub]))
                == .privateKey(type: "ed25519", encrypted: true, fingerprint: fp))
        // RSA: the size comes from the modulus (a leading zero byte does not count).
        let rsa = [Data([1, 0, 1]), Data([0]) + Data(repeating: 0xC0, count: 512)]
        guard case .privateKey(let type, _, _) = KeyText.detect(KeyText.sample(type: "ssh-rsa", publicFields: rsa))
        else {
            Issue.record("not read as a key")
            return
        }
        #expect(type == "RSA 4096")
    }

    @Test func pemAndOtherTextsAreToldApart() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----"
        #expect(KeyText.detect(pem) == .privateKey(type: "RSA", encrypted: false, fingerprint: nil))
        let locked =
            "-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,00\n\nMIIE\n-----END RSA PRIVATE KEY-----"
        #expect(KeyText.detect(locked) == .privateKey(type: "RSA", encrypted: true, fingerprint: nil))
        #expect(
            KeyText.detect("-----BEGIN ENCRYPTED PRIVATE KEY-----\nMII\n-----END ENCRYPTED PRIVATE KEY-----")
                == .privateKey(type: nil, encrypted: true, fingerprint: nil))
        #expect(KeyText.detect("ssh-ed25519 AAAAC3Nza ops@mac") == .publicKey)
        #expect(KeyText.detect("hello") == .notAKey)
        // An OpenSSH header over a body that does not read still counts: the Core has the last word.
        #expect(
            KeyText.detect("-----BEGIN OPENSSH PRIVATE KEY-----\nx\n-----END OPENSSH PRIVATE KEY-----")
                == .privateKey(type: nil, encrypted: false, fingerprint: nil))
    }

    @Test func aRowShowsThreeHostChipsAndTheRest() {
        #expect(KeyText.chips([1, 2]).shown == [1, 2])
        #expect(KeyText.chips([1, 2]).more == 0)
        #expect(KeyText.chips([1, 2, 3, 4, 5]).shown == [1, 2, 3])
        #expect(KeyText.chips([1, 2, 3, 4, 5]).more == 2)
        #expect(KeyText.chips([Int]()).more == 0)
    }

    @Test func aDroppedFileFillsTheDraftAndKeepsATypedName() {
        var d = KeyDraft()
        d.pasting = true
        d.load(file: "deploy.pem", text: "x", taken: ["deploy"])
        #expect(d.name == "deploy-2")
        #expect(!d.pasting)
        d.load(file: "other.pem", text: "y", taken: [])
        #expect(d.name == "deploy-2")
        #expect(d.file == "other.pem")
    }

    private static func field(_ d: Data) -> Data {
        var n = UInt32(d.count).bigEndian
        return Data(bytes: &n, count: 4) + d
    }
}

private enum SHA256Probe {
    static func hash(_ d: Data) -> [UInt8] { Array(SHA256.hash(data: d)) }
}
