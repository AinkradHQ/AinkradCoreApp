import Foundation
import SQLite3
import Testing

@testable import BrainImport

/// Runs the real streamer with any collector over `root`.
func gather(_ root: URL, collector: any FileCollector) async throws -> (items: [ImportItem], report: CollectReport) {
    let rec = Recorder()
    let streamer = ImportStreamer(
        collector: collector, uploader: Uploader(transport: rec, retries: 0, pause: { _ in }))
    let report = try await streamer.run(
        root: root, runID: "r", resume: .init(), uploaded: .init(), save: { _ in }, onProgress: { _ in })
    return (rec.items, report)
}

func jsonl(_ lines: [String]) -> String { lines.joined(separator: "\n") }

@Suite struct HarnessCollectorTests {
    // MARK: Codex

    static let codexCurrent = jsonl([
        #"{"timestamp":"2026-09-15T10:00:00Z","ordinal":0,"type":"session_meta","payload":{"id":"s1","cwd":"/synthetic/work/alpha","cli_version":"9.9"}}"#,
        #"{"timestamp":"2026-09-15T10:00:01Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"system rules"}]}}"#,
        #"{"timestamp":"2026-09-15T10:00:02Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}"#,
        #"{"timestamp":"2026-09-15T10:00:03Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix the parser"}]}}"#,
        #"{"timestamp":"2026-09-15T10:00:04Z","type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
        #"{"timestamp":"2026-09-15T10:00:05Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done, see KAN-12"}]}}"#,
        #"{"timestamp":"2026-09-15T10:00:06Z","type":"event_msg","payload":{"type":"token_count"}}"#,
    ])

    @Test func codexCurrentFormatNormalisesExactly() async throws {
        let root = try fixtureRoot()
        try write(root, "2026/09/15/rollout-2026-09-15T10-00-00-aaa.jsonl", Self.codexCurrent)
        let (items, report) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
        #expect(items.count == 1)
        let i = items[0]
        #expect(i.source_kind == "codex")
        #expect(i.text == "User: Fix the parser\n\nAssistant: Done, see KAN-12")
        #expect(i.title == "Fix the parser" && i.project_hint == "/synthetic/work/alpha")
        #expect(i.started_at == "2026-09-15T10:00:00Z" && i.ended_at == "2026-09-15T10:00:06Z")
        #expect(report.found == 1 && report.items == 1 && report.skipped.isEmpty)
    }

    @Test func codexLegacyFormatIsRead() async throws {
        let root = try fixtureRoot()
        try write(
            root, "2025/05/01/rollout-2025-05-01T10-00-00-bbb.jsonl",
            jsonl([
                #"{"id":"s0","timestamp":"2025-05-01T10:00:00Z","instructions":"x"}"#,
                #"{"type":"message","role":"user","content":[{"type":"input_text","text":"Old question"}]}"#,
                #"{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Old answer"}]}"#,
            ]))
        let (items, _) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
        #expect(items.first?.text == "User: Old question\n\nAssistant: Old answer")
        #expect(items.first?.project_hint == nil)
    }

