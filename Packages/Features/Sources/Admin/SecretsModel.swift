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
    var kind = SecretWords.Kind.text
    var description = ""
    /// nil: no group.
    var group: String?
    /// A file picked or dropped: its name, and how big it is. The bytes only live in `value` (base64 for a file secret).
    var fileName: String?
    var fileMode = "0600"
    private(set) var fileSize: Int64?
    var fileKindWord: String?
    private(set) var issue: FieldIssue?
    private(set) var busy = false

    init(existing: SecretItem? = nil) {
        self.existing = existing
        if let existing {
            kind = SecretWords.Kind(wire: existing.kind)
            delivery = existing.delivery
        }
    }

    /// The only way a value gets in.
    func setValue(_ v: String) { value = v }
    func wipe() {
        value = ""
        fileSize = nil
    }

    /// Takes a file's bytes: base64 for a file secret, text for the others. Nil when it is fine, else why not.
    func setFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return "That file could not be read."
        }
        if data.count > SecretWords.fileLimit {
            return "A file can be at most 1 MB. This one is \(SecretWords.size(Int64(data.count)))."
        }
        if kind.isFile {
            value = data.base64EncodedString()
        } else {
            guard let text = String(data: data, encoding: .utf8) else {
                return "That file is not text. Choose the File type for it."
            }
            value = text
        }
        fileName = url.lastPathComponent
        fileSize = Int64(data.count)
        fileKindWord = url.pathExtension.isEmpty ? "file" : url.pathExtension.lowercased()
        return nil
    }

    /// The size the person sees: the file's bytes, else the typed text.
    var shownSize: Int64? { fileSize ?? (value.isEmpty ? nil : Int64(value.utf8.count)) }

    var draft: SecretDraft {
        SecretDraft(
            name: name.trimmingCharacters(in: .whitespaces), kind: kind.wire, value: value,
            delivery: kind.isFile ? "file" : delivery, runners: runners.sorted(),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines), group: group,
            fileName: kind.isFile ? fileName : nil, fileMode: kind.isFile ? fileMode : nil)
    }

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
        if kind.isFile, existing == nil, fileName == nil {
            return FieldIssue(code: "bad_request", message: "Choose the file to seal.")
        }
        if kind.isFile, existing == nil, !Self.validMode(fileMode) {
            return FieldIssue(code: "bad_request", message: "The file mode is three or four octal digits, like 0600.")
        }
        return nil
    }

    static func validMode(_ m: String) -> Bool {
        (3...4).contains(m.count) && m.allSatisfy { ("0"..."7").contains($0) }
    }

    fileprivate func fail(_ i: FieldIssue?) { issue = i }
    fileprivate func working(_ b: Bool) { busy = b }
}

/// The lease sheet: which runner, how long, and the person's word that an agent there can read the value. For one secret or
/// for every secret of a group.
@MainActor @Observable
final class LeaseForm {
    enum Target {
        case secret(SecretItem)
        case group(SecretGroupItem)
    }
    let target: Target
    var runner: String
    var ttl = ""
    var understood = false
    fileprivate(set) var issue: FieldIssue?
    fileprivate(set) var busy = false

    init(secret: SecretItem) {
        target = .secret(secret)
        runner = secret.runnersUsing.first ?? ""
    }
    init(group: SecretGroupItem) {
        target = .group(group)
        runner = group.runners.first ?? ""
    }

    var name: String {
        switch target {
        case .secret(let s): s.name
        case .group(let g): g.name
        }
    }
    var runnerIDs: [String] {
        switch target {
        case .secret(let s): s.runnersUsing
        case .group(let g): g.runners
        }
    }
    var isGroup: Bool { if case .group = target { true } else { false } }
}

/// Settings, Security, Secrets: names and metadata only, plus the leases this Mac granted. Set, replace, lease and delete go
/// through Touch ID. A value is never read back, shown, copied or logged.
@MainActor @Observable
final class SecretsModel {
    private(set) var items: [SecretItem] = []
    private(set) var groups: [SecretGroupItem] = []
    var state: SectionState = .loading
    private(set) var leases: [LeaseItem] = []
    private(set) var runners: [RunnerChoice] = []
    private(set) var rowError: [String: String] = [:]
    @ObservationIgnored private weak var hub: AdminModel?

    init(hub: AdminModel) { self.hub = hub }

