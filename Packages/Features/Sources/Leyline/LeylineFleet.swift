import CoreGraphics
import Foundation

// The pure parts of the Leyline page (map, list, peek): status, group summaries, the map's layout, arrow-key moves and the
// `ssh` line Add Host reads. No views here, so each is pinned by a test.

/// Map or List (⌘M / ⌘L).
enum LeylineLayout: String, CaseIterable, Sendable {
    case map, list
}

/// A host's light: from the Core's last reachability check. "Slow" is an answer that took 150 ms or more.
enum HostLight: Equatable, Sendable {
    case ok, slow, off, unknown
}

/// What the Core does not send for a host yet. A live Core leaves it empty, so each element that reads it hides; only the Debug
/// demo fills it, so its screenshots show the whole design.
struct HostExtras: Equatable, Sendable {
    /// Answer times, oldest first, for the list's sparkline.
    var latencyHistory: [Double] = []
    /// "Ubuntu 24.04"; the Core only knows `linux` / `darwin`.
    var osName: String?
    /// "23 days".
    var uptime: String?
    /// "8 GB".
    var memoryTotal: String?
    /// "31 GB free".
    var diskFree: String?
    /// An AI request waiting for a person on this host, as the command it wants to run.
    var approval: String?
}

extension HostItem {
    static let slowMS = 150

    var light: HostLight {
        guard let r = reach else { return .unknown }
        if !r.up { return .off }
        return (r.latencyMS ?? 0) >= Self.slowMS ? .slow : .ok
    }

    /// "31 ms", "offline", or nil before the first check.
    var latencyWord: String? {
        guard let r = reach else { return nil }
        guard r.up else { return "offline" }
        return r.latencyMS.map { "\($0) ms" } ?? "online"
    }

    /// Reached straight from the Core (no jump host, no runner).
    var direct: Bool { jumpChain.isEmpty }

    /// An SF Symbol by what it is: a jump host, a database, else a server.
    func symbol(isJump: Bool) -> String {
        if isJump { return "checkmark.shield" }
        let n = (name + " " + tags.joined(separator: " ")).lowercased()
        return ["db", "backup", "postgres", "mysql", "redis"].contains { n.contains($0) } ? "cylinder" : "cpu"
    }
}

/// A group's line: "14 hosts", "2 slow", "1 offline", and how many AI requests wait.
struct GroupSummary: Equatable, Sendable {
    var hosts: Int
    var slow: Int
    var offline: Int
    var approvals: Int

    init(_ hosts: [HostItem], approvals: Set<String> = []) {
        self.hosts = hosts.count
        slow = hosts.filter { $0.light == .slow }.count
        offline = hosts.filter { $0.light == .off }.count
        self.approvals = hosts.filter { approvals.contains($0.id) }.count
    }

    /// "14 hosts · 2 slow · 1 offline" as its parts.
    var words: [String] {
        ["\(hosts) host\(hosts == 1 ? "" : "s")"] + (slow > 0 ? ["\(slow) slow"] : [])
            + (offline > 0 ? ["\(offline) offline"] : [])
    }
}

/// Where the cards of the map sit. Small fleets: one card per host, a column per hop (straight from the Core, through one jump
/// host, …). Big fleets (`bigFleet`): a card per group, and only the open group's hosts spread out in columns.
enum RouteLayout {
    /// More than this many hosts and the map shows groups.
    static let bigFleet = 12
    /// Rows per column of the open group on a big map.
    static let groupRows = 8

    /// Column (hops before it) and row (in steps, may be fractional) of each host. Column 0 holds the jump hosts first, then
    /// the rest in group order; a host reached through a jump host sits beside it, its siblings centred on it.
    static func place(_ hosts: [HostItem]) -> [String: (col: Int, row: Double)] {
        let ids = Set(hosts.map(\.id))
        let jumps = Set(hosts.flatMap(\.jumpChain))
        func col(_ h: HostItem) -> Int { h.jumpChain.allSatisfy(ids.contains) ? min(h.jumpChain.count, 2) : 0 }
        var out: [String: (col: Int, row: Double)] = [:]
        let first = hosts.filter { col($0) == 0 }
        let ordered = first.filter { jumps.contains($0.id) } + first.filter { !jumps.contains($0.id) }
        for (i, h) in ordered.enumerated() { out[h.id] = (0, Double(i)) }
        for c in 1...2 {
            let here = hosts.filter { col($0) == c }
            let byParent = Dictionary(grouping: here) { $0.jumpChain[c - 1] }
            var floor = -0.4
            for parent in byParent.keys.sorted(by: { (out[$0]?.row ?? 0) < (out[$1]?.row ?? 0) }) {
                let kids = byParent[parent] ?? []
                let centre = out[parent]?.row ?? 0
                for (k, h) in kids.enumerated() {
                    let row = max(centre + (Double(k) - Double(kids.count - 1) / 2) * 0.8, floor)
                    out[h.id] = (c, row)
                    floor = row + 0.8
                }
            }
        }
        return out
    }
}