    @Test func codexUnknownFormatIsSkippedWithAReason() async throws {
        let root = try fixtureRoot()
        try write(root, "rollout-future.jsonl", #"{"v":3,"kind":"envelope","records":[]}"#)
        try write(root, "rollout-bin.jsonl", "not json at all")
        let (items, report) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
        #expect(items.isEmpty && report.skipped["unknown-format"] == 2)
    }

    @Test func codexDeprecatedWorkingDirectoryIsSkipped() async throws {
        let root = try fixtureRoot()
        try write(
            root, "rollout-x.jsonl",
            #"{"timestamp":"2026-09-15T10:00:00Z","type":"session_meta","payload":{"cwd":"/Users/x/Projects/GitScope"}}"#
                + "\n"
                + #"{"timestamp":"2026-09-15T10:00:03Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"old"}]}}"#
        )
        let (items, report) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
        #expect(items.isEmpty && report.skipped["deprecated:GitScope"] == 1)
    }

    @Test func codexZstdFilesAreReadWhenTheToolExistsAndReportedWhenNot() async throws {
        let root = try fixtureRoot()
        try write(root, "plain.jsonl", Self.codexCurrent)
        guard let tool = DiskFiles.zstdPath else {
            try write(root, "2026/rollout-z.jsonl.zst", "bytes")
            let (items, report) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
            #expect(items.isEmpty && report.skipped["needs-zstd"] == 1)
            return
        }
        let src = root.appendingPathComponent("rollout-z.jsonl")
        try Self.codexCurrent.write(to: src, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-q", "--rm", src.path]
        try p.run()
        p.waitUntilExit()
        let (items, _) = try await gather(root, collector: HarnessCollectors.codex(device: "mac-1"))
        #expect(items.count == 1 && items[0].text.contains("Fix the parser"))
    }

    // MARK: Cursor

    @Test func cursorTranscriptNormalisesExactly() async throws {
        let root = try fixtureRoot()
        let rel = "Users-synthetic-Work-alpha/agent-transcripts/c1/c1.jsonl"
        try write(
            root, rel,
            jsonl([
                #"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Sunday, Sep 20, 2026</timestamp>\n<user_query>\nWhy is the scan slow?\n</user_query>"}]}}"#,
                #"{"role":"assistant","message":{"content":[{"type":"text","text":"Checking."},{"type":"tool_use","name":"Read","input":{"path":"/x"}}]}}"#,
                #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}"#,
            ]))
        let (items, report) = try await gather(root, collector: HarnessCollectors.cursor(device: "mac-1"))
        #expect(items.count == 1)
        let i = items[0]
        #expect(i.source_kind == "cursor" && i.text == "User: Why is the scan slow?\n\nAssistant: Checking.")
        #expect(i.title == "Why is the scan slow?")
        #expect(report.found == 1 && !i.started_at.isEmpty)
    }

    @Test func cursorProjectHintComesFromTheProjectFolder() async throws {
        let root = try fixtureRoot().appendingPathComponent("projects")
        try write(
            root, "Users-synthetic-Work-alpha/agent-transcripts/c1/c1.jsonl",
            #"{"role":"user","message":{"content":[{"type":"text","text":"hi"}]}}"#)
        let (items, _) = try await gather(root, collector: HarnessCollectors.cursor(device: "mac-1"))
        #expect(items.first?.project_hint == "Users-synthetic-Work-alpha")
    }

    @Test func cursorUnknownFormatIsSkipped() async throws {
        let root = try fixtureRoot()
        try write(root, "p/agent-transcripts/c/c.jsonl", #"{"v":2,"events":[]}"#)
        let (items, report) = try await gather(root, collector: HarnessCollectors.cursor(device: "mac-1"))
        #expect(items.isEmpty && report.skipped["unknown-format"] == 1)
    }

    // MARK: OpenCode

    func makeDB(_ statements: [String]) throws -> String {
        let path = try fixtureRoot().appendingPathComponent("opencode.db").path
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for s in statements { #expect(sqlite3_exec(db, s, nil, nil, nil) == SQLITE_OK, "\(s)") }
        return path
    }

    static let schema = [
        "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, time_created INTEGER)",
        "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)",
        "CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, data TEXT)",
        "CREATE TABLE credential (id TEXT, secret TEXT)",
        "INSERT INTO credential VALUES ('c1', 'CANARY-SECRET-123')",
    ]

    func opencodeItems(_ path: String) async throws -> (items: [ImportItem], report: CollectReport) {
        let rec = Recorder()
        let report = try await OpenCodeCollector(device: "mac-1", dbPath: path).run(
            run: "r", uploader: Uploader(transport: rec, retries: 0, pause: { _ in }), uploaded: .init(),
            resume: .init(), save: { _ in }, onProgress: { _ in })
        return (rec.items, report)
    }

    @Test func opencodeSessionNormalisesAndNeverReadsCredentials() async throws {
        let path = try makeDB(
            Self.schema + [
                "INSERT INTO session VALUES ('ses_1', '/synthetic/work/alpha', 'Parser fix', 1788000000000)",
                "INSERT INTO session VALUES ('ses_2', '/Users/x/Projects/Habtic', 'Old', 1788000100000)",
                #"INSERT INTO message VALUES ('m1','ses_1',1788000001000,'{"role":"user"}')"#,
                #"INSERT INTO message VALUES ('m2','ses_1',1788000002000,'{"role":"assistant"}')"#,
                #"INSERT INTO part VALUES ('p1','m1','ses_1',1788000001000,'{"type":"text","text":"Fix the parser"}')"#,
                #"INSERT INTO part VALUES ('p2','m2','ses_1',1788000002000,'{"type":"step-start"}')"#,
                #"INSERT INTO part VALUES ('p3','m2','ses_1',1788000002000,'{"type":"text","text":"Done"}')"#,
                #"INSERT INTO part VALUES ('p4','m2','ses_1',1788000002000,'{"type":"tool","state":{"output":"ok"}}')"#,
            ])
        let (items, report) = try await opencodeItems(path)
        #expect(items.count == 1)
        let i = items[0]
        #expect(i.source_kind == "opencode" && i.title == "Parser fix" && i.project_hint == "/synthetic/work/alpha")
        #expect(i.text == "User: Fix the parser\n\nAssistant: Done\n[tool output] ok")
        #expect(i.origin.path.hasSuffix("opencode.db#ses_1"))
        #expect(report.found == 2 && report.items == 1 && report.skipped["deprecated:Habtic"] == 1)
        #expect(!items.map(\.text).joined().contains("CANARY"))
        // SQLite itself refuses any other table.
        let reader = try #require(OpenCodeReader(path: path))
        defer { reader.close() }
        #expect(reader.rows("SELECT secret FROM credential") == nil)
        #expect(reader.rows("SELECT count(*) FROM session") != nil)
    }

    @Test func opencodeUnknownShapeIsSkippedWithAReason() async throws {
        let path = try makeDB(["CREATE TABLE session (id TEXT, cwd TEXT)", "CREATE TABLE message (id TEXT)"])
        let (items, report) = try await opencodeItems(path)
        #expect(items.isEmpty && report.skipped["unknown-format"] == 1)
    }

    @Test func opencodeResumesAtTheSessionNotYetSent() async throws {
        let path = try makeDB(
            Self.schema + [
                "INSERT INTO session VALUES ('a', '/s/a', 'A', 1788000000000)",
                "INSERT INTO session VALUES ('b', '/s/b', 'B', 1788000100000)",
                #"INSERT INTO message VALUES ('m1','a',1788000001000,'{"role":"user"}')"#,
                #"INSERT INTO message VALUES ('m2','b',1788000101000,'{"role":"user"}')"#,
                #"INSERT INTO part VALUES ('p1','m1','a',1,'{"type":"text","text":"one"}')"#,
                #"INSERT INTO part VALUES ('p2','m2','b',1,'{"type":"text","text":"two"}')"#,
            ])
        let rec = Recorder()
        let report = try await OpenCodeCollector(device: "mac-1", dbPath: path).run(
            run: "r", uploader: Uploader(transport: rec, retries: 0, pause: { _ in }), uploaded: .init(),
            resume: SourceResume(done: ["a"], items: 1), save: { _ in }, onProgress: { _ in })
        #expect(rec.items.map(\.title) == ["B"] && report.items == 2)
    }

    // MARK: OpenCode incremental

    func newRun(_ path: String, after: Int64?) async throws -> (items: [ImportItem], report: CollectReport) {
        let rec = Recorder()
        let report = try await OpenCodeCollector(device: "mac-1", dbPath: path).run(
            after: after, run: "r", uploader: Uploader(transport: rec, retries: 0, pause: { _ in }), uploaded: .init(),
            resume: .init(), save: { _ in }, onProgress: { _ in })
        return (rec.items, report)
    }

    static let twoSessions =
        Self.schema + [
            "INSERT INTO session VALUES ('a', '/s/a', 'A', 1788000000000)",
            "INSERT INTO session VALUES ('b', '/s/b', 'B', 1788000100000)",
            #"INSERT INTO message VALUES ('m1','a',1788000001000,'{"role":"user"}')"#,
            #"INSERT INTO message VALUES ('m2','b',1788000101000,'{"role":"user"}')"#,
            #"INSERT INTO part VALUES ('p1','m1','a',1,'{"type":"text","text":"one"}')"#,
            #"INSERT INTO part VALUES ('p2','m2','b',1,'{"type":"text","text":"two"}')"#,
        ]

    @Test func opencodeIncrementalFirstThenNothingThenOnlyTheNewMessage() async throws {
        let path = try makeDB(Self.twoSessions)
        let c = OpenCodeCollector(device: "mac-1", dbPath: path)
        // First run: no mark, everything; the newest message time becomes the cursor.
        #expect(try await newRun(path, after: nil).items.count == 2)
        let mark = try #require(c.newestMessage())
        #expect(mark == 1_788_000_101_000)
        // Second run: nothing newer.
        #expect(c.newCount(after: mark) == 0)
        #expect(try await newRun(path, after: mark).items.isEmpty)
        // A new message in the old session 'a': only that message, and only that session.
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        for q in [
            #"INSERT INTO message VALUES ('m3','a',1788000200000,'{"role":"assistant"}')"#,
            #"INSERT INTO part VALUES ('p3','m3','a',1,'{"type":"text","text":"later"}')"#,
        ] { #expect(sqlite3_exec(db, q, nil, nil, nil) == SQLITE_OK) }
        sqlite3_close(db)
        #expect(c.newCount(after: mark) == 1)
        let (items, report) = try await newRun(path, after: mark)
        #expect(items.count == 1 && items[0].title == "A" && report.found == 1)
        #expect(items[0].text.contains("later") && !items[0].text.contains("one"))
        #expect(!items[0].text.contains("CANARY"))
    }

    @Test func opencodeIncrementalSkipsAnUnknownSchema() async throws {
        let path = try makeDB(["CREATE TABLE session (id TEXT, cwd TEXT)", "CREATE TABLE message (id TEXT)"])
        let c = OpenCodeCollector(device: "mac-1", dbPath: path)
        #expect(c.newCount(after: 0) == 0 && c.newestMessage() == nil)
        let (items, report) = try await newRun(path, after: 0)
        #expect(items.isEmpty && report.skipped["unknown-format"] == 1)
    }
}
