import BrainImport
import Foundation

/// A folder read file by file through one `FileCollector`: Codex, Cursor, the Markdown kinds, chat exports.
public struct FolderSource: ImportSource {
    public let id: String
    public let title: String
    let root: URL
    let collector: any FileCollector

    public init(id: String, title: String, root: URL, collector: any FileCollector) {
        self.id = id
        self.title = title
        self.root = root
        self.collector = collector
    }

    public func scan() async -> CollectReport {
        var report = CollectReport()
        let zstd = DiskFiles.zstdPath != nil
        for url in collector.candidates(under: root) {
            report.found += 1
            if let why = PreFilter.skipReason(path: url.path.replacingOccurrences(of: root.path, with: "")) {
                report.skipped[why, default: 0] += 1
            } else if url.pathExtension == "zst", !zstd {
                report.skipped["needs-zstd", default: 0] += 1
            }
        }
        return report
    }

    public var incremental: Bool { true }
    public func newCount(since: Date?) async -> Int {
        guard let since else { return 0 }
        return collector.candidates(under: root).filter {
            (collector.files.modified(of: $0) ?? .distantPast) > since
                && PreFilter.skipReason(path: $0.path.replacingOccurrences(of: root.path, with: "")) == nil
        }.count
    }
    public func streamNew(
        since: Date?, run: String, uploader: Uploader, uploaded: Uploader.Progress
    ) async throws -> CollectReport {
        try await ImportStreamer(collector: collector, uploader: uploader).run(
            root: root, runID: run, resume: .init(), uploaded: uploaded, since: since, save: { _ in },
            onProgress: { _ in })
    }

    public func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        try await ImportStreamer(collector: collector, uploader: uploader).run(
            root: root, runID: run, resume: resume, uploaded: uploaded, save: save, onProgress: onProgress)
    }
}

/// OpenCode's database: one unit per session, so a restart skips the sessions already sent.
public struct OpenCodeSource: ImportSource {
    public let id = "opencode"
    public let title = "OpenCode sessions"
    let collector: OpenCodeCollector

    public init(device: String, dbPath: String) { collector = OpenCodeCollector(device: device, dbPath: dbPath) }

    public static func standard() -> OpenCodeSource {
        OpenCodeSource(
            device: Host.current().localizedName ?? "Mac",
            dbPath: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/opencode/opencode.db")
                .path)
    }

    public func scan() async -> CollectReport { collector.scan() }

    public var incremental: Bool { true }
    static func mark(_ c: SourceCursor) -> Int64? { c.ocMessageMs ?? c.mtime.map { Int64($0 * 1000) } }
    public func newCount(cursor: SourceCursor) async -> Int {
        guard let m = Self.mark(cursor) else { return 0 }
        return collector.newCount(after: m)
    }
    public func streamNew(cursor: SourceCursor, run: String, uploader: Uploader, uploaded: Uploader.Progress)
        async throws -> CollectReport
    {
        guard let m = Self.mark(cursor) else { return CollectReport() }
        return try await collector.run(
            after: m, run: run, uploader: uploader, uploaded: uploaded, resume: .init(), save: { _ in },
            onProgress: { _ in })
    }
    public func cursorAfter(_ cursor: SourceCursor, began: Date) -> SourceCursor {
        let old = Self.mark(cursor) ?? Int64(began.timeIntervalSince1970 * 1000)
        return SourceCursor(ocMessageMs: max(old, collector.newestMessage() ?? 0))
    }

    public func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        try await collector.run(
            run: run, uploader: uploader, uploaded: uploaded, resume: resume, save: save, onProgress: onProgress)
    }
}

/// A tool whose history this app cannot read yet. Listed in step 1 with the reason; never collected.
public struct NotReadableSource: ImportSource {
    public let id: String
    public let title: String
    public let notReadable: String?
    /// Nothing of this tool is on this Mac, so its format could not even be checked.
    public let absent: Bool

    public init(id: String, title: String, reason: String, absent: Bool = false) {
        self.id = id
        self.title = title
        self.absent = absent
        self.notReadable = reason
    }

    public func scan() async -> CollectReport { CollectReport() }

    public func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        CollectReport()
    }
}

/// Every source the wizard offers on this Mac.
public enum ImportSources {
    public static var chatExportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/Chat exports")
    }

    public static func standard() -> [any ImportSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let device = Host.current().localizedName ?? "Mac"
        let projects = home.appending(path: "Home/Projects")
        func markdown(_ l: MarkdownCollector.Layout) -> MarkdownCollector { .init(layout: l, device: device) }
        return [
            ClaudeCodeSource.standard(),
            FolderSource(
                id: "codex", title: "Codex sessions", root: home.appending(path: ".codex/sessions"),
                collector: HarnessCollectors.codex(device: device)),
            OpenCodeSource.standard(),
            FolderSource(
                id: "cursor", title: "Cursor sessions", root: home.appending(path: ".cursor/projects"),
                collector: HarnessCollectors.cursor(device: device)),
            NotReadableSource(
                id: "antigravity", title: "Antigravity sessions",
                reason: "Its conversations are stored as binary records with no published format."),
            NotReadableSource(
                id: "kimi", title: "Kimi sessions",
                reason: "No Kimi history was found on this Mac, so its format could not be checked.", absent: true),
            FolderSource(id: "doc", title: "Project docs", root: projects, collector: markdown(.projectDocs)),
            FolderSource(
                id: "vault", title: "Notes vault (Ainkrad)", root: home.appending(path: "Ainkrad"),
                collector: markdown(.vault)),
            FolderSource(
                id: "agents_md", title: "AGENTS.md and CLAUDE.md files", root: projects,
                collector: markdown(.agentFiles)),
            FolderSource(
                id: "chat", title: "Chat exports", root: chatExportsFolder,
                collector: ChatExportCollector(device: device)),
        ]
    }
}
