import Foundation

/// A folder of exported chats (E5-4). One reader per exporter, picked by the shape of the file, never by its
/// name alone:
/// - ChatGPT export, `conversations.json` (or `conversations-000.json`...): an array of
///   `{title, create_time, mapping: {id: {parent, message: {author: {role}, content: {parts}}}}, current_node}`;
///   the turns are the chain from `current_node` back to the root, so edited-away branches are not imported.
/// - Claude.ai export, `conversations.json`: an array of
///   `{uuid, name, created_at, chat_messages: [{sender: "human"|"assistant", text, created_at}]}`.
/// Other files in the folder (`users.json`, `projects.json`, `message_feedback.json`, images) are never read.
/// A `.zip` is reported, not opened: unpack it first. The whole JSON file is loaded, which is why a file over
/// `maxFileBytes` is skipped (ponytail: stream with a JSON tokenizer if exports outgrow that).
public struct ChatExportCollector: FileCollector {
    public static let maxFileBytes: UInt64 = 256 << 20
    public let device: String
    public let files: any FileAccess

    public init(device: String, files: any FileAccess = DiskFiles()) {
        self.device = device
        self.files = files
    }

    static func isConversationFile(_ u: URL) -> Bool {
        let n = u.lastPathComponent.lowercased()
        return n.hasPrefix("conversations") && n.hasSuffix(".json")
    }

    public func accepts(_ url: URL) -> Bool { Self.isConversationFile(url) || url.pathExtension.lowercased() == "zip" }

    public func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String? {
        if url.pathExtension.lowercased() == "zip" { return "zip" }
        if files.size(of: url) > Self.maxFileBytes { return "too-big" }
        var data = Data()
        do {
            try await files.readLines(url, chunk: 1 << 20, maxLine: Int(Self.maxFileBytes)) {
                data.append($0)
                data.append(10)
                return true
            }
        } catch { return "unreadable" }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let head = list.first
        else { return "unknown-format" }
        let reader: (([String: Any]) -> Conversation?)
        if head["mapping"] != nil {
            reader = Self.chatGPT
        } else if head["chat_messages"] != nil {
            reader = Self.claudeAI
        } else {
            return "unknown-format"
        }
        var emitted = 0
        for raw in list {
            guard let c = reader(raw), !c.turns.isEmpty else { continue }
            var s = SessionStream(
                path: "\(url.path)#\(c.id)", device: device, gauge: nil, kind: "chat", defaultTitle: "Chat",
                startedAt: c.created, title: c.title)
            for t in c.turns {
                switch s.add(.init(timestamp: t.at, turn: (t.role, t.text))) {
                case .skip(let why): return why
                case .items(let items): for i in items { try await sink(i) }
                }
            }
            if case .items(let items) = s.finish() { for i in items { try await sink(i) } }
            emitted += s.emitted
        }
        return emitted == 0 ? "empty" : nil
    }

    struct Conversation {
        var id: String
        var title: String?
        var created: String?
        var turns: [(role: String, text: String, at: String?)]
    }

    static func epoch(_ v: Any?) -> String? {
        (v as? NSNumber).map { isoTime(Date(timeIntervalSince1970: $0.doubleValue)) }
    }

    static func chatGPT(_ c: [String: Any]) -> Conversation? {
        guard let mapping = c["mapping"] as? [String: [String: Any]] else { return nil }
        var chain: [[String: Any]] = []
        var node = c["current_node"] as? String
        var guardRail = 0
        while let id = node, let n = mapping[id], guardRail < 100_000 {
            if let m = n["message"] as? [String: Any] { chain.append(m) }
            node = n["parent"] as? String
            guardRail += 1
        }
        let turns = chain.reversed().compactMap { m -> (String, String, String?)? in
            guard let role = (m["author"] as? [String: Any])?["role"] as? String,
                role == "user" || role == "assistant",
                let content = m["content"] as? [String: Any], content["content_type"] as? String == "text",
                let parts = content["parts"] as? [Any]
            else { return nil }
            let text = parts.compactMap { $0 as? String }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (role, text, epoch(m["create_time"]))
        }
        let title = (c["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Conversation(
            id: (c["conversation_id"] as? String) ?? (c["id"] as? String) ?? title ?? "chat",
            title: title, created: epoch(c["create_time"]), turns: turns)
    }

    static func claudeAI(_ c: [String: Any]) -> Conversation? {
        guard let messages = c["chat_messages"] as? [[String: Any]] else { return nil }
        let turns = messages.compactMap { m -> (String, String, String?)? in
            guard let sender = m["sender"] as? String, sender == "human" || sender == "assistant" else { return nil }
            var text = (m["text"] as? String) ?? ""
            if text.isEmpty, let blocks = m["content"] as? [[String: Any]] {
                text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (sender == "human" ? "user" : "assistant", text, m["created_at"] as? String)
        }
        let name = (c["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Conversation(
            id: (c["uuid"] as? String) ?? name ?? "chat", title: name, created: c["created_at"] as? String,
            turns: turns)
    }
}
