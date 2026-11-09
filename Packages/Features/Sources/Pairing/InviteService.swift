import CoreKit
import Foundation

/// A one-time invite for another device: the link (and its QR) it scans.
struct DeviceInvite: Equatable, Sendable {
    let name: String
    let scopes: [String]
    let link: ConnectLink
}

/// Creates a device invite on the Core (an admin call, gated by step-up). This is the seam for the owner invite API
/// (AinkradCore branch `feat/owner-invite-pairing`): until it lands, `UnavailableInviteService` is installed and the Add device
/// action keeps using the typed-code flow. When it lands, add a conformer that calls it and install it in `AppModel.openDesktop`.
protocol InviteService: Sendable {
    /// False when the Core cannot make an invite yet.
    var isAvailable: Bool { get }
    /// `scopes` are the ones the new device may hold, never more than the creator's own.
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite
}

/// Release default until the Core serves invites. Says so, plainly.
struct UnavailableInviteService: InviteService {
    var isAvailable: Bool { false }
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite {
        throw CoreError.invalidInput("This Core cannot make a device QR yet. Use a typed code instead.")
    }
}

#if DEBUG
/// Debug only: makes a well-formed link with a random secret the Core never heard of, so the screens can be shot and clicked
/// through. It cannot connect anything.
struct SampleInviteService: InviteService {
    let host: String
    let coreFingerprint: String
    var isAvailable: Bool { true }
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite {
        let secret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return DeviceInvite(
            name: name, scopes: scopes,
            link: try ConnectLink(host: host, coreFingerprint: coreFingerprint, secret: secret))
    }
}
#endif
