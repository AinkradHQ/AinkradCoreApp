import Foundation

/// Where Add Host stands: four steps (Server, Sign in, Name, Check) and what each one holds. Values only, so a test can walk
/// it; the wizard draws it and `LeylineModel.runAddCheck` runs the check.
struct AddHostFlow: Equatable {
    enum Step: Int, CaseIterable, Comparable {
        case server, signIn, name, check
        var title: String {
            switch self {
            case .server: "Server"
            case .signIn: "Sign in"
            case .name: "Name"
            case .check: "Check"
            }
        }
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }
    enum KeyChoice: Equatable {
        case none
        case saved(String)
        case importing
    }
    enum ImportFrom: Equatable { case file, text }
    /// The fields a failure can send a person back to, so the right one takes focus.
    enum Field: Equatable { case user, host, port, keys, passphrase, name }
    /// Which check a failure came from.
    enum Failure: Equatable {
        case reach, key
        case save(String)
    }
    /// One line of the check.
    enum Mark: Equatable {
        case waiting, running
        /// Passed, with the chip it shows ("31 ms", "Signed in").
        case done(String?)
        case failed(String)
        /// The host offers this key and waits for a person.
        case asks(String)
    }

    var step = Step.server
    var user = "root"
    var host = ""
    var port = "22"
    /// The jump host's id; nil = straight from the Core.
    var jump: String?
    var password = ""
    var key = KeyChoice.none
    var importFrom = ImportFrom.file
    var keyText = ""
    /// The file a key was read from, for its name.
    var keyFile: String?
    var passphrase = ""
    var name = ""
    var nameTouched = false
    /// The project (group) it joins; nil = none.
    var project: String?

    var reach = Mark.waiting
    var signIn = Mark.waiting
    var hostKey = Mark.waiting
    /// The host once the Core saved it.
    var made: HostItem?
    /// The host key a person trusted here, kept for the done screen.
    var trusted: String?
    /// The field that takes focus when a step appears (the step's first, or the one a "Change …" jumped to).
    var focus: Field? = .user
    /// What failed in the check, for its "Change …" button.
    var failure: Failure?

    var portNumber: Int? { Int(port).flatMap { HostRules.port($0) ? $0 : nil } }
    var serverOK: Bool { HostRules.address(host) && HostRules.username(user) && portNumber != nil }
    var signInOK: Bool {
        guard key == .importing else { return true }
        return keyText.contains("PRIVATE KEY") && (!Self.needsPassphrase(keyText) || !passphrase.isEmpty)
    }
    var nameOK: Bool { HostRules.label(name.trimmingCharacters(in: .whitespaces)) }
    var finished: Bool {
        guard made != nil else { return false }
        if case .done = hostKey { return true }
        return false
    }

    /// Whether Continue may go on from the current step.
    var canContinue: Bool {
        switch step {
        case .server: serverOK
        case .signIn: signInOK
        case .name: nameOK
        case .check: false
        }
    }

    /// What is wrong with what was typed, in plain words, per field. Empty fields say nothing: a fresh form is not an error.
    var problems: [Field: String] {
        var out: [Field: String] = [:]
        if !user.isEmpty, !HostRules.username(user) { out[.user] = "Letters, digits, dots, dashes and underscores." }
        if !host.isEmpty, !HostRules.address(host) { out[.host] = "A name or IP address, with no spaces." }
        if !port.isEmpty, portNumber == nil { out[.port] = "A number from 1 to 65535." }
        if nameTouched, !nameOK { out[.name] = "Give it a name of up to 64 characters." }
        if key == .importing, !keyText.isEmpty, !keyText.contains("PRIVATE KEY") {
            out[.keys] = "That is not a private key. It starts with -----BEGIN … PRIVATE KEY-----."
        }
        return out
    }

    /// Any field of the Server step changed. Pasting a whole `ssh user@host -p 2222` (or `user@host:2222`) into any of them
    /// fills all three; otherwise only that field takes the text.
    mutating func setServer(_ field: Field, _ text: String) {
        if SSHLine.fills(text) {
            setHost(text)
            return
        }
        switch field {
        case .user: user = text.trimmingCharacters(in: .whitespaces)
        case .port: port = text.filter(\.isNumber)
        default: setHost(text)
        }
    }

    /// The key choices in the order the list shows them: none, each saved key, import.
    static func choices(_ keyIDs: [String]) -> [KeyChoice] { [.none] + keyIDs.map(KeyChoice.saved) + [.importing] }

