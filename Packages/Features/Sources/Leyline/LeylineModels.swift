import CoreUI
import Foundation

/// What a host's AI sessions, agents and MCP may do on it: one rule (Y4 builds the gate that enforces it).
enum AIRule: Equatable, Sendable, CaseIterable, Identifiable {
    case readOnly, ask, allowed
    var id: String { wire }
    /// The Core's word (`read_only`, `ask`, `allowed`).
    var wire: String {
        switch self {
        case .readOnly: "read_only"
        case .ask: "ask"
        case .allowed: "allowed"
        }
    }
    init(wire: String) {
        switch wire {
        case "read_only": self = .readOnly
        case "allowed": self = .allowed
        default: self = .ask  // an unknown rule is shown as the safe default, never as more than it is
        }
    }
    var title: String {
        switch self {
        case .readOnly: "Read-only"
        case .ask: "Ask first"
        case .allowed: "Allowed"
        }
    }
    var line: String {
        switch self {
        case .readOnly: "only safe commands"
        case .ask: "you approve each"
        case .allowed: "runs, all logged"
        }
    }
}

/// One host as the gallery and the host page show it (`HostView` of the Core's Leyline module).
struct HostItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var address: String
    var port: Int
    var username: String
    /// The key it logs in with; nil = a password typed in the terminal.
    var keyID: String?
    /// Jump host ids, in order, at most three.
    var jumpChain: [String]
    /// Runner device id; nil = the Core machine's own runner.
    var viaRunner: String?
    var group: String?
    var tags: [String]
    var aiRule: AIRule
    var os: String?
    var createdAt: Date?
    /// The runner device this host was made into (Make Runner): display only, never a route and never proof that the
    /// runner is this host (the Core says the same).
    var runnerDevice: String?
    /// How the Core's last reachability check went (API minor 95): nil for a host it cannot reach directly or before the first.
    var reach: HostReach?
    /// How Make Runner stands on this host: installing, failed (with the reason) or paired.
    var runnerInstall: HostRunnerInstall?

    /// `user@address`, with the port only when it is not 22.
    var login: String { "\(username)@\(address)" + (port == 22 ? "" : ":\(port)") }
}

/// A host's reachability: it answered like an SSH server (a TCP connect and the banner, no login).
struct HostReach: Equatable, Sendable {
    var up: Bool
    var latencyMS: Int?
    var checkedAt: Date?
    var seenAt: Date?
}

extension HostItem {
    /// "Online" or "Not answering", from the Core's last reachability check; nil when it has none.
    var presence: (label: String, tone: Tone)? {
        reach.map { $0.up ? ("Online", .run) : ("Not answering", .fail) }
    }

    /// "Seen just now", "Seen 3 hours ago": the last time it answered; nil when it never has.
    var seenLine: String? {
        guard let d = reach?.up == true ? reach?.checkedAt : reach?.seenAt else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Seen " + f.localizedString(for: d, relativeTo: Date())
    }
}

/// Make Runner on a host: `installing`, `failed` or `paired`; `mode` is `system` or `user`.
struct HostRunnerInstall: Equatable, Sendable {
    var state: String
    var mode: String?
    var reason: String?
}

/// A key the Core keeps sealed. The private half never reaches this app after it is made.
struct KeyItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    /// `ed25519`, `ecdsa-p256`, `ecdsa-p384` or `rsa`.
    var algo: String
    var publicKey: String
    /// `SHA256:…`, as `ssh-keygen -l` prints it.
    var fingerprint: String
    var imported: Bool
    var createdAt: Date?
    /// The size the Core reports (RSA modulus, or the curve); nil from a Core that does not say.
    var bits: Int? = nil

    /// "ed25519", "ecdsa" or "RSA 4096".
    var typeWord: String {
        if algo == "rsa" { return bits.map { "RSA \($0)" } ?? "RSA" }
        return algo.hasPrefix("ecdsa") ? "ecdsa" : algo
    }

    /// "ed25519 · made in the Core · 3 Nov".
    var line: String {
        let algoWord = typeWord
        let how = imported ? "imported" : "made in the Core"
        guard let createdAt else { return "\(algoWord) · \(how)" }
        return "\(algoWord) · \(how) · \(createdAt.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// A host key the Core pinned on the first connect. TODO(Y2-02): the Core serves none yet, so a live Core shows the empty
/// words; the Debug demo fills it.
struct KnownHostItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case trusted, changed }
    var id: String { host }
    let host: String
    let fingerprint: String
    var state: State = .trusted
    var since: Date?
}

enum LeylineLoad: Equatable {
    case notConnected, loading, ready
    case failed(String)
    /// The Core has no Leyline module (it answered 404).
    case absent
}

/// The two pages of the gallery's top bar. TODO(Y9-04): Fleet.
enum LeylinePage: String, CaseIterable, Identifiable {
    case hosts, keys
    var id: String { rawValue }
    var title: String { self == .hosts ? "Hosts" : "Keys" }
}

