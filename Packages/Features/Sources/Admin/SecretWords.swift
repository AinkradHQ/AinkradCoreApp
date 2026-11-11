import Foundation

/// What the Secrets page says (N24), as plain functions the tests pin. The Core stores only text secrets for now: it has no
/// type, group, description or last-used time, so those show as "Coming with the next Core" and nothing is invented.
enum SecretWords {
    static let comingNext = "Coming with the next Core"

    /// What a secret can be. Only `text` works today; the others are shown so people know they are planned.
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
            case .text: "A password, a token or a key on one line."
            case .multiline: "Text on many lines, like a PEM key."
            case .file: "Any file up to 1 MB, like a .p8 key or a JSON file."
            case .env: "Many names and values in one secret."
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
        var available: Bool { self == .text }
    }

    /// `20 B`, `1.2 KB`.
    static func size(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let kb = Double(bytes) / 1000
        return kb < 10 ? String(format: "%.1f KB", kb) : String(format: "%.0f KB", kb)
    }

    /// How an agent gets it, in the words a person would use.
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
        let who = runners.isEmpty ? "No runner may use it yet" : "Agents on \(runners.joined(separator: ", "))"
        let how =
            switch d {
            case "file": "get it as a file only they can read"
            case "askpass": "get it as the answer to git and ssh password prompts"
            default: "get it as an environment variable"
            }
        return runners.isEmpty ? "\(who). Choose a runner to let agents have it." : "\(who) \(how)."
    }

    /// `Oracle, Azure Dev`, or why there is none.
    static func usedBy(_ names: [String]) -> String { names.isEmpty ? "No runner yet" : names.joined(separator: ", ") }

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
        return (q.isEmpty || s.name.lowercased().contains(q)) && (runner.map { s.runners.contains($0) } ?? true)
    }

    /// The delete dialog's line about where it is used.
    static func usage(_ s: SecretItem, runnerNames: [String]) -> String {
        let used =
            runnerNames.isEmpty
            ? "No runner may use it."
            : "Used on \(runnerNames.count) runner\(runnerNames.count == 1 ? "" : "s") (\(runnerNames.joined(separator: ", ")))."
        return "\(used) \(versions(s)). Agents that need it will stop getting it."
    }
}

/// A group of secrets on the page. The Core has none yet, so every secret is in one section; when groups arrive this is the
/// one place that splits them.
struct SecretSectionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let items: [SecretItem]
}

enum SecretSections {
    static func sections(_ items: [SecretItem]) -> [SecretSectionItem] {
        items.isEmpty ? [] : [SecretSectionItem(id: "all", title: "All secrets", symbol: "lock.fill", items: items)]
    }
}
