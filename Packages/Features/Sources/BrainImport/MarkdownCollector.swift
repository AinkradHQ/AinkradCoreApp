import Foundation

/// Markdown files: project `Docs/` folders, the Obsidian vault, `AGENTS.md` / `CLAUDE.md`. One file is one item
/// (ordered parts when it is large). The text is kept exactly as written, front matter included: whatever
/// instructions a file contains are data to store, never something this code acts on. Wikilinks and relative
/// markdown links become the item's `links`.
public struct MarkdownCollector: FileCollector {
    public enum Layout: Sendable {
        /// `<root>/<project>/Docs/**.md`
        case projectDocs
        /// every `.md` under the root, hidden folders (`.obsidian`, `.git`) left out
        case vault
        /// `AGENTS.md` / `CLAUDE.md` in `<root>/<project>` and `<root>/<project>/Repositories/<repo>`
        case agentFiles
    }

    /// A file bigger than this is not read: it is a data dump, not a note.
    public static let maxFileBytes = 2 << 20

    public let device: String
    public let files: any FileAccess
    public let layout: Layout
    public let kind: String

    public init(layout: Layout, device: String, files: any FileAccess = DiskFiles()) {
        self.layout = layout
        self.device = device
        self.files = files
        switch layout {
        case .projectDocs: kind = "doc"
        case .vault: kind = "vault"
        case .agentFiles: kind = "agents_md"
        }
    }

    static func isMarkdown(_ u: URL) -> Bool { ["md", "markdown"].contains(u.pathExtension.lowercased()) }
    static func isAgentFile(_ u: URL) -> Bool { ["AGENTS.md", "CLAUDE.md"].contains(u.lastPathComponent) }

    public func accepts(_ url: URL) -> Bool { layout == .agentFiles ? Self.isAgentFile(url) : Self.isMarkdown(url) }

    public func candidates(under root: URL) -> [URL] {
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        func visible(_ u: URL) -> Bool { !u.lastPathComponent.hasPrefix(".") }
        switch layout {
        case .vault:
            return files.listFiles(under: root).filter {
                accepts($0)
                    && !$0.path.dropFirst(root.path.count).split(separator: "/").contains {
                        $0.hasPrefix(".")
                    }
            }
        case .projectDocs:
            return files.children(of: root).filter { isDir($0) && visible($0) }.flatMap {
                files.listFiles(under: $0.appending(path: "Docs", directoryHint: .isDirectory)).filter(accepts)
            }
        case .agentFiles:
            let projects = files.children(of: root).filter { isDir($0) && visible($0) }
            let repos = projects.flatMap { files.children(of: $0.appending(path: "Repositories")).filter(isDir) }
            return (projects + repos).flatMap { files.children(of: $0).filter(accepts) }
        }
    }

    public func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String? {
        var text = ""
        var tooBig = false
        do {
            try await files.readLines(url, chunk: 1 << 16, maxLine: Self.maxFileBytes) { line in
                text += (text.isEmpty ? "" : "\n") + String(decoding: line, as: UTF8.self)
                tooBig = text.utf8.count > Self.maxFileBytes
                return !tooBig
            }
        } catch { return "unreadable" }
        if tooBig { return "too-big" }
        let body = ItemFormat.normalize(text)
        guard !body.isEmpty else { return "empty" }
        let parts = ItemFormat.split(body)
        let (front, _) = Self.frontMatter(body)
        let title = front["title"] ?? Self.heading(body) ?? url.deletingPathExtension().lastPathComponent
        let when = isoTime(files.modified(of: url) ?? Date(timeIntervalSince1970: 0))
        let links = Self.links(in: body)
        for (i, part) in parts.enumerated() {
            try await sink(
                ImportItem(
                    item_id: ItemFormat.itemID(seed: "\(url.path)#\(i)"), source_kind: kind,
                    content_hash: ItemFormat.hash(part),
                    origin: .init(device: device, path: url.path, range: parts.count > 1 ? [UInt64(i), 0] : nil),
                    project_hint: nil, author: .init(kind: "person", name: "me"),
                    title: parts.count > 1 ? "\(title) (part \(i + 1))" : title, text: part, links: links,
                    started_at: when, ended_at: nil))
        }
        return nil
    }

    /// `key: value` lines between a leading `---` pair. Values are plain text; nothing is evaluated.
    static func frontMatter(_ text: String) -> (fields: [String: String], rest: Substring) {
        guard text.hasPrefix("---\n") else { return ([:], text[...]) }
        let afterOpen = text.index(text.startIndex, offsetBy: 4)
        guard let close = text.range(of: "\n---", range: afterOpen..<text.endIndex) else { return ([:], text[...]) }
        var fields: [String: String] = [:]
        for l in text[afterOpen..<close.lowerBound].split(separator: "\n") {
            guard let c = l.firstIndex(of: ":"), !l.hasPrefix(" ") else { continue }
            let v = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
            fields[String(l[..<c]).lowercased()] = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return (fields, text[close.upperBound...])
    }

    static func heading(_ text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)).prefix(120).description }
    }

    /// Wikilink targets (`[[Note|alias]]` and `[[Note#Heading]]` give `Note`) and relative `.md` link targets,
    /// in order of first appearance, front matter included.
    static func links(in text: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, seen.insert(t).inserted { out.append(t) }
        }
        for m in text.matches(of: /\[\[([^\]\n]+)\]\]/) {
            add(String(m.1.split(whereSeparator: { $0 == "|" || $0 == "#" }).first ?? ""))
        }
        for m in text.matches(of: /\]\(([^)\s#]+\.md)(?:#[^)]*)?\)/) where !m.1.contains("://") { add(String(m.1)) }
        return out
    }
}
