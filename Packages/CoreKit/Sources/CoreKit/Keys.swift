import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// `key_storage` as the pairing claim reports it (§3). A claim: the Core stores and shows it labelled "claimed".
public enum KeyStorage: String, Sendable, Equatable {
    case secureEnclave = "secure_enclave"
    case software
}

public enum KeyRole: String, Sendable, Equatable {
    /// Signs every request, the session challenge and the pairing proof of possession.
    case routine
    /// Signs step-up only (§8); the OS releases it after Touch ID or the passcode.
    case stepup
}

/// A P-256 signing key, wherever it lives. The private half never leaves the Secure Enclave or the Keychain.
public protocol DeviceKey: Sendable {
    var storage: KeyStorage { get }
    /// The 91-byte SPKI (§3).
    var spki: Data { get }
    /// ES256 in message mode: raw r‖s, 64 bytes, never DER. A `stepup` key blocks here while the OS asks the user.
    func sign(_ message: Data) throws -> Data
}

extension DeviceKey {
    public var fingerprint: String { Wire.fingerprint(spki: spki) }
}

struct SoftwareKey: DeviceKey {
    let key: P256.Signing.PrivateKey
    var storage: KeyStorage { .software }
    var spki: Data { key.publicKey.derRepresentation }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).rawRepresentation }
}

struct SecureEnclaveKey: DeviceKey {
    let blob: Data
    let spki: Data
    /// Shown by the OS prompt when the key's access control asks for the user (the `stepup` key).
    let reason: String?
    var storage: KeyStorage { .secureEnclave }
    func sign(_ message: Data) throws -> Data {
        let context = LAContext()
        if let reason { context.localizedReason = reason }
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
        return try key.signature(for: message).rawRepresentation
    }
}

/// What pairing pins, and where the Core is. Not secret, but its integrity matters (the pin), so it lives beside the keys.
public struct PairedIdentity: Codable, Sendable, Equatable {
    public var deviceID: String
    /// `core_fp`: the fingerprint of the Core identity key (§13).
    public var coreFingerprint: String
    public var endpoint: URL
    public init(deviceID: String, coreFingerprint: String, endpoint: URL) {
        self.deviceID = deviceID
        self.coreFingerprint = coreFingerprint
        self.endpoint = endpoint
    }
}

/// A pairing in flight: claimed, not yet approved. Kept apart from `PairedIdentity` so nothing is pinned until the device is
/// active and the SAS was confirmed; a relaunched app resumes from it. The keys stay in their own slots.
public struct PendingPairing: Codable, Sendable, Equatable {
    public var identity: PairedIdentity
    public var pairingID: String
    public var sas: String
    /// The Core key is trusted: from the QR's fingerprint, or because the user confirmed the SAS matches the approver's.
    public var sasConfirmed: Bool
    /// The Core said `active`: the approver holds this device as approved, so giving up must revoke it there.
    public var approved: Bool = false
}

public protocol KeyStore: Sendable {
    /// The stored key, or nil when none was made. `reason` is the OS prompt text for a key that needs the user.
    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)?
    /// Makes a new key and replaces any old one. Nil for `stepup` where the device has no way to verify the user.
    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)?
    func deleteKey(_ role: KeyRole) throws
    func loadIdentity() throws -> PairedIdentity?
    func saveIdentity(_ identity: PairedIdentity) throws
    func loadPending() throws -> PendingPairing?
    func savePending(_ pending: PendingPairing) throws
    func clearPending() throws
    /// Removes both keys, the identity and any pending pairing; keeps going past a failure and reports the first.
    func wipe() throws
}

/// Where opaque secret blobs live: the Keychain in the app, a dictionary in tests.
protocol BlobStore: Sendable {
    func read(_ name: String) throws -> Data?
    func write(_ name: String, _ data: Data) throws
    func remove(_ name: String) throws
}

/// The key logic over a blob store. Tag byte 1 = a Secure Enclave key's `dataRepresentation`, 2 = a software key's raw scalar.
struct BlobKeyStore: KeyStore {
    let blobs: BlobStore
    /// Secure Enclave keys where the hardware is there. Otherwise software, reported as `software` (§3).
    let useSecureEnclave: Bool

