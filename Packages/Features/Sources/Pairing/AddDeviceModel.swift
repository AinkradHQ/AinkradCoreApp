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
    /// What the approver typed from the new device's screen, as `XXXX-XXXX-XXXX-XXXX`: approving needs all four groups to match.
    var typed = "" { didSet { if typed != Self.format(typed) { typed = Self.format(typed) } } }
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

    /// Upper case letters and digits, four to a group, at most four groups.
    static func format(_ text: String) -> String {
        let chars = text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(16)
        return stride(from: 0, to: chars.count, by: 4).map { i in
            String(chars.dropFirst(i).prefix(4))
        }.joined(separator: "-")
    }

    /// The check code the Core gave for the claimed device, if any.
    var checkCode: String? { if case .claimed(let i) = stage { i.sas } else { nil } }

    /// How many groups from the start of what was typed equal the real check code.
    var groupsMatching: Int {
        guard let sas = checkCode else { return 0 }
        let real = sas.uppercased().split(separator: "-")
        let mine = typed.split(separator: "-")
        var n = 0
        for (a, b) in zip(real, mine) {
            guard a == b else { break }
            n += 1
        }
        return n
    }
    var groupCount: Int { max(checkCode?.split(separator: "-").count ?? 4, 1) }
    var checkMatches: Bool { checkCode != nil && groupsMatching == groupCount }
    /// A full group that is wrong (typing the next one is not a mismatch yet).
    var checkMismatch: Bool {
        guard let sas = checkCode else { return false }
        let real = sas.uppercased().split(separator: "-")
        let mine = typed.split(separator: "-")
        return zip(real, mine).contains { $0 != $1 && $1.count == 4 }
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

    /// After a pairing ended: back to the form (same name and scopes) for a new code.
    func restart() {
        pairing = nil
        error = nil
        typed = ""
        stage = .form
    }

    func refreshIfCurrent(_ id: String) async { if id == pairingID { await refresh() } }

    func approve() async {
        guard case .claimed(let info) = stage, let sas = info.sas, checkMatches, let host, let service = host.service
        else { return }
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
