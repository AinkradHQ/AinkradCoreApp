import Foundation
import Shell

/// Audit rows of AI sessions in words: `code_mode.call` (one operation an AI session ran through Code Mode) and `brain.ai.*`
/// (what an AI session did in the Brain). A row never holds an argument or a result, so a sentence names the operation only.
enum CodeModeAudit {
    static let areaPrefix = "code_mode."

    static func isRow(_ action: String) -> Bool { action.hasPrefix(areaPrefix) || action.hasPrefix("brain.ai.") }

    /// How one detail of a Code Mode row reads in the side panel: the operation as words, the time, the refusal as a sentence.
    /// Nil keeps the pair as the Core wrote it; an empty key drops it.
    static func plain(_ key: String, _ value: String) -> (key: String, value: String)? {
        switch key {
        case "op": return ("operation", CodeModeWords.op(value).will)
        case "ms": return ("took", "\(value) ms")
        case "code": return value == "null" ? ("", "") : ("why", CodeModeWords.refusal(value))
        default: return nil
        }
    }

    /// `An AI session in customer-portal searched the Brain`, `… was refused when it tried to create issue with Jira`.
    static func sentence(_ a: AuditItem) -> (who: String, verb: String, what: String)? {
        guard isRow(a.action) else { return nil }
        let d = (try? JSONSerialization.jsonObject(with: Data(a.details.utf8))) as? [String: Any] ?? [:]
        let who = "An AI session" + ((d["project"] as? String).map { " in \($0)" } ?? "")
        if a.action.hasPrefix("brain.ai.") {
            switch a.action.dropFirst("brain.ai.".count) {
            case "refused": return (who, "was refused", "a Brain room it may not see")
            case "proposed": return (who, "proposed", "a Brain record")
            case let other: return (who, other.replacingOccurrences(of: "_", with: " "), "in the Brain")
            }
        }
        guard let op = d["op"] as? String else { return (who, "was refused", "a call before it ran") }
        let words = CodeModeWords.op(op)
        switch d["outcome"] as? String {
        case "denied": return (who, "was refused when it tried to", words.will)
        case "error": return (who, "hit an error trying to", words.will)
        default:
            let parts = words.did.split(separator: " ", maxSplits: 1).map(String.init)
            return (who, parts.first ?? words.did, parts.count > 1 ? parts[1] : "")
        }
    }
}
