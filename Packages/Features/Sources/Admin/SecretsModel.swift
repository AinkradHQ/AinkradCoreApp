import CoreKit
import Foundation
import Observation

/// The form behind New secret and Replace value. The value is typed here and goes to the Core; it is cleared as soon as the
/// request has been made (and when the dialog closes), and no other type in the app can hold it.
@MainActor @Observable
final class SecretForm {
    /// nil: replacing the value of an existing secret.
    let existing: SecretItem?
    var name = ""
    private(set) var value = ""
    var delivery = "env"
    var runners: Set<String> = []
    /// The new-secret wizard: 0 type, 1 value, 2 details.
    var step = 0
    /// Only text is stored by the Core today (`SecretWords.Kind`).
    var kind = SecretWords.Kind.text
    private(set) var issue: FieldIssue?
    private(set) var busy = false

    init(existing: SecretItem? = nil) { self.existing = existing }

    /// The only way a value gets in.
    func setValue(_ v: String) { value = v }
    func wipe() { value = "" }

    /// `[a-z][a-z0-9_.-]{0,63}`, the Core's rule for a name.
    static func validName(_ n: String) -> Bool {
        guard n.count <= 64, let first = n.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return n.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || "_.-".unicodeScalars.contains($0)
        }
    }

    func check() -> FieldIssue? {
        if existing == nil, !Self.validName(name) {
            return FieldIssue(
                code: "bad_request",
                message:
                    "A name starts with a lower case letter, then letters, digits, dots, dashes or underscores (up to 64)."
            )
        }
        if value.isEmpty { return FieldIssue(code: "bad_request", message: "A value is required.") }
        return nil
    }

    fileprivate func fail(_ i: FieldIssue?) { issue = i }
    fileprivate func working(_ b: Bool) { busy = b }
}

/// The lease sheet: which runner, how long, and the person's word that an agent there can read the value.
@MainActor @Observable
final class LeaseForm {
    let secret: SecretItem
    var runner: String
    var ttl = ""
    var understood = false
    fileprivate(set) var issue: FieldIssue?
    fileprivate(set) var busy = false
    init(secret: SecretItem) {
        self.secret = secret
        runner = secret.runners.first ?? ""
    }
}

/// Settings, Security, Secrets: names and metadata only, plus the leases this Mac granted. Set, replace, lease and delete go
/// through Touch ID. A value is never read back, shown, copied or logged.
@MainActor @Observable
final class SecretsModel {
    private(set) var items: [SecretItem] = []
    var state: SectionState = .loading
    private(set) var leases: [LeaseItem] = []
    private(set) var runners: [RunnerChoice] = []
    private(set) var rowError: [String: String] = [:]
    @ObservationIgnored private weak var hub: AdminModel?

    init(hub: AdminModel) { self.hub = hub }

    var mode: Int { hub?.registry.secretsMode ?? 0 }
    var leaseLimit: Int64 { hub?.registry.item("secrets.lease_secs")?.value ?? 120 }

    func reset() {
        items = []
        leases = []
        state = .loading
    }

    func reload() async {
        guard let hub, let service = hub.service else { return }
        if items.isEmpty { state = .loading }
        do {
            items = try await service.secrets().sorted { $0.name < $1.name }
            state = items.isEmpty ? .empty : .ready
        } catch { state = hub.state(for: error) }
        runners = (try? await service.runners()) ?? runners
    }

