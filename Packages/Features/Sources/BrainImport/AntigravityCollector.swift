import Foundation
import SQLite3

/// Antigravity (`agy`) keeps one folder per conversation: `brain/<uuid>/.system_generated/logs/transcript_full.jsonl`
/// (`transcript.jsonl` when there is no full one). Lines are `{step_index, source, type, status, created_at,
/// content}`; the person's words are `USER_INPUT` steps (wrapped in `<USER_REQUEST>`), the model's are
/// `PLANNER_RESPONSE` steps with text. Tool results, system messages and checkpoints are not conversation.
///
/// `conversation_summaries.db` next to `brain/` gives the title and workspace of each conversation. It is
/// opened read-only and only that one table is read; when it is missing or locked the transcript still works.
public struct AntigravityCollector: FileCollector {
    public let files: any FileAccess
    let dbPath: String
    let inner: LineCollector

    public init(
        device: String, dbPath: String, files: any FileAccess = DiskFiles(),
        chunk: Int = ClaudeCodeCollector.defaultChunk, maxLine: Int = ClaudeCodeCollector.defaultMaxLine,
        gauge: BufferGauge? = nil
    ) {
        self.files = files
        self.dbPath = dbPath
        inner = Self.lines(
            device: device, dbPath: dbPath, files: files, chunk: chunk, maxLine: maxLine, gauge: gauge)
    }

    public func accepts(_ url: URL) -> Bool {
        let n = url.lastPathComponent
        guard url.path.contains("/.system_generated/logs/") else { return false }
        if n == "transcript_full.jsonl" { return true }
        return n == "transcript.jsonl"
            && !files.children(of: url.deletingLastPathComponent()).contains {
                $0.lastPathComponent == "transcript_full.jsonl"
            }
    }

    public func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String? {
        // The workspace is known from the summaries, not the file: refuse a refused project before opening it.
        if let w = Self.meta(dbPath: dbPath, url: url).workspace {
            if PreFilter.isRestricted(w) { return "restricted" }
            if let p = PreFilter.deprecatedProject(in: w) { return "deprecated:\(p)" }
        }
        return try await inner.stream(file: url, sink: sink)
    }

    /// `<uuid>` of `.../brain/<uuid>/.system_generated/logs/<file>`.
    static func conversationID(_ url: URL) -> String {
        url.deletingLastPathComponent().pathComponents.dropLast(2).last ?? ""
    }

    /// Title and first workspace folder of one conversation; nils when the database cannot be read.
    static func meta(dbPath: String, url: URL) -> (title: String?, workspace: String?) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return (nil, nil)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var st: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db, "SELECT title, workspace_uris FROM conversation_summaries WHERE conversation_id = ?1", -1, &st,
                nil) == SQLITE_OK
        else { return (nil, nil) }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, conversationID(url), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(st) == SQLITE_ROW else { return (nil, nil) }
        func col(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
        let title = col(0)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let uris = (col(1)?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String]
        let path = uris?.first.flatMap { URL(string: $0)?.path }
        return (title?.isEmpty == false ? title : nil, path?.isEmpty == false ? path : nil)
    }

    static func lines(
        device: String, dbPath: String, files: any FileAccess, chunk: Int, maxLine: Int, gauge: BufferGauge?
    ) -> LineCollector {
        LineCollector(
            device: device, files: files, chunk: chunk, maxLine: maxLine, gauge: gauge, kind: "antigravity",
            defaultTitle: "Antigravity session", strictFirst: true,
            hint: { meta(dbPath: dbPath, url: $0).workspace },
            titleFor: { meta(dbPath: dbPath, url: $0).title },
            accepts: { _ in true },
            decode: { obj, first in
                guard obj["step_index"] is Int, let source = obj["source"] as? String, obj["type"] is String else {
                    return first ? .init(skip: "unknown-format") : .init()
                }
                var r = SessionStream.Read(timestamp: obj["created_at"] as? String)
                guard let content = obj["content"] as? String else { return r }
                switch (source, obj["type"] as? String) {
                case ("USER_EXPLICIT", "USER_INPUT"): r.turn = ("user", userText(content))
                case ("MODEL", "PLANNER_RESPONSE"):
                    r.turn = ("assistant", content.trimmingCharacters(in: .whitespacesAndNewlines))
                default: break
                }
                return r
            })
    }

    /// The person's words are inside `<USER_REQUEST>`; metadata and settings notes follow it.
    static func userText(_ content: String) -> String {
        var t = content
        if let a = t.range(of: "<USER_REQUEST>") {
            t = String(t[a.upperBound...])
            if let b = t.range(of: "</USER_REQUEST>") { t = String(t[..<b.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
