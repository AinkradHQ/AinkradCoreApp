import Foundation
import SQLite3

/// OpenCode keeps everything in one SQLite file, `~/.local/share/opencode/opencode.db`, next to its
/// credentials. This reader opens it read-only and installs an authorizer that refuses every table except
/// `session`, `message` and `part`, so a credential row can not be read even by mistake.
///
/// Known shape (checked by column name before any row is read): `session(id, directory, title,
/// time_created, time_updated)`, `message(id, session_id, time_created, data)` with `data` JSON holding
/// `role`, `part(id, message_id, session_id, time_created, data)` with `data` JSON `{type: "text", text}` or
/// `{type: "tool", state: {output}}`. Anything else is `unknown-format`.
public struct OpenCodeReader {
    public struct SessionRow: Sendable, Equatable {
        public var id: String
        public var directory: String
        public var title: String
        public var created: Int64  // milliseconds
    }

    static let allowedTables: Set<String> = ["session", "message", "part"]
    static let required: [String: [String]] = [
        "session": ["id", "directory", "title", "time_created"],
        "message": ["id", "session_id", "time_created", "data"],
        "part": ["id", "message_id", "session_id", "time_created", "data"],
    ]

    let db: OpaquePointer

    /// Nil when the file cannot be opened.
    public init?(path: String) {
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let h else {
            sqlite3_close(h)
            return nil
        }
        sqlite3_busy_timeout(h, 2000)
        // Reads of any other table (credentials, accounts) are refused by SQLite itself.
        sqlite3_set_authorizer(
            h,
            { _, action, a, _, _, _ in
                guard action == SQLITE_READ || action == SQLITE_SELECT || action == SQLITE_FUNCTION else {
                    return action == SQLITE_PRAGMA ? SQLITE_OK : SQLITE_DENY
                }
                if action == SQLITE_READ, let a, !OpenCodeReader.allowedTables.contains(String(cString: a)) {
                    return SQLITE_DENY
                }
                return SQLITE_OK
            }, nil)
        db = h
    }

    public func close() { sqlite3_close(db) }

    /// Rows as text columns; `args` bound as text. Returns nil when the statement is refused or fails.
    func rows(_ sql: String, _ args: [String] = []) -> [[String?]]? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() {
            sqlite3_bind_text(st, Int32(i + 1), a, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var out: [[String?]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(
                (0..<sqlite3_column_count(st)).map { c in
                    sqlite3_column_text(st, c).map { String(cString: $0) }
                })
        }
        return out
    }

    /// True when the three tables have the columns this reader needs.
    public func isKnownFormat() -> Bool {
        Self.required.allSatisfy { table, columns in
            let have = Set((rows("PRAGMA table_info(\(table))") ?? []).compactMap { $0[1] })
            return columns.allSatisfy(have.contains)
        }
    }

    public func sessionCount() -> Int {
        Int(rows("SELECT count(*) FROM session")?.first?.first.flatMap { $0 } ?? "") ?? 0
    }

    public func sessions() -> [SessionRow] {
        (rows("SELECT id, directory, title, time_created FROM session ORDER BY time_created, id") ?? []).compactMap {
            guard let id = $0[0] else { return nil }
            return SessionRow(id: id, directory: $0[1] ?? "", title: $0[2] ?? "", created: Int64($0[3] ?? "") ?? 0)
        }
    }

    /// The newest message time (ms); nil when there is none.
    public func newestMessage() -> Int64? {
        rows("SELECT max(time_created) FROM message")?.first?.first.flatMap { $0 }.flatMap { Int64($0) }
    }

    /// Ids of the sessions with a message newer than `after` (ms).
    public func sessions(withMessagesAfter after: Int64) -> Set<String> {
        Set(
            (rows("SELECT DISTINCT session_id FROM message WHERE time_created > CAST(?1 AS INTEGER)", ["\(after)"])
                ?? [])
                .compactMap { $0[0] })
    }

    /// The session's turns in order, tool output trimmed like Claude Code's. `after`: only messages newer than it (ms).
    public func turns(of session: String, after: Int64? = nil) -> [(role: String, text: String, at: Int64)] {
        var out: [(String, String, Int64)] = []
        let messages =
            rows(
                "SELECT id, time_created, json_extract(data, '$.role') FROM message WHERE session_id = ?1 AND time_created > CAST(?2 AS INTEGER) ORDER BY time_created, id",
                [session, "\(after ?? Int64.min)"]) ?? []
        for m in messages {
            guard let id = m[0], let role = m[2], role == "user" || role == "assistant" else { continue }
            var texts: [String] = []
            let parts =
                rows(
                    "SELECT json_extract(data, '$.type'), json_extract(data, '$.text'), json_extract(data, '$.state.output') FROM part WHERE message_id = ?1 ORDER BY id",
                    [id]) ?? []
            for p in parts {
                if p[0] == "text", let t = p[1] {
                    texts.append(t)
                } else if p[0] == "tool", let o = p[2] {
                    texts.append("[tool output] " + ClaudeCodeCollector.trim(o))
                }
            }
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append((role, text, Int64(m[1] ?? "") ?? 0)) }
        }
        return out
    }
}

