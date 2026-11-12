import Foundation

/// Collectors for the other coding-tool histories that are plain JSON lines. Each is a `LineCollector` with
/// the decoder of one format; a file in a shape that is not recognised is skipped with `unknown-format`.
public enum HarnessCollectors {
    /// Codex CLI: `~/.codex/sessions/<y>/<m>/<d>/rollout-*.jsonl` (finished ones are `.jsonl.zst`).
    /// Two shapes are known. Current: every line `{timestamp, type, payload}`, the first `session_meta`,
    /// turns are `response_item` messages. Legacy: first line `{id, timestamp}`, then flat
    /// `{type: "message", role, content}` records.
    public static func codex(
        device: String, files: any FileAccess = DiskFiles(), chunk: Int = ClaudeCodeCollector.defaultChunk,
        maxLine: Int = ClaudeCodeCollector.defaultMaxLine, gauge: BufferGauge? = nil
    ) -> LineCollector {
        LineCollector(
            device: device, files: files, chunk: chunk, maxLine: maxLine, gauge: gauge, kind: "codex",
            defaultTitle: "Codex session", strictFirst: true,
            accepts: { u in
                let n = u.lastPathComponent
                return n.hasPrefix("rollout-") && (n.hasSuffix(".jsonl") || n.hasSuffix(".jsonl.zst"))
            },
            decode: { obj, first in
                let type = obj["type"] as? String
                if first {
                    let current = type == "session_meta" && obj["payload"] is [String: Any]
                    let legacy = type == nil && obj["id"] is String && obj["timestamp"] is String
                    if !current && !legacy { return .init(skip: "unknown-format") }
                    let meta = obj["payload"] as? [String: Any]
                    return .init(cwd: meta?["cwd"] as? String, timestamp: (obj["timestamp"] as? String))
                }
                var r = SessionStream.Read(timestamp: obj["timestamp"] as? String)
                let record: [String: Any]?
                if type == "response_item" {
                    record = obj["payload"] as? [String: Any]
                } else if type == "message" {
                    record = obj
                } else {
                    record = nil
                }
                if let m = record, m["type"] as? String == "message", let role = m["role"] as? String,
                    role == "user" || role == "assistant"
                {
                    let text = codexText(m["content"])
                    if !(role == "user" && isInjected(text)) { r.turn = (role, text) }
                }
                return r
            })
    }

    static func codexText(_ content: Any?) -> String {
        if let s = content as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let blocks = (content as? [[String: Any]]) ?? []
        return blocks.compactMap { b -> String? in
            guard let t = b["type"] as? String, t == "input_text" || t == "output_text" || t == "text" else {
                return nil
            }
            return b["text"] as? String
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Codex puts the environment and the AGENTS.md text into the first user turns; that is not the person's words.
    static func isInjected(_ text: String) -> Bool {
        ["<environment_context>", "<user_instructions>", "# AGENTS.md instructions", "<permissions instructions>"]
            .contains { text.hasPrefix($0) }
    }

    /// Cursor agent transcripts: `~/.cursor/projects/<encoded project>/agent-transcripts/<id>/<id>.jsonl`,
    /// lines `{role, message: {content: [{type: "text", text}, tool_use...]}}`. There are no timestamps, so
    /// the file's modified time stands in; the project is the encoded folder name.
    public static func cursor(
        device: String, files: any FileAccess = DiskFiles(), chunk: Int = ClaudeCodeCollector.defaultChunk,
        maxLine: Int = ClaudeCodeCollector.defaultMaxLine, gauge: BufferGauge? = nil
    ) -> LineCollector {
        LineCollector(
            device: device, files: files, chunk: chunk, maxLine: maxLine, gauge: gauge, kind: "cursor",
            defaultTitle: "Cursor session", strictFirst: true, usesFileTime: true,
            hint: { url in
                let parts = url.pathComponents
                guard let i = parts.firstIndex(of: "projects"), parts.indices.contains(i + 1) else { return nil }
                return parts[i + 1]
            },
            accepts: { $0.pathExtension == "jsonl" && $0.pathComponents.contains("agent-transcripts") },
            decode: { obj, first in
                guard let role = obj["role"] as? String, let message = obj["message"] as? [String: Any] else {
                    return first ? .init(skip: "unknown-format") : .init()
                }
                var r = SessionStream.Read()
                if role == "user" || role == "assistant" {
                    r.turn = (role, cursorText(message["content"], user: role == "user"))
                }
                return r
            })
    }

    static func cursorText(_ content: Any?, user: Bool) -> String {
        let blocks = (content as? [[String: Any]]) ?? []
        var text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        if user {
            // The user's words are wrapped: `<timestamp>..</timestamp>` then `<user_query>..</user_query>`.
            text = text.replacingOccurrences(
                of: "<timestamp>.*?</timestamp>", with: "", options: [.regularExpression])
            if let a = text.range(of: "<user_query>"),
                let b = text.range(of: "</user_query>", range: a.upperBound..<text.endIndex)
            {
                text = String(text[a.upperBound..<b.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