    /// ↑ / ↓ on the key list: the choice before or after, stopping at the ends (a list of radio choices, not a loop).
    mutating func moveKey(_ step: Int, keyIDs: [String]) {
        let all = Self.choices(keyIDs)
        let i = all.firstIndex(of: key) ?? 0
        key = all[min(max(i + step, 0), all.count - 1)]
    }

    /// The key a new host starts with: the one picked last time if it still exists, else the key most hosts use, else none.
    static func defaultKey(keyIDs: [String], usage: [String: Int], last: String?) -> KeyChoice {
        if let last, keyIDs.contains(last) { return .saved(last) }
        let best = keyIDs.max { (usage[$0] ?? 0, $1) < (usage[$1] ?? 0, $0) }
        return best.flatMap { (usage[$0] ?? 0) > 0 ? .saved($0) : nil } ?? .none
    }

    /// "Change …" on a failed check: the step and the field to fix it, the words on the button, and the check reset so it
    /// runs again from the start. Typed values are kept.
    static func fix(for failure: Failure) -> (step: Step, field: Field, title: String) {
        switch failure {
        case .reach: (.server, .host, "Change Server")
        case .key: (.signIn, .keys, "Change Key")
        case .save(let why):
            why.localizedCaseInsensitiveContains("name")
                ? (.name, .name, "Change Name") : (.server, .host, "Change Server")
        }
    }

    mutating func applyFix() {
        guard let failure else { return }
        let f = Self.fix(for: failure)
        step = f.step
        focus = f.field
        resetCheck()
    }

    mutating func resetCheck() {
        reach = .waiting
        signIn = .waiting
        hostKey = .waiting
        failure = nil
    }

    /// The Host field changed. A whole `ssh user@host -p 2222` (or `user@host:2222`) fills User, Host and Port.
    mutating func setHost(_ text: String) {
        if SSHLine.fills(text), let l = SSHLine.parse(text) {
            user = l.user ?? user
            host = l.host
            port = l.port.map(String.init) ?? port
        } else {
            host = text.trimmingCharacters(in: .whitespaces)
        }
        if !nameTouched { name = suggestedName(host) }
    }

    mutating func next() {
        guard canContinue, let s = Step(rawValue: step.rawValue + 1) else { return }
        if s == .name, !nameTouched { name = suggestedName(host) }
        step = s
        focus = Self.firstField(s)
    }

    /// The field a step focuses when it appears.
    static func firstField(_ s: Step) -> Field? {
        switch s {
        case .server: .user
        case .signIn: .keys
        case .name: .name
        case .check: nil
        }
    }

    mutating func back() {
        guard step != .server, made == nil else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .server
        focus = Self.firstField(step)
        resetCheck()
    }

    /// The draft the Core gets once the check reached the host. `keyID` is the saved key, or the one just imported.
    func draft(keyID: String?) -> HostDraft {
        HostDraft(
            name: name.trimmingCharacters(in: .whitespaces), address: host, username: user, port: portNumber ?? 22,
            keyID: keyID, jumpChain: jump.map { [$0] } ?? [], group: project)
    }

    /// The imported key's name: the file's name, else "<host>-key".
    var importName: String {
        let base = keyFile.map { ($0 as NSString).deletingPathExtension } ?? ""
        let n = base.isEmpty ? "\(name.isEmpty ? suggestedName(host) : name)-key" : base
        return String(n.prefix(64))
    }

    /// Whether a private key is sealed with a passphrase: a PEM that says ENCRYPTED, or an OpenSSH key whose cipher is not
    /// `none`. Unknown text counts as not sealed (the Core then says why it refused).
    static func needsPassphrase(_ key: String) -> Bool {
        if key.contains("ENCRYPTED") { return true }
        let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
        guard let r = key.range(of: begin), let e = key.range(of: "-----END OPENSSH PRIVATE KEY-----") else {
            return false
        }
        let b64 = key[r.upperBound..<e.lowerBound].filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(b64)) else { return false }
        let magic = Array("openssh-key-v1".utf8) + [0]
        let bytes = [UInt8](data)
        guard bytes.count > magic.count + 4, Array(bytes.prefix(magic.count)) == magic else { return false }
        var i = magic.count
        let len = bytes[i..<i + 4].reduce(0) { $0 << 8 | Int($1) }
        i += 4
        guard len > 0, i + len <= bytes.count else { return false }
        return String(decoding: bytes[i..<i + len], as: UTF8.self) != "none"
    }
}
