import Foundation

/// What the Secrets page says (N24), as plain functions the tests pin.
enum SecretWords {
    /// A file secret is at most 1 MiB (decision G1).
    static let fileLimit = 1_048_576

    /// What a secret can be (`kind` on the Core).
    enum Kind: CaseIterable, Equatable {
        case text, multiline, file, env
        var title: String {
            switch self {
            case .text: "Text"
            case .multiline: "Multi-line"
            case .file: "File"
            case .env: ".env file"
            }
        }
        var blurb: String {
            switch self {
            case .text: "A password, token or key"
            case .multiline: "A PEM or SSH key"
            case .file: "Up to 1 MB, like a .p8"
            case .env: "Many names and values"
            }
        }
        var symbol: String {
            switch self {
            case .text: "key.fill"
            case .multiline: "list.bullet"
            case .file: "doc.fill"
            case .env: "curlybraces"
            }
        }
        /// The word the Core takes and sends back.
        var wire: String {
            switch self {
            case .text: "text"
            case .multiline: "multiline"
            case .file: "file"
            case .env: "env_bundle"
            }
        }
        init(wire: String) { self = Self.allCases.first { $0.wire == wire } ?? .text }
        var isFile: Bool { self == .file }
        /// Typed or pasted on several lines, or read from a text file.
        var isMultiline: Bool { self == .multiline || self == .env }
        var delivery: String { self == .file ? "file" : "env" }
    }

    /// `20 B`, `1.2 KB`.
    static func size(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let kb = Double(bytes) / 1000
        return kb < 10 ? String(format: "%.1f KB", kb) : String(format: "%.0f KB", kb)
    }

    /// How an AI session gets it, in the words a person would use.
    static func delivery(_ d: String) -> (title: String, line: String, symbol: String) {
        switch d {
        case "env": ("As a setting", "As a setting (environment variable)", "terminal.fill")
        case "file": ("As a file", "As a file", "doc.fill")
        case "askpass": ("As a password prompt", "As a password prompt (for git and ssh)", "key.horizontal.fill")
        default: (d, d, "questionmark")
        }
    }

    /// The preview under the details step: what agents on those runners will get.
    static func preview(delivery d: String, runners: [String]) -> String {
        let who = runners.isEmpty ? "No runner may use it yet" : "AI sessions on \(runners.joined(separator: ", "))"
        let how =
            switch d {
            case "file": "get it as a file only they can read"
            case "askpass": "get it as the answer to git and ssh password prompts"
            default: "get it as an environment variable"
            }
        return runners.isEmpty ? "\(who). Choose a runner to let AI sessions have it." : "\(who) \(how)."
    }

    /// `Oracle, Azure Dev`, or why there is none.
    static func usedBy(_ names: [String]) -> String { names.isEmpty ? "No runner yet" : names.joined(separator: ", ") }

    /// `Used 2 h ago · 12 times`, or `Never used`.
    static func lastUsed(_ s: SecretItem, now: Date = Date()) -> String {
        guard let at = s.lastUsedAt else { return "Never used" }
        let secs = max(0, now.timeIntervalSince(at))
        let ago =
            secs < 60
            ? "just now"
            : secs < 3600
                ? "\(Int(secs / 60)) min ago"
                : secs < 86_400 ? "\(Int(secs / 3600)) h ago" : "\(Int(secs / 86_400)) d ago"
        return "Used \(ago) · \(s.useCount) time\(s.useCount == 1 ? "" : "s")"
    }

