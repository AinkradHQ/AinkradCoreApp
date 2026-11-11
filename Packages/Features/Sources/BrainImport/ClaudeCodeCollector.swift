import Foundation

/// Reads files for a collector. Injected so a test can prove which files were opened.
public protocol FileAccess: Sendable {
    func listFiles(under root: URL) -> [URL]
    func read(_ url: URL) throws -> Data
}

public struct DiskFiles: FileAccess {
    public init() {}
    public func listFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return e.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
}

/// Claude Code sessions: `<root>/<encoded project dir>/<session>.jsonl`, one JSON record per line.
/// One session becomes one item (or ordered parts when it is large): the user and assistant text,
/// with tool output trimmed. Records of an unknown shape are skipped, never guessed at.
public struct ClaudeCodeCollector: Sendable {
    public let device: String
    public let files: any FileAccess
    /// Tool output longer than this many characters is cut.
    public static let toolOutputLimit = 400

    public init(device: String, files: any FileAccess = DiskFiles()) {
        self.device = device
        self.files = files
    }

    public func collect(root: URL, report: inout CollectReport) -> [ImportItem] {
        var out: [ImportItem] = []
        for url in files.listFiles(under: root).sorted(by: { $0.path < $1.path }) where url.pathExtension == "jsonl" {
            report.found += 1
            // Decided by the path alone, before the file is opened.
            if let why = PreFilter.skipReason(path: url.path.replacingOccurrences(of: root.path, with: "")) {
                report.skipped[why, default: 0] += 1
                continue
            }
            guard let data = try? files.read(url) else {
                report.skipped["unreadable", default: 0] += 1
                continue
            }
            switch parse(data, path: url.path) {
            case .skip(let why): report.skipped[why, default: 0] += 1
            case .items(let items):
                report.items += items.count
                out += items
            }
        }
        return out
    }

    enum Parsed {
        case items([ImportItem])
        case skip(String)
    }

    func parse(_ data: Data, path: String) -> Parsed {
        var cwd: String?
        var first: String?
        var last: String?
        var lines: [String] = []
        var title: String?
        for raw in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8))
            guard let obj = json as? [String: Any] else { continue }
            if cwd == nil, let c = obj["cwd"] as? String { cwd = c }
            if let t = obj["timestamp"] as? String {
                if first == nil { first = t }
                last = t
            }
            guard let type = obj["type"] as? String, type == "user" || type == "assistant",
                let message = obj["message"] as? [String: Any]
            else { continue }
            let text = Self.text(of: message["content"])
            guard !text.isEmpty else { continue }
            if title == nil, type == "user" { title = text }
            lines.append("\(type == "user" ? "User" : "Assistant"): \(text)")
        }
        // The working directory is only known after reading; a deprecated project still stops here.
        if let cwd, let p = PreFilter.deprecatedProject(in: cwd) { return .skip("deprecated:\(p)") }
        if let cwd, PreFilter.isRestricted(cwd) { return .skip("restricted") }
        guard let first, !lines.isEmpty else { return .skip("empty") }
        let body = lines.joined(separator: "\n\n")
        let parts = ItemFormat.split(body)
        let headline = String((title ?? "Claude Code session").split(separator: "\n").first ?? "").prefix(80)
        let items = parts.enumerated().map { i, part in
            ImportItem(
                item_id: ItemFormat.itemID(seed: "\(path)#\(i)"),
                source_kind: "claude_code",
                content_hash: ItemFormat.hash(part),
                origin: .init(
                    device: device, path: path,
                    range: parts.count > 1 ? [UInt64(i), UInt64(parts.count)] : nil),
                project_hint: cwd,
                author: .init(kind: "person", name: "me"),
                title: parts.count > 1 ? "\(headline) (part \(i + 1) of \(parts.count))" : String(headline),
                text: part, links: [], started_at: first, ended_at: last == first ? nil : last)
        }
        return .items(items)
    }

    static func text(of content: Any?) -> String {
        if let s = content as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for b in blocks {
            switch b["type"] as? String {
            case "text": if let t = b["text"] as? String { parts.append(t) }
            case "tool_result":
                let nested = (b["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }
                let raw = (b["content"] as? String) ?? nested?.joined(separator: "\n") ?? ""
                parts.append("[tool output] " + trim(raw))
            default: break  // tool calls, thinking and images are not kept
            }
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trim(_ s: String) -> String {
        s.count > toolOutputLimit ? String(s.prefix(toolOutputLimit)) + " [trimmed]" : s
    }
}
