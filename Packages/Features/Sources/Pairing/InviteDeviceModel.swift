import AppKit
import CoreKit
import Foundation
import Observation

/// Add device by QR, as the owner: name it, choose what it may do, show the QR. The new device scans it and connects directly,
/// so nothing is compared or approved afterwards. Making the QR needs Touch ID.
///
/// An invite never expires, and taking one back (`reject`) is an admin action that needs a fresh Touch ID once the 5 minute
/// window has passed. So nothing here withdraws silently and forgets: an invite stays tracked until the Core confirms it is
/// withdrawn, the replacement and the withdrawal of the old one share one elevation, and a QR that cannot be withdrawn is
/// said out loud (`stillLive`) or handed to the app (`abandonInvites`), which keeps a bell item until it is withdrawn.
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
    /// Invites made here, no longer on screen, not yet confirmed withdrawn: still live on the Core.
    private(set) var leftover: [String] = []
    /// Closing was tried and the QR is still live: the dialog stays and says so.
    private(set) var closeBlocked = false
    private weak var host: AppModel?
    private let pasteboard: any LinkPasteboard
    private let clearAfter: Duration
    private var copiedCount: Int?
    private var clearTask: Task<Void, Never>?
    private var quiet: [Task<Void, Never>] = []
    /// Bumped by anything that makes an in-flight `create()` obsolete: closing, editing the form.
    private var generation = 0
    private var closed = false
    private var closing = false

    init(
        host: AppModel, pasteboard: any LinkPasteboard = SystemLinkPasteboard(), clearAfter: Duration = .seconds(60)
    ) {
        self.host = host
        self.pasteboard = pasteboard
        self.clearAfter = clearAfter
        // A copied link must not outlive the app.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.takeBackLink() } }
    }

    var effectiveScopes: [String] { ScopeText.all.filter(scopes.contains) }
    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !effectiveScopes.isEmpty && !busy }
    /// A QR that is on screen and not spent.
    var live: Bool { invite?.pairingID != nil && !used && !ended }
    /// What to say loudly: a QR that is still live and that this dialog could not take back.
    var stillLive: Bool { !leftover.isEmpty || (closeBlocked && live) }
    private var currentID: String? { live ? invite?.pairingID : nil }

    /// The dialog opened: learn what this Mac may hand on. Nothing is created until the person asks for the QR.
    func prepare() async {
        if let service = host?.service, let held = try? await service.myScopes() {
            mine = held
            scopes = scopes.intersection(held)
        }
        if effectiveScopes.isEmpty { error = "This Mac cannot hand on read or approve. Choose what the device may do." }
    }

    /// The name or scopes changed: the shown QR is not what the form says any more. It stays tracked until withdrawn.
    private func reset() {
        generation += 1
        if let id = currentID { leftover.append(id) }
        invite = nil
        used = false
        ended = false
        takeBackLink()
        guard !leftover.isEmpty, let service = host?.invites else { return }
        // Quietly, with the elevation that is still running; if it has run out the ids stay tracked and `stillLive` says so.
        let ids = leftover
        quiet.append(
            Task { [weak self] in
                var gone: [String] = []
                for id in ids {
                    do {
                        try await service.withdraw(id)
                        gone.append(id)
                    } catch { if CoreError.unwrapping(error)?.inviteIsGone == true { gone.append(id) } }
                }
                self?.leftover.removeAll { gone.contains($0) }
            })
    }

    /// Withdraws `ids` inside an elevation; returns the ones still live (see `withdrawInvites`).
    private func withdrawAll(_ ids: [String], rethrowStepUp: Bool = true) async throws -> [String] {
        guard let service = host?.invites else { return ids }
        return try await withdrawInvites(ids, with: service, rethrowStepUp: rethrowStepUp)
    }

    func create() async {
        guard let host, canCreate else { return }
        generation += 1
        let token = generation
        error = nil
        busy = true
        // Closed while this ran: whatever is still live afterwards (the old QR when this failed) goes to the bell.
        defer {
            busy = false
            if closed { abandon() }
        }
        let label = name.trimmingCharacters(in: .whitespaces)
        let granted = effectiveScopes
        do {
            // The new invite and the withdrawal of the old ones share one Touch ID, the old ones only after the new exists.
            let reason = "Make a QR for \(label)."
            let (made, failed): (DeviceInvite?, [String]) = try await host.elevated(reason, done: "made") {
                guard generation == token else { return (nil, leftover + (currentID.map { [$0] } ?? [])) }
                let new = try await host.invites.createInvite(name: label, scopes: granted)
                var ids = leftover
                if let id = currentID { ids.append(id) }
                var keep: DeviceInvite? = new
                // Closed or edited while it was being made: nobody will see it, so it goes at once.
                if generation != token, let id = new.pairingID {
                    ids.append(id)
                    keep = nil
                }
                return (keep, try await withdrawAll(ids, rethrowStepUp: false))
            }
            leftover = failed
            if let made {
                invite = made
                used = false
                ended = false
            } else if currentID != nil {
                invite = nil
            }
        } catch is StepUpDeclined {
        } catch {
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Asks the Core whether the invite was claimed. A failed ask changes nothing: the next poll tries again.
    func refresh() async {
        guard let host, let id = invite?.pairingID, !used, !ended, !busy else { return }
        let status = try? await host.invites.status(id)
        // A slow answer about an invite that has since been replaced says nothing about the one on screen.
        guard invite?.pairingID == id, !busy, let status else { return }
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

    /// Takes the shown invite back, after Touch ID.
    func withdraw() async {
        guard let host, let id = currentID else { return }
        error = nil
        busy = true
        defer {
            busy = false
            if closed { abandon() }
        }
        do {
            let reason = "Withdraw the QR for \(invite?.name ?? "the device")."
            let left = try await host.elevated(reason, done: "withdrawn") {
                try await withdrawInvites([id], with: host.invites)
            }
            if left.isEmpty {
                // Gone is gone: withdrawn now, or a device used it first.
                let status = try? await host.invites.status(id)
                if status == "approved" || status == "claimed" { used = true } else { ended = true }
                takeBackLink()
            } else {
                error = "The Core could not be reached, so this QR is still live. Try again."
            }
        } catch is StepUpDeclined {
        } catch {
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
    }

    // MARK: closing

    /// Done or the close button. True when the dialog may close: nothing is live any more. Otherwise it stays, with the
    /// reason (`stillLive`, or `error` when the Core could not be reached).
    func requestClose() async -> Bool {
        if closing { return false }
        // A create or withdraw in flight handles the rest itself (see their `defer`).
        if busy {
            didClose()
            return true
        }
        let ids = leftover + (currentID.map { [$0] } ?? [])
        guard !ids.isEmpty, let host else {
            didClose()
            return true
        }
        closing = true
        busy = true
        defer {
            closing = false
            busy = false
            if closed { abandon() }
        }
        do {
            let reason = "Withdraw the QR for \(invite?.name ?? "the device")."
            let failed = try await host.elevated(reason, done: "withdrawn") {
                try await withdrawInvites(ids, with: host.invites)
            }
            if let id = currentID, !failed.contains(id) { ended = true }
            if failed.isEmpty {
                leftover = []
                invite = nil
                closeBlocked = false
                takeBackLink()
                didClose()
                return true
            }
            keep(failed)
            error = "The Core could not be reached, so this QR is still live. Try again."
        } catch is StepUpDeclined {
            keep(ids)
        } catch {
            keep(ids)
            self.error = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
        }
        closeBlocked = true
        return false
    }

    /// Keeps `ids` tracked: those that are the shown invite stay shown, the rest are leftovers.
    private func keep(_ ids: [String]) {
        leftover = ids.filter { $0 != invite?.pairingID }
    }

    /// "Close anyway", and the dialog going away by any other way (Esc): what is still live is handed to the app, which says so
    /// in the bell until it is withdrawn.
    func abandon() {
        let ids = leftover + (currentID.map { [$0] } ?? [])
        if !ids.isEmpty { host?.abandonInvites(ids) }
        leftover = []
        invite = nil
        didClose()
    }

    /// The dialog is gone. If it went without `requestClose` succeeding, nothing may be forgotten.
    func dialogDidClose() {
        if !closed { abandon() }
    }

    private func didClose() {
        closed = true
        generation += 1
        takeBackLink()
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

    /// For tests: waits for the quiet withdrawals.
    func settle() async { for t in quiet { await t.value } }
}