    /// The Last used column: `Never`, `Just now`, `12 min ago`, `2 hours ago`, `Yesterday`, `3 days ago`.
    static func lastUsedShort(_ s: SecretItem, now: Date = Date()) -> String {
        guard let at = s.lastUsedAt else { return "Never" }
        let secs = max(0, now.timeIntervalSince(at))
        if secs < 60 { return "Just now" }
        if secs < 3600 { return "\(Int(secs / 60)) min ago" }
        if secs < 86_400 {
            let h = Int(secs / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        let d = Int(secs / 86_400)
        return d == 1 ? "Yesterday" : "\(d) days ago"
    }

    /// A loan in the Used by column: `Lent to Azure Dev · 41 min left`, `… · 40 s left`, or `Back from Azure Dev`.
    static func lent(to runner: String, secondsLeft: Int) -> String {
        if secondsLeft <= 0 { return "Back from \(runner)" }
        let left = secondsLeft < 60 ? "\(secondsLeft) s" : "\((secondsLeft + 59) / 60) min"
        return "Lent to \(runner) · \(left) left"
    }

    /// The line beside the page title: `6 · values never come back`.
    static func header(count: Int) -> String { "\(count) · values never come back" }

    /// How a row's value is described: `Sealed · 1.2 KB`, or the file name for a file.
    static func sealed(_ s: SecretItem) -> String {
        let size = "Sealed · \(size(s.size))"
        return Kind(wire: s.kind).isFile ? (s.fileName.map { "\($0) · \(size)" } ?? size) : size
    }

    /// The row's second line: the description, else how an agent gets it.
    static func line(_ s: SecretItem) -> String { s.description.isEmpty ? delivery(s.delivery).line : s.description }

    /// The Core has no last-used time yet, so the row says when the value last changed.
    static func changed(_ s: SecretItem, now: Date = Date()) -> String {
        let secs = now.timeIntervalSince(s.updatedAt)
        if secs < 60 { return "Changed just now" }
        let m = Int(secs / 60)
        if m < 60 { return "Changed \(m) min ago" }
        if m < 1440 { return "Changed \(m / 60) h ago" }
        return "Changed \(m / 1440) d ago"
    }

    /// `First value`, or `Changed 3 times`.
    static func versions(_ s: SecretItem) -> String {
        s.version <= 1 ? "First value" : "Changed \(s.version - 1) time\(s.version == 2 ? "" : "s")"
    }

    /// The search box and the runner filter.
    static func matches(_ s: SecretItem, query: String, runner: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return (q.isEmpty || s.name.lowercased().contains(q)) && (runner.map { s.runnersUsing.contains($0) } ?? true)
    }

    /// The delete dialog's line about where it is used.
    static func usage(_ s: SecretItem, runnerNames: [String]) -> String {
        let used =
            runnerNames.isEmpty
            ? "No runner may use it."
            : "Used on \(runnerNames.count) runner\(runnerNames.count == 1 ? "" : "s") (\(runnerNames.joined(separator: ", ")))."
        return "\(used) \(versions(s)). AI sessions that need it will stop getting it."
    }
}

/// A section of the page: a group (with its description and runners) or "No group" at the end.
struct SecretSectionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let items: [SecretItem]
    /// nil for "No group".
    var group: SecretGroupItem?
}

enum SecretSections {
    /// Each group, even an empty one, in name order, then the secrets with no group. A secret whose group is unknown here goes
    /// to "No group". While a search narrows the list, empty groups are left out.
    static func sections(_ items: [SecretItem], groups: [SecretGroupItem], narrowed: Bool = false)
        -> [SecretSectionItem]
    {
        var out: [SecretSectionItem] = []
        let known = Set(groups.map(\.name))
        for g in groups.sorted(by: { $0.name < $1.name }) {
            let mine = items.filter { $0.group == g.name }
            if narrowed && mine.isEmpty { continue }
            out.append(
                SecretSectionItem(id: "g-\(g.name)", title: g.name, symbol: "folder.fill", items: mine, group: g))
        }
        let loose = items.filter { $0.group == nil || !known.contains($0.group!) }
        if !loose.isEmpty || (out.isEmpty && !items.isEmpty) {
            out.append(
                SecretSectionItem(
                    id: "none", title: groups.isEmpty ? "All secrets" : "No group", symbol: "lock.fill", items: loose))
        }
        return out
    }
}