/// The tabs of a host's view. Commands has no tab: it opens from More.
enum HostSection: String, CaseIterable, Identifiable {
    case terminal, files, history, access, commands
    var id: String { rawValue }
    static let tabs: [HostSection] = [.terminal, .files, .history, .access]
    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .files: "Files"
        case .commands: "Commands"
        case .history: "History"
        case .access: "Access"
        }
    }
    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .files: "folder"
        case .commands: "chevron.right.2"
        case .history: "clock"
        case .access: "lock"
        }
    }
    /// ⌘1, ⌘2, ⌘3 and ⌘, (Access is where a host's settings are).
    var key: Character? {
        switch self {
        case .terminal: "1"
        case .files: "2"
        case .history: "3"
        case .access: ","
        case .commands: nil
        }
    }
    var keyWord: String { key.map { "⌘\($0)" } ?? "" }
    static func forKey(_ c: Character) -> HostSection? { tabs.first { $0.key == c } }

    /// What a page says while it has nothing to show.
    var empty: (title: String, line: String) {
        switch self {
        case .terminal: ("Terminal", "No terminal is open on this host.")
        case .files: ("Files", "Browse the host over SFTP, drag files in to upload and out to download.")
        case .commands: ("Pre-set commands", "No commands yet. Add the ones you run often; AI follows the same rules.")
        case .history: ("History", "Nothing has run on this host yet. Everything you and AI do is listed here.")
        case .access: ("Access", "")
        }
    }
}

/// A group of the gallery: a project or group name and its hosts. Hosts with no group fall under "Shared".
struct HostGroup: Identifiable, Equatable {
    let name: String?
    let hosts: [HostItem]
    /// The title of the hosts that are in no group.
    static let shared = "Shared"
    var id: String { name ?? "" }
    var title: String { name ?? Self.shared }
    var sub: String {
        let n = "\(hosts.count) host\(hosts.count == 1 ? "" : "s")"
        return name == nil ? "not in a group · \(n)" : "group · \(n)"
    }

    /// Named groups A to Z, the ungrouped ones last; hosts A to Z inside.
    static func grouping(_ hosts: [HostItem]) -> [HostGroup] {
        let by = Dictionary(grouping: hosts) { $0.group }
        func sorted(_ h: [HostItem]) -> [HostItem] {
            h.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let named = by.keys.compactMap { $0 }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return named.map { HostGroup(name: $0, hosts: sorted(by[$0] ?? [])) }
            + (by[nil].map { [HostGroup(name: nil, hosts: sorted($0))] } ?? [])
    }
}

/// The Core's rules for a host's fields, checked here first so a typo is caught before Touch ID. The Core checks again.
enum HostRules {
    static func only(_ s: String, _ extra: String) -> Bool {
        s.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType == .decimal))
                || extra.unicodeScalars.contains($0)
        }
    }
    static func address(_ s: String) -> Bool {
        (1...255).contains(s.utf8.count) && !s.hasPrefix("-") && only(s, ".:%_-")
    }
    static func username(_ s: String) -> Bool { (1...32).contains(s.utf8.count) && !s.hasPrefix("-") && only(s, "._-") }
    static func port(_ n: Int) -> Bool { (1...65535).contains(n) }
    static func label(_ s: String) -> Bool {
        (1...64).contains(s.count) && s == s.trimmingCharacters(in: .whitespacesAndNewlines)
            && !s.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
    static func tag(_ s: String) -> Bool { (1...32).contains(s.utf8.count) && only(s, "._-") }

    /// "web-1, EU-West" as the Core stores tags: lowercased, no repeats. Nil when one is not a tag.
    static func tags(_ text: String) -> [String]? {
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let t = raw.lowercased()
            guard tag(t) else { return nil }
            if !out.contains(t) { out.append(t) }
        }
        return out.count <= 20 ? out : nil
    }

    /// What the quick field takes: `user@address`, `user@address:port` or `address` alone (the user is then "root").
    struct Login: Equatable {
        var username: String
        var address: String
        var port: Int
    }
    static func login(_ text: String) -> Login? {
        let t = text.trimmingCharacters(in: .whitespaces)
        var user = "root"
        var rest = Substring(t)
        if let at = t.lastIndex(of: "@") {
            user = String(t[..<at])
            rest = t[t.index(after: at)...]
        }
        var port = 22
        // A single colon is `address:port`; more than one is an IPv6 address.
        if rest.filter({ $0 == ":" }).count == 1, let c = rest.lastIndex(of: ":") {
            guard let n = Int(rest[rest.index(after: c)...]) else { return nil }
            port = n
            rest = rest[..<c]
        }
        let address = String(rest)
        guard username(user), self.address(address), self.port(port) else { return nil }
        return Login(username: user, address: address, port: port)
    }

    /// A label from an address: `db-1.internal` -> `db-1`, an IP stays whole.
    static func label(fromAddress a: String) -> String {
        let isIP = a.contains(":") || a.allSatisfy { $0.isNumber || $0 == "." }
        return isIP ? a : String(a.split(separator: ".").first ?? Substring(a))
    }
}

enum Words {
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
