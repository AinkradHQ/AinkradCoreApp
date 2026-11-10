import CoreKit
import Foundation
import Observation

/// Add device by QR, as the owner: name it, choose what it may do, show the QR. The new device scans it and connects directly,
/// so nothing is compared or approved afterwards. Making the QR needs Touch ID.
///
/// An invite never expires, so one that is no longer shown is withdrawn: when it is replaced, when the name or scopes change,
/// and when the dialog closes (best effort: it never blocks, and it says nothing about the secret).
@MainActor @Observable
final class InviteDeviceModel {
    var name = "New device" { didSet { if name != oldValue { reset() } } }
    var scopes: Set<String> = ["read", "approve"] { didSet { if scopes != oldValue { reset() } } }
    private(set) var mine: [String] = []
    private(set) var invite: DeviceInvite?
    private(set) var busy = false
    private(set) var error: String?
    /// The Core says a device claimed the invite: the QR is spent.
    private(set) var used = false
    /// The invite was taken back (or the Core ended it), so the QR no longer works.
    private(set) var ended = false
    private(set) var copied = false
    private weak var host: AppModel?
    private let pasteboard: any LinkPasteboard
    private let clearAfter: Duration
    private var copiedCount: Int?
    private var clearTask: Task<Void, Never>?
    private var discards: [Task<Void, Never>] = []

    init(
        host: AppModel, pasteboard: any LinkPasteboard = SystemLinkPasteboard(), clearAfter: Duration = .seconds(60)
    ) {
        self.host = host
        self.pasteboard = pasteboard
        self.clearAfter = clearAfter
    }

    var effectiveScopes: [String] { ScopeText.all.filter(scopes.contains) }
    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !effectiveScopes.isEmpty && !busy }
    /// A QR that is on screen and not spent.
    var live: Bool { invite?.pairingID != nil && !used && !ended }

    /// The dialog opened: learn what this Mac may hand on. Nothing is created until the person asks for the QR.
    func prepare() async {
        if let service = host?.service, let held = try? await service.myScopes() {
            mine = held
            scopes = scopes.intersection(held)
        }
        if effectiveScopes.isEmpty { error = "This Mac cannot hand on read or approve. Choose what the device may do." }
    }

    private func reset() {
        discard()
        invite = nil
        used = false
        ended = false
    }

    /// Withdraws the invite that is on screen, without waiting and without asking for Touch ID: the window that made it is
    /// usually still open, and when it is not the Core's refusal is ignored.
    private func discard() {
        takeBackLink()
        guard let id = invite?.pairingID, !used, !ended, let service = host?.invites else { return }
        discards.append(Task { try? await service.withdraw(id) })
    }

    /// The dialog is closing (Done, the close button, Esc).
    func closed() {
        discard()
        invite = nil
    }

    func create() async {
        guard let host, canCreate else { return }
        discard()
        error = nil
        used = false
        ended = false
        busy = true
        defer { busy = false }
        let label = name.trimmingCharacters(in: .whitespaces)
        let granted = effectiveScopes
        do {
            invite = try await host.elevated("Make a QR for \(label).", done: "made") {
                try await host.invites.createInvite(name: label, scopes: granted)
            }
        } catch is StepUpDeclined {
            invite = nil
        } catch {
            invite = nil
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Asks the Core whether the invite was claimed. A failed ask changes nothing: the next poll tries again.
    func refresh() async {
        guard let host, let id = invite?.pairingID, !used, !ended,
            let status = try? await host.invites.status(id)
        else { return }
        switch status {
        case "approved", "claimed":
            used = true
            takeBackLink()
        case "rejected", "expired", "burned":
            ended = true
            takeBackLink()
        default: break
        }
    }

    /// Takes an unused invite back, after Touch ID.
    func withdraw() async {
        guard let host, let id = invite?.pairingID, !used else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await host.elevated("Withdraw the QR for \(invite?.name ?? "the device").", done: "withdrawn") {
                try await host.invites.withdraw(id)
            }
            ended = true
            takeBackLink()
        } catch is StepUpDeclined {
        } catch {
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
    }

    // MARK: the copied link

    func copyLink() {
        guard let invite else { return }
        copiedCount = pasteboard.write(secret: invite.link.text)
        copied = true
        clearTask?.cancel()
        let wait = clearAfter
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            if !Task.isCancelled { self?.takeBackLink() }
        }
    }

    /// Clears the pasteboard if it still holds what this dialog put there: never something the person copied since.
    func takeBackLink() {
        clearTask?.cancel()
        clearTask = nil
        copied = false
        guard let count = copiedCount else { return }
        copiedCount = nil
        if pasteboard.changeCount == count { pasteboard.clear() }
    }

    /// For tests: waits for the withdrawals that were started without waiting.
    func settle() async { for t in discards { await t.value } }
}
