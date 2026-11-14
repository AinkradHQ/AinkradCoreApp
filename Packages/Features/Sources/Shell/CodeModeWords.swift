import Foundation

/// Code Mode in plain words, shared by the transcript, the approval card and the audit log: an operation id
/// (`brainAiSearch`, `connections.github.get_issue`) as a phrase for what happened and for what is about to, and a refusal
/// code as a sentence. Words say "AI session", never "agent". No operation body or argument value is ever put in a phrase.
public enum CodeModeWords {
    public struct Op: Equatable, Sendable {
        /// After the fact: "searched the Brain".
        public let did: String
        /// Before it: "propose a record to the Brain inbox".
        public let will: String
        public let symbol: String
    }

    private static let known: [String: Op] = [
        "brainAiRooms": Op(
            did: "listed the Brain rooms it can see", will: "list the Brain rooms", symbol: "books.vertical"),
        "brainAiSearch": Op(did: "searched the Brain", will: "search the Brain", symbol: "magnifyingglass"),
        "brainAiRecord": Op(did: "read a Brain record", will: "read a Brain record", symbol: "doc.text"),
        "brainAiDecisions": Op(did: "read Brain decisions", will: "read Brain decisions", symbol: "checkmark.seal"),
        "brainAiProjectState": Op(
            did: "read the project state in the Brain", will: "read the project state in the Brain",
            symbol: "list.bullet.rectangle"),
        "brainAiPropose": Op(
            did: "proposed a Brain record", will: "propose a record to the Brain inbox", symbol: "tray.and.arrow.down"),
        "listAgentSessions": Op(did: "listed AI sessions", will: "list AI sessions", symbol: "sparkles"),
        "getAgentSession": Op(did: "read an AI session", will: "read an AI session", symbol: "sparkles"),
        "getAgentTranscript": Op(
            did: "read an AI session's transcript", will: "read an AI session's transcript", symbol: "text.alignleft"),
        "listAudit": Op(did: "read the audit log", will: "read the audit log", symbol: "doc.text.magnifyingglass"),
        "getCoreHealth": Op(
            did: "checked the Core's health", will: "check the Core's health", symbol: "heart.text.square"),
    ]

    private static let verbs: [String: (did: String, will: String)] = [
        "get": ("read", "read"), "list": ("listed", "list"), "create": ("created", "create"),
        "update": ("updated", "update"), "delete": ("deleted", "delete"), "add": ("added", "add"),
        "search": ("searched", "search"), "merge": ("merged", "merge"), "close": ("closed", "close"),
        "comment": ("commented on", "comment on"), "transition": ("moved", "move"), "assign": ("assigned", "assign"),
        "propose": ("proposed", "propose"), "set": ("changed", "change"), "remove": ("removed", "remove"),
    ]

    static let services = ["github": "GitHub", "jira": "Jira", "linear": "Linear", "slack": "Slack"]

    public static func op(_ id: String) -> Op {
        if let o = known[id] { return o }
        let parts = id.split(separator: ".").map(String.init)
        if parts.count == 3, parts[0] == "connections" {
            let words = parts[2].split(separator: "_").map(String.init)
            let rest = words.dropFirst().joined(separator: " ")
            let v = verbs[words.first ?? ""]
            let with = " with \(services[parts[1]] ?? parts[1].capitalized)"
            let tail = (rest.isEmpty ? "" : " " + rest) + with
            return Op(
                did: (v?.did ?? words.joined(separator: " ")) + tail,
                will: (v?.will ?? words.joined(separator: " ")) + tail,
                symbol: "link")
        }
        // `someCamelName` becomes "some camel name".
        var out = ""
        for c in id where c != "." {
            if c.isUppercase { out += " " }
            out += String(c).lowercased()
        }
        let words = out.split(separator: " ").map(String.init)
        let v = verbs[words.first ?? ""]
        let rest = words.dropFirst().joined(separator: " ")
        return Op(
            did: [v?.did ?? words.first ?? id, rest].filter { !$0.isEmpty }.joined(separator: " "),
            will: [v?.will ?? words.first ?? id, rest].filter { !$0.isEmpty }.joined(separator: " "),
            symbol: "lock.shield.fill")
    }

    /// A refusal code of the Core or the script engine, as a sentence that says what happened and what it means.
    public static func refusal(_ code: String) -> String {
        switch code {
        case "rate_limited": "It made too many calls in a minute, so the Core asked it to slow down."
        case "too_many_calls": "The script ran more operations than one script may."
        case "run_timeout": "The script ran past its time limit and was stopped."
        case "timeout": "One operation took too long and was stopped."
        case "busy": "It tried too many operations at once."
        case "args_too_large": "It sent more data than one operation accepts."
        case "result_too_large": "The answer was too large to hand back."
        case "unknown_op": "It asked for an operation that does not exist."
        case "bad_args": "It sent arguments that operation does not accept."
        case "approval_denied", "denied": "You turned it down, so nothing ran."
        case "approval_timeout": "Nobody answered in time, so nothing ran."
        case "approval_closed": "The question was already closed, so nothing ran."
        case "outcome_unknown": "The Core restarted while it waited. Nothing was run, and it will not run later."
        case "unknown_session": "This AI session is no longer running."
        case "unavailable": "The Core could not answer. Trying again is safe."
        case "not_exposed": "That operation is never offered to AI sessions."
        default: "The Core refused it (\(code))."
        }
    }
}
