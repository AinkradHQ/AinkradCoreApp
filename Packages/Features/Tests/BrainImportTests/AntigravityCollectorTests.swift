import Foundation
import SQLite3
import Testing

@testable import BrainImport

@Suite struct AntigravityCollectorTests {
    static func step(_ i: Int, _ source: String, _ type: String, _ content: String?, at t: String) -> String {
        let c = content.map { #","content":"\#($0)""# } ?? ""
        return
            #"{"step_index":\#(i),"source":"\#(source)","type":"\#(type)","status":"DONE","created_at":"\#(t)"\#(c)}"#
    }

    static let transcript = jsonl([
        step(
            0, "USER_EXPLICIT", "USER_INPUT",
            "<USER_REQUEST>\\nAdd a retry\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>x</ADDITIONAL_METADATA>",
            at: "2026-10-01T09:00:00Z"),
        step(1, "SYSTEM", "SYSTEM_MESSAGE", "system noise", at: "2026-10-01T09:00:01Z"),
        "{this is not json",
        step(2, "MODEL", "GENERIC", "Created file a.txt", at: "2026-10-01T09:00:02Z"),
        #"{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-01T09:00:03Z","tool_calls":[{"name":"run","args":{}}]}"#,
        step(4, "MODEL", "PLANNER_RESPONSE", "Retry added.", at: "2026-10-01T09:00:04Z"),
    ])

    func db(_ root: URL, _ rows: [String]) throws -> String {
        let path = root.appendingPathComponent("conversation_summaries.db").path
        var h: OpaquePointer?
        #expect(sqlite3_open(path, &h) == SQLITE_OK)
        defer { sqlite3_close(h) }
        let all = ["CREATE TABLE conversation_summaries (conversation_id TEXT, title TEXT, workspace_uris TEXT)"] + rows
        for s in all { #expect(sqlite3_exec(h, s, nil, nil, nil) == SQLITE_OK) }
        return path
    }

    func log(_ id: String, _ name: String = "transcript_full.jsonl") -> String {
        "brain/\(id)/.system_generated/logs/\(name)"
    }

    @Test func userAndModelTextBecomeTurnsWithTitleAndWorkspaceFromTheDatabase() async throws {
        let root = try fixtureRoot()
        try write(root, log("c1"), Self.transcript)
        try write(root, log("c1", "transcript.jsonl"), "ignored: the full one wins")
        let path = try db(
            root, [#"INSERT INTO conversation_summaries VALUES ('c1','Retry work','["file:///synthetic/work/alpha"]')"#]
        )
        let (items, report) = try await gather(
            root.appendingPathComponent("brain"), collector: AntigravityCollector(device: "mac-1", dbPath: path))
        #expect(items.count == 1)
        let i = items[0]
        #expect(i.source_kind == "antigravity" && i.title == "Retry work" && i.project_hint == "/synthetic/work/alpha")
        #expect(i.text == "User: Add a retry\n\nAssistant: Retry added.")
        #expect(i.started_at == "2026-10-01T09:00:00Z" && i.ended_at == "2026-10-01T09:00:04Z")
        #expect(report.found == 1 && report.items == 1)
    }

    @Test func aMissingDatabaseStillReadsTheTranscript() async throws {
        let root = try fixtureRoot()
        try write(root, log("c2", "transcript.jsonl"), Self.transcript)
        let c = AntigravityCollector(device: "mac-1", dbPath: root.appendingPathComponent("nope.db").path)
        let (items, _) = try await gather(root.appendingPathComponent("brain"), collector: c)
        #expect(items.first?.title == "Add a retry" && items.first?.project_hint == nil)
    }

    @Test func aConversationInARefusedProjectIsSkipped() async throws {
        let root = try fixtureRoot()
        try write(root, log("c3"), Self.transcript)
        let path = try db(
            root, [#"INSERT INTO conversation_summaries VALUES ('c3','Old','["file:///Users/x/Projects/Habtic"]')"#])
        let (items, report) = try await gather(
            root.appendingPathComponent("brain"), collector: AntigravityCollector(device: "mac-1", dbPath: path))
        #expect(items.isEmpty && report.skipped["deprecated:Habtic"] == 1)
    }

    @Test func unknownFormatIsSkippedWithAReason() async throws {
        let root = try fixtureRoot()
        try write(root, log("c4"), #"{"v":3,"records":[]}"#)
        let c = AntigravityCollector(device: "mac-1", dbPath: "/nonexistent.db")
        let (items, report) = try await gather(root.appendingPathComponent("brain"), collector: c)
        #expect(items.isEmpty && report.skipped["unknown-format"] == 1)
    }
}
