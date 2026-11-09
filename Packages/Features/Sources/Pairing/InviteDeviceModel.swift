import CoreKit
import Foundation
import Observation

/// Add device by QR, as the owner: name it, choose what it may do, show the QR. The new device scans it and connects directly,
/// so nothing is compared or approved afterwards. Making the QR needs Touch ID.
@MainActor @Observable
final class InviteDeviceModel {
    var name = "New device" { didSet { if name != oldValue { invite = nil } } }
    var scopes: Set<String> = ["read", "approve"] { didSet { if scopes != oldValue { invite = nil } } }
    private(set) var mine: [String] = []
    private(set) var invite: DeviceInvite?
    private(set) var busy = false
    private(set) var error: String?
    private weak var host: AppModel?

    init(host: AppModel) { self.host = host }

    var effectiveScopes: [String] { ScopeText.all.filter(scopes.contains) }
    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !effectiveScopes.isEmpty && !busy }

    /// The sheet opened: learn what this Mac may hand on, then make the QR at once with the defaults.
    func quick() async {
        if let service = host?.service, let held = try? await service.myScopes() {
            mine = held
            scopes = scopes.intersection(held)
        }
        guard !effectiveScopes.isEmpty else {
            error = "This Mac cannot hand on read or approve. Choose what the device may do."
            return
        }
        await create()
    }

    func create() async {
        guard let host, canCreate else { return }
        error = nil
        busy = true
        defer { busy = false }
        let label = name.trimmingCharacters(in: .whitespaces)
        let granted = effectiveScopes
        do {
            invite = try await host.elevated("Make a QR for \(label).", done: "made") {
                try await host.invites.createInvite(name: label, scopes: granted)
            }
        } catch is StepUpDeclined {
        } catch {
            invite = nil
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
    }
}