    var mode: Int { hub?.registry.secretsMode ?? 0 }
    /// Off only once the registry has loaded and says so: while it loads, or when it failed, `mode` reads as 0 and must
    /// not hide the secrets or lock the New buttons.
    var isOff: Bool { hub?.registry.state == .ready && mode == 0 }
    var leaseLimit: Int64 { hub?.registry.item("secrets.lease_secs")?.value ?? 120 }

    func reset() {
        items = []
        groups = []
        leases = []
        state = .loading
    }

    func reload() async {
        guard let hub, let service = hub.service else { return }
        if items.isEmpty { state = .loading }
        do {
            items = try await service.secrets().sorted { $0.name < $1.name }
            groups = (try? await service.secretGroups().sorted { $0.name < $1.name }) ?? groups
            state = items.isEmpty && groups.isEmpty ? .empty : .ready
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
        let draft = form.draft
        form.fail(nil)
        form.working(true)
        defer { form.working(false) }
        do {
            let made = try await hub.host.elevated(
                "Store a new secret named \(name). The value is never shown again.", done: "stored", keepsEdit: true
            ) {
                try await service.createSecret(draft)
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
        let fileName = old.kind == "file" ? form.fileName : nil
        form.fail(nil)
        form.working(true)
        defer { form.working(false) }
        do {
            let made = try await hub.host.elevated(
                "Replace the value of \(old.name). Version \(old.version) becomes \(old.version + 1).",
                done: "replaced",
                keepsEdit: true
            ) { try await service.rotateSecret(old.name, value: value, fileName: fileName) }
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

    // MARK: groups

    /// nil when the Core took it, else why not. `existing` edits the description and runners (the Core has no rename).
    func saveGroup(name: String, description: String, runners: [String], existing: Bool) async -> String? {
        guard let hub, let service = hub.service, hub.mayWrite() else { return "This device may not change secrets." }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard SecretForm.validName(n) else {
            return
                "A name starts with a lower case letter, then letters, digits, dots, dashes or underscores (up to 64)."
        }
        do {
            let g = try await hub.host.elevated(
                existing ? "Change the group \(n)." : "Make the group \(n).", done: "saved", keepsEdit: true
            ) {
                existing
                    ? try await service.updateSecretGroup(n, description: description, runners: runners)
                    : try await service.createSecretGroup(name: n, description: description, runners: runners)
            }
            groups = (groups.filter { $0.name != g.name } + [g]).sorted { $0.name < $1.name }
            await reload()
            hub.host.shell.showToast(existing ? "\(n) saved" : "Group \(n) made")
            return nil
        } catch is AdminDeclined {
            return ""
        } catch { return hub.words(error) }
    }

    func deleteGroup(_ g: SecretGroupItem) async -> String? {
        guard let hub, let service = hub.service, hub.mayWrite() else { return "This device may not change secrets." }
        do {
            try await hub.host.elevated("Delete the group \(g.name).", done: "deleted", keepsEdit: false) {
                try await service.deleteSecretGroup(g.name)
            }
            groups.removeAll { $0.name == g.name }
            await reload()
            hub.host.shell.showToast("Group \(g.name) deleted")
            return nil
        } catch is AdminDeclined {
            return ""
        } catch { return hub.words(error) }
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
            if items.isEmpty && groups.isEmpty { state = .empty }
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
                code: "bad_request",
                message: "Choose a runner. \(f.isGroup ? "A group" : "A secret") with no runners cannot be used by one."
            )
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
            return FieldIssue(code: "bad_request", message: "Confirm that an AI session on that runner can read it.")
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
            let granted: [LeaseItem] = try await hub.host.elevated(
                "Let \(f.runner) use \(f.name).", done: "leased", keepsEdit: true
            ) {
                switch f.target {
                case .secret(let s): [try await service.lease(s.name, runner: f.runner, ttl: ttl)]
                case .group(let g): try await service.leaseGroup(g.name, runner: f.runner, ttl: ttl)
                }
            }
            leases.insert(contentsOf: granted, at: 0)
            hub.host.shell.showToast("\(f.name) is allowed on \(runnerName(f.runner))")
            return true
        } catch is AdminDeclined {
            return false
        } catch {
            f.issue = FieldIssue(code: hub.code(error) ?? "error", message: hub.words(error))
            return false
        }
    }
}
