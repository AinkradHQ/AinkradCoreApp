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
    }

    mutating func back() {
        guard step != .server, made == nil else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .server
        reach = .waiting
        signIn = .waiting
        hostKey = .waiting
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