    private func name(_ role: KeyRole) -> String { role.rawValue }

    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)? {
        guard let blob = try blobs.read(name(role)), let tag = blob.first else { return nil }
        let body = blob.dropFirst()
        do {
            switch tag {
            case 1:
                let probe = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: Data(body))
                return SecureEnclaveKey(
                    blob: Data(body), spki: probe.publicKey.derRepresentation,
                    reason: role == .stepup ? reason : nil)
            case 2:
                return SoftwareKey(key: try P256.Signing.PrivateKey(rawRepresentation: body))
            default:
                throw CoreError.keyStore("a stored key of an unknown kind")
            }
        } catch let e as CoreError {
            throw e
        } catch {
            throw CoreError.keyStore("the stored \(role.rawValue) key cannot be opened")
        }
    }

    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)? {
        if useSecureEnclave {
            do {
                var cfError: Unmanaged<CFError>?
                let flags: SecAccessControlCreateFlags =
                    role == .stepup ? [.privateKeyUsage, .userPresence] : [.privateKeyUsage]
                let protection =
                    role == .stepup
                    ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard let access = SecAccessControlCreateWithFlags(nil, protection, flags, &cfError) else {
                    throw CoreError.keyStore("the access control for the \(role.rawValue) key was refused")
                }
                let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
                try blobs.write(name(role), Data([1]) + key.dataRepresentation)
                return SecureEnclaveKey(
                    blob: key.dataRepresentation, spki: key.publicKey.derRepresentation,
                    reason: role == .stepup ? "Confirm it is you" : nil)
            } catch let e as CoreError {
                throw e
            } catch {
                throw CoreError.keyStore("the Secure Enclave refused a new \(role.rawValue) key")
            }
        }
        // No Secure Enclave: a routine key in software. A step-up key without user verification would prove nothing
        // beyond the routine key, so there is none: the device can never elevate (like `ainkradctl --no-stepup`).
        guard role == .routine else {
            try blobs.remove(name(role))
            return nil
        }
        let key = P256.Signing.PrivateKey()
        try blobs.write(name(role), Data([2]) + key.rawRepresentation)
        return SoftwareKey(key: key)
    }

    func deleteKey(_ role: KeyRole) throws { try blobs.remove(name(role)) }

    func loadIdentity() throws -> PairedIdentity? {
        guard let data = try blobs.read("identity") else { return nil }
        guard let id = try? JSONDecoder().decode(PairedIdentity.self, from: data) else {
            throw CoreError.keyStore("the stored identity is unreadable")
        }
        return id
    }

    func saveIdentity(_ identity: PairedIdentity) throws {
        try blobs.write("identity", try JSONEncoder().encode(identity))
    }

    func loadPending() throws -> PendingPairing? {
        guard let data = try blobs.read("pending") else { return nil }
        guard let p = try? JSONDecoder().decode(PendingPairing.self, from: data) else {
            throw CoreError.keyStore("the pending pairing is unreadable")
        }
        return p
    }

    func savePending(_ pending: PendingPairing) throws {
        try blobs.write("pending", try JSONEncoder().encode(pending))
    }

    func clearPending() throws { try blobs.remove("pending") }

    func wipe() throws {
        var first: (any Error)?
        for n in ["routine", "stepup", "identity", "pending"] {
            do { try blobs.remove(n) } catch { first = first ?? error }
        }
        if let first { throw first }
    }
}

/// Keys and identity in memory only: tests, and the software path of the live integration test.
public func makeMemoryKeyStore() -> any KeyStore {
    BlobKeyStore(blobs: MemoryBlobs(), useSecureEnclave: false)
}

// @unchecked Sendable: every access to `items` is under `lock`.
final class MemoryBlobs: BlobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func read(_ name: String) throws -> Data? { lock.withLock { items[name] } }
    func write(_ name: String, _ data: Data) throws { lock.withLock { items[name] = data } }
    func remove(_ name: String) throws { lock.withLock { _ = items.removeValue(forKey: name) } }
}

/// Generic-password items in the Keychain. The routine key is a Secure Enclave key where one exists (its blob is useless
/// off this device) and otherwise a software key; both are `AfterFirstUnlockThisDeviceOnly` so a background refresh works.
public func makeKeychainKeyStore(
    service: String = "com.ainkrad.core.corekit", namespace: String = "default",
    useSecureEnclave: Bool = SecureEnclave.isAvailable, dataProtectionKeychain: Bool = defaultDataProtection
) -> any KeyStore {
    BlobKeyStore(
        blobs: KeychainBlobs(service: service, namespace: namespace, dataProtection: dataProtectionKeychain),
        useSecureEnclave: useSecureEnclave)
}

#if os(iOS)
public let defaultDataProtection = true
#else
// ponytail: the macOS data-protection keychain needs a provisioned keychain-access-groups entitlement; the app is not
// provisioned yet, so it uses the login keychain, which ignores kSecAttrAccessible. Flip once the app has the entitlement.
public let defaultDataProtection = false
#endif

struct KeychainBlobs: BlobStore {
    let service: String
    let namespace: String
    let dataProtection: Bool

    private func query(_ name: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(namespace).\(name)",
            kSecAttrSynchronizable as String: false,
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    func read(_ name: String) throws -> Data? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw Self.fail("read", status) }
        return data
    }

    /// Update in place, add when there is nothing yet: a failure never leaves the old secret deleted.
    func write(_ name: String, _ data: Data) throws {
        let updated = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Self.fail("write", updated) }
        var q = query(name)
        q[kSecValueData as String] = data
        if dataProtection { q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.fail("write", status) }
    }

    func remove(_ name: String) throws {
        let status = SecItemDelete(query(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.fail("delete", status) }
    }

    private static func fail(_ what: String, _ status: OSStatus) -> CoreError {
        CoreError.keyStore("the Keychain refused to \(what) (OSStatus \(status))")
    }
}
