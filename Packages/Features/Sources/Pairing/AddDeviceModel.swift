import CoreKit
import Foundation
import Observation

/// Add device, as the approver: name it, choose what it may do, show the code, compare the check code, approve.
@MainActor @Observable
final class AddDeviceModel {
    enum Stage: Equatable {
        case form, creating
        case code(NewPairing)
        case claimed(PairingInfo)
        case approved(PairingInfo)
        /// `rejected`, `expired` or `burned`.
        case ended(String)
    }

    private(set) var stage: Stage = .form
    var name = ""
    var kind = "device"
    var scopes: Set<String> = ["read", "approve"]
    private(set) var mine: [String] = []
    private(set) var error: String?
    private(set) var busy = false
    private(set) var pairing: NewPairing?
    private weak var host: AppModel?
    private let existing: String?

    init(host: AppModel, existing: String? = nil) {
        self.host = host
        self.existing = existing
    }

    var pairingID: String? { pairing?.id ?? existing }
    /// A runner holds exactly `runner`.
    var effectiveScopes: [String] { kind == "runner" ? ["runner"] : ScopeText.all.filter(scopes.contains) }
    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !effectiveScopes.isEmpty && !busy
    }

    /// What the approver may hand out: their own scopes, no more.
    func prepare() async {
        guard let service = host?.service else { return }
        if let existing {
            do {
                let info = try await service.pairing(existing)
                pairing = NewPairing(id: existing, code: "", qr: nil, expiresAt: info.expiresAt)
                apply(info)
            } catch { fail(error) }
            return
        }
        do {
            try await loadMine(service)
        } catch { fail(error) }
    }

    /// What this Mac holds now: the Core's own record of this device, else what the session was granted. The Core refuses a
    /// pairing wider than its creator (403 `forbidden_scope`), so the form never offers more.
    private func loadMine(_ service: any CoreService) async throws {
        mine = try await service.myScopes()
        if let me = try? await service.devices().first(where: { $0.id == service.deviceID }) { mine = me.scopes }
        scopes = scopes.intersection(mine)
    }

    func create() async {
        guard let host, let service = host.service, canCreate else { return }
        error = nil
        busy = true
        stage = .creating
        defer { busy = false }
        let label = name.trimmingCharacters(in: .whitespaces)
        let (kind, granted) = (kind, effectiveScopes)
        do {
            let p = try await host.elevated("Make a pairing code for \(label).", done: "made") {
                try await service.createPairing(name: label, kind: kind, scopes: granted)
            }
            pairing = p
            stage = .code(p)
        } catch is StepUpDeclined {
            stage = .form
        } catch {
            stage = .form
            if CoreError.unwrapping(error) == .forbiddenScope {
                // Not a bare "not allowed": say what this Mac may hand on, and take back what it may not.
                try? await loadMine(service)
                let held = ScopeText.all.filter(mine.contains).joined(separator: ", ")
                self.error =
                    "This Mac can only hand on the scopes it holds (\(held.isEmpty ? "none" : held)). Unchecked what it does not hold."
            } else {
                fail(error)
            }
        }
    }

    func refresh() async {
        guard let id = pairingID, let service = host?.service else { return }
        switch stage {
        case .code, .claimed:
            if let info = try? await service.pairing(id) { apply(info) }
        default: break
        }
    }

    func refreshIfCurrent(_ id: String) async { if id == pairingID { await refresh() } }

    func approve() async {
        guard case .claimed(let info) = stage, let sas = info.sas, let host, let service = host.service else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let done = try await host.elevated("Approve \(info.name ?? "the new device").", done: "approved") {
                try await service.approve(info.id, sas: sas, scopes: nil)
            }
            apply(done)
            if case .approved = stage { host.shell.showToast("\(info.name ?? "The device") is now paired") }
        } catch is StepUpDeclined {
        } catch { fail(error) }
    }

    func reject() async {
        guard let id = pairingID, let host, let service = host.service else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await host.elevated("Reject the new device.", done: "rejected") { try await service.reject(id) }
            stage = .ended("rejected")
            host.shell.bell.remove("pairing-\(id)")
        } catch is StepUpDeclined {
        } catch { fail(error) }
    }

    private func apply(_ info: PairingInfo) {
        switch info.status {
        case "claimed": stage = .claimed(info)
        case "approved": stage = .approved(info)
        case "rejected", "expired", "burned": stage = .ended(info.status)
        default:
            if case .claimed = stage {} else if existing != nil { stage = .claimed(info) }
        }
    }

    private func fail(_ e: any Error) {
        error = CoreError.unwrapping(e)?.localizedDescription ?? e.localizedDescription
    }
}