/// Turns one OpenCode session into items, the same way a Claude Code file is.
public struct OpenCodeCollector: Sendable {
    public let device: String
    public let dbPath: String

    public init(device: String, dbPath: String) {
        self.device = device
        self.dbPath = dbPath
    }

    static func iso(_ ms: Int64) -> String { isoTime(Date(timeIntervalSince1970: Double(ms) / 1000)) }

    /// Returns the skip reason, or nil.
    public func stream(
        session: OpenCodeReader.SessionRow, reader: OpenCodeReader, after: Int64? = nil,
        sink: (ImportItem) async throws -> Void
    ) async throws -> String? {
        let turns = reader.turns(of: session.id, after: after)
        var s = SessionStream(
            path: "\(dbPath)#\(session.id)", device: device, gauge: nil, kind: "opencode",
            defaultTitle: "OpenCode session",
            startedAt: session.created > 0 ? Self.iso(session.created) : nil,
            title: session.title.isEmpty ? nil : session.title)
        var read = SessionStream.Read(cwd: session.directory.isEmpty ? nil : session.directory)
        for t in turns {
            read.turn = (t.role, t.text)
            read.timestamp = Self.iso(t.at)
            switch s.add(read) {
            case .skip(let why): return why
            case .items(let items): for i in items { try await sink(i) }
            }
            read.cwd = nil
        }
        if case .items(let items) = s.finish() { for i in items { try await sink(i) } }
        return s.emitted == 0 ? "empty" : nil
    }
}

extension OpenCodeCollector {
    /// What the database holds, from the session table alone.
    public func scan() -> CollectReport {
        var report = CollectReport()
        guard FileManager.default.fileExists(atPath: dbPath) else { return report }
        guard let reader = OpenCodeReader(path: dbPath) else {
            report.skipped["unreadable"] = 1
            return report
        }
        defer { reader.close() }
        guard reader.isKnownFormat() else {
            report.skipped["unknown-format"] = 1
            return report
        }
        for s in reader.sessions() {
            report.found += 1
            if let why = PreFilter.skipReason(path: s.directory) { report.skipped[why, default: 0] += 1 }
        }
        return report
    }

    /// How many sessions have messages newer than `after` (ms) and pass the folder rule; 0 when the file is unknown.
    public func newCount(after: Int64) -> Int {
        guard FileManager.default.fileExists(atPath: dbPath), let reader = OpenCodeReader(path: dbPath) else {
            return 0
        }
        defer { reader.close() }
        guard reader.isKnownFormat() else { return 0 }
        let fresh = reader.sessions(withMessagesAfter: after)
        return reader.sessions().filter { fresh.contains($0.id) && PreFilter.skipReason(path: $0.directory) == nil }
            .count
    }

    public func newestMessage() -> Int64? {
        guard let reader = OpenCodeReader(path: dbPath) else { return nil }
        defer { reader.close() }
        return reader.isKnownFormat() ? reader.newestMessage() : nil
    }

    /// `after`: an incremental run, only the messages newer than it (ms), only in the sessions that have any.
    public func run(
        after: Int64? = nil, run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        var report = CollectReport()
        guard FileManager.default.fileExists(atPath: dbPath) else { return report }
        guard let reader = OpenCodeReader(path: dbPath) else {
            report.skipped["unreadable"] = 1
            return report
        }
        defer { reader.close() }
        guard reader.isKnownFormat() else {
            report.skipped["unknown-format"] = 1
            return report
        }
        var rows: [String: OpenCodeReader.SessionRow] = [:]
        var units: [ImportStreamer.Unit] = []
        let fresh = after.map { reader.sessions(withMessagesAfter: $0) }
        for s in reader.sessions() {
            if let fresh, !fresh.contains(s.id) { continue }
            report.found += 1
            // Decided by the folder alone, before a message is read.
            if let why = PreFilter.skipReason(path: s.directory) {
                report.skipped[why, default: 0] += 1
                continue
            }
            rows[s.id] = s
            // ponytail: progress counts sessions, not bytes; sizing needs a scan of the 1 GB part table.
            units.append(.init(key: s.id, size: 1))
        }
        return try await ImportStreamer(collector: nil, uploader: uploader).run(
            units: units, report: report, runID: run, resume: resume, uploaded: uploaded, save: save,
            onProgress: onProgress
        ) { unit, sink in
            guard let row = rows[unit.key] else { return "unreadable" }
            return try await stream(session: row, reader: reader, after: after, sink: sink)
        }
    }
}