/// The arrow keys, as pure moves.
enum FleetNav {
    /// The next id in a list, wrapping at both ends; the first (or last) when nothing is selected.
    static func step(_ ids: [String], from current: String?, by step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let i = current.flatMap({ ids.firstIndex(of: $0) }) else { return step >= 0 ? ids.first : ids.last }
        return ids[((i + step) % ids.count + ids.count) % ids.count]
    }

    /// The nearest card in the arrow's direction (`dx` or `dy` is -1 or 1). Off-axis distance counts double, so → stays on
    /// its row before it jumps to another.
    static func nearest(from: CGPoint, in points: [String: CGPoint], dx: Int, dy: Int) -> String? {
        var best: (id: String, d: CGFloat)?
        for (id, p) in points {
            let vx = p.x - from.x
            let vy = p.y - from.y
            if dx != 0, vx * CGFloat(dx) <= 1 { continue }
            if dy != 0, vy * CGFloat(dy) <= 1 { continue }
            let d = hypot(vx, vy) + (dx != 0 ? abs(vy) : abs(vx)) * 2
            if best == nil || d < best!.d || (d == best!.d && id < best!.id) { best = (id, d) }
        }
        return best?.id
    }
}

/// What Add Host's Host field reads: `ssh user@host -p 2222`, `user@host:2222`, `user@host`, or a bare host. Nil when the
/// text is not a whole command or address (the field then keeps it as typed).
struct SSHLine: Equatable, Sendable {
    var user: String?
    var host: String
    var port: Int?

    static func parse(_ text: String) -> SSHLine? {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        if words.first == "ssh" { words.removeFirst() }
        var port: Int?
        var target: String?
        var i = 0
        while i < words.count {
            let w = words[i]
            if w == "-p", i + 1 < words.count {
                guard let n = Int(words[i + 1]), HostRules.port(n) else { return nil }
                port = n
                i += 2
            } else if w.hasPrefix("-p"), let n = Int(w.dropFirst(2)) {
                guard HostRules.port(n) else { return nil }
                port = n
                i += 1
            } else if target == nil, !w.hasPrefix("-") {
                target = w
                i += 1
            } else {
                return nil
            }
        }
        guard var rest = target else { return nil }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }
        // A single colon is host:port; more is an IPv6 address.
        if rest.filter({ $0 == ":" }).count == 1, let c = rest.lastIndex(of: ":") {
            guard let n = Int(rest[rest.index(after: c)...]), HostRules.port(n) else { return nil }
            port = n
            rest = String(rest[..<c])
        }
        guard HostRules.address(rest), user.map(HostRules.username) ?? true else { return nil }
        return SSHLine(user: user, host: rest, port: port)
    }

    /// Whether the text says more than a host (a user, a port or `ssh`), so pasting it should fill the other fields.
    static func fills(_ text: String) -> Bool {
        guard let l = parse(text) else { return false }
        return l.user != nil || l.port != nil || text.trimmingCharacters(in: .whitespaces).hasPrefix("ssh ")
    }
}

/// The name Add Host suggests from the address: `web-1.example.com` -> `web-1`, `192.0.2.40` -> `server-40`.
func suggestedName(_ address: String) -> String {
    let a = address.trimmingCharacters(in: .whitespaces)
    if a.isEmpty { return "" }
    if a.allSatisfy({ $0.isNumber || $0 == "." }) {
        return "server-" + (a.split(separator: ".").last.map(String.init) ?? a)
    }
    if a.contains(":") { return "server" }
    return String(a.split(separator: ".").first ?? Substring(a))
}