    /// Stores a new secret. True when the Core took it.
    func store(_ form: SecretForm) async -> Bool {
        guard let hub, let service = hub.service, hub.mayWrite() else { return false }
        if let found = form.check() {
            form.fail(found)
            return false
        }
        let name = form.name.trimmingCharacters(in: .whitespaces)
        let value = form.value
        form.fail(nil)
        form.working(true)
        defer { form.working(false) }
        do {
            let made = try await hub.host.elevated(
                "Store a new secret named \(name). The value is never shown again.", done: "stored", keepsEdit: true
            ) {
                try await service.createSecret(
                    name: name, value: value, delivery: form.delivery, runners: form.runners.sorted())
            }
            form.wipe()
            items = (items.filter { $0.name != made.name } + [made]).sorted { $0.name < $1.name }
            state = .ready
            hub.host.shell.showToast("\(made.name) stored. The value is write-only.")
            return true
        } catch is AdminDeclined {
            return false  // nothing was sent: the person's edit is still on screen
        } catch {
            form.wipe()
            form.fail(FieldIssue(code: hub.code(error) ?? "error", message: hub.words(error)))
            return false
        }
    }

    /// Replaces a value: the version goes up by one.
    func replace(_ form: SecretForm) async -> Bool {
        guard let hub, let service = hub.service, hub.mayWrite(), let old = form.existing else { return false }
        if let found = form.check() {
            form.fail(found)
            return false
        }
        let value = form.value
        form.fail(nil)
        form.working(true)
        defer { form.working(false) }
        do {
            let made = try await hub.host.elevated(
                "Replace the value of \(old.name). Version \(old.version) becomes \(old.version + 1).",
                done: "replaced",
                keepsEdit: true
            ) { try await service.rotateSecret(old.name, value: value) }
            form.wipe()
            if let i = items.firstIndex(where: { $0.name == made.name }) { items[i] = made }
            hub.host.shell.showToast("\(made.name) is now v\(made.version)")
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            form.wipe()
            form.fail(FieldIssue(code: hub.code(error) ?? "error", message: hub.words(error)))
            return false
        }
    }

    func delete(_ s: SecretItem) async -> Bool {
        guard let hub, let service = hub.service, hub.mayWrite() else { return false }
        rowError[s.name] = nil
        do {
            try await hub.host.elevated(
                "Delete \(s.name). Runners can no longer lease it.", done: "deleted", keepsEdit: false
            ) {
                try await service.deleteSecret(s.name)
            }
            items.removeAll { $0.name == s.name }
            leases.removeAll { $0.secret == s.name }
            if items.isEmpty { state = .empty }
            hub.host.shell.showToast("\(s.name) deleted")
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            rowError[s.name] = hub.words(error)
            return false
        }
    }

    func checkLease(_ f: LeaseForm) -> FieldIssue? {
        if f.runner.isEmpty {
            return FieldIssue(
                code: "bad_request", message: "Choose a runner. A secret with no runners cannot be leased.")
        }
        let t = f.ttl.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty {
            guard let n = Int64(t) else {
                return FieldIssue(code: "not_integer", message: "\(t) is not a whole number.")
            }
            if n < 1 || n > leaseLimit {
                return FieldIssue(
                    code: "out_of_bounds", message: "A lease lasts 1 to \(leaseLimit) seconds (secrets.lease_secs).")
            }
        }
        if !f.understood {
            return FieldIssue(code: "bad_request", message: "Confirm that an agent on that runner can read it.")
        }
        return nil
    }

    func lease(_ f: LeaseForm) async -> Bool {
        guard let hub, let service = hub.service, hub.mayWrite() else { return false }
        if let found = checkLease(f) {
            f.issue = found
            return false
        }
        f.issue = nil
        f.busy = true
        defer { f.busy = false }
        let ttl = Int64(f.ttl.trimmingCharacters(in: .whitespaces))
        do {
            let granted = try await hub.host.elevated(
                "Lease \(f.secret.name) to \(f.runner).", done: "leased", keepsEdit: true
            ) {
                try await service.lease(f.secret.name, runner: f.runner, ttl: ttl)
            }
            leases.insert(granted, at: 0)
            hub.host.shell.showToast("\(f.secret.name) leased to \(f.runner)")
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            f.issue = FieldIssue(code: hub.code(error) ?? "error", message: hub.words(error))
            return false
        }
    }
}
