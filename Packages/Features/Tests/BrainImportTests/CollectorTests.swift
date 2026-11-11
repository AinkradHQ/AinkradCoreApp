import Foundation
import Testing

@testable import BrainImport

/// Records every file read, so a test can prove what was never opened.
final class SpyFiles: FileAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [String] = []
    var opened: [String] { lock.withLock { reads } }
    func listFiles(under root: URL) -> [URL] { DiskFiles().listFiles(under: root) }
    func read(_ url: URL) throws -> Data {
        lock.withLock { reads.append(url.path) }
        return try Data(contentsOf: url)
    }
}

func fixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("brain-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func write(_ root: URL, _ rel: String, _ text: String) throws {
    let url = root.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func session(cwd: String, _ turns: [(String, String)]) -> String {
    turns.enumerated().map { i, t in
        let content = t.1.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return
            "{\"type\":\"\(t.0)\",\"cwd\":\"\(cwd)\",\"timestamp\":\"2026-11-0\(1 + i)T09:00:00Z\",\"message\":{\"role\":\"\(t.0)\",\"content\":\"\(content)\"}}"
    }.joined(separator: "\n")
}

@Suite struct CollectorTests {
    @Test func normalisesASyntheticSessionExactly() throws {
        let root = try fixtureRoot()
        try write(
            root, "-synthetic-work-alpha/s1.jsonl",
            session(cwd: "/synthetic/work/alpha", [("user", "Fix the parser"), ("assistant", "Done, see KAN-12")]))
        // an unknown record and a tool call block are skipped, a tool result is trimmed
        var report = CollectReport()
        let items = ClaudeCodeCollector(device: "mac-1").collect(root: root, report: &report)
        #expect(items.count == 1)
        let i = items[0]
        #expect(i.source_kind == "claude_code")
        #expect(i.text == "User: Fix the parser\n\nAssistant: Done, see KAN-12")
        #expect(i.title == "Fix the parser")
        #expect(i.project_hint == "/synthetic/work/alpha")
        #expect(i.started_at == "2026-11-01T09:00:00Z" && i.ended_at == "2026-11-02T09:00:00Z")
        #expect(i.content_hash == ItemFormat.hash(i.text) && i.item_id.count == 26)
        #expect(report.found == 1 && report.items == 1 && report.skipped.isEmpty)
        // Re-running makes the same ids (idempotent uploads).
        var again = CollectReport()
        #expect(ClaudeCodeCollector(device: "mac-1").collect(root: root, report: &again).first?.item_id == i.item_id)
    }

    @Test func toolOutputIsTrimmedAndToolCallsDropped() {
        let long = String(repeating: "x", count: 1000)
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "Bash"], ["type": "tool_result", "content": long],
            ["type": "text", "text": "ok"],
        ]
        let t = ClaudeCodeCollector.text(of: content)
        #expect(t.contains("[trimmed]") && t.hasSuffix("ok") && t.count < 500 && !t.contains("Bash"))
    }

    @Test func restrictedAndDeprecatedPathsAreNeverOpened() throws {
        let root = try fixtureRoot()
        try write(root, "-synthetic-ok/a.jsonl", session(cwd: "/synthetic/ok", [("user", "hi")]))
        try write(
            root, "-Users-x-Projects-GitScope-app/b.jsonl",
            session(cwd: "/Users/x/Projects/GitScope/app", [("user", "old")]))
        try write(root, "-synthetic-ok/.env", "SECRET=1")
        try write(root, "contracts/c.jsonl", session(cwd: "/x", [("user", "legal")]))
        try write(root, "-synthetic-ok/server.pem", "KEY")
        let spy = SpyFiles()
        var report = CollectReport()
        let items = ClaudeCodeCollector(device: "d", files: spy).collect(root: root, report: &report)
        #expect(items.count == 1)
        let opened = spy.opened.joined(separator: "|")
        #expect(opened.contains("a.jsonl"))
        #expect(
            !opened.contains("GitScope") && !opened.contains(".env") && !opened.contains("contracts")
                && !opened.contains(".pem"))
        #expect(report.skipped["deprecated:GitScope"] == 1 && report.skipped["restricted"] == 1)
    }

    @Test func aSessionWhoseCwdIsDeprecatedIsSkippedAfterTheFirstRead() throws {
        let root = try fixtureRoot()
        try write(root, "-misc/c.jsonl", session(cwd: "/home/me/Projects/Finvo/api", [("user", "old")]))
        var report = CollectReport()
        #expect(ClaudeCodeCollector(device: "d").collect(root: root, report: &report).isEmpty)
        #expect(report.skipped["deprecated:Finvo"] == 1)
    }

    @Test func aHugeSessionSplitsIntoPartsUnderTheCap() throws {
        let line = String(repeating: "word ", count: 200)  // ~1 KB
        let body = (0..<1_500).map { "\($0) " + line }.joined(separator: "\n")  // ~1.5 MB stands in for 50 MB
        let parts = ItemFormat.split(body)
        #expect(parts.count >= 6)
        #expect(parts.allSatisfy { $0.utf8.count <= ItemFormat.maxText })
        #expect(parts.joined(separator: "\n") == body)
        let one = String(repeating: "é", count: 400_000)  // one line, multi-byte
        let cut = ItemFormat.split(one)
        #expect(cut.allSatisfy { $0.utf8.count <= ItemFormat.maxText } && cut.joined() == one)
    }

    @Test func preFilterMirrorsTheCoreRules() {
        for p in ["/a/.env", "/a/.env.local", "/a/server.pem", "/a/AuthKey.p8", "/h/.ssh/id_rsa", "/w/Contracts/x.md"] {
            #expect(PreFilter.isRestricted(p), "\(p)")
        }
        for p in ["/a/env.md", "/a/README.md", "/a/monkey.rs"] { #expect(!PreFilter.isRestricted(p), "\(p)") }
        #expect(PreFilter.deprecatedProject(in: "-Users-x-Projects-ILINK-app") == "ILINK")
        #expect(PreFilter.deprecatedProject(in: "/a/GitScopeX/b") == nil)
    }

    @Test func hashMatchesTheCoreForNormalisedText() {
        // sha256("hello\nworld"), the same value the Core's `hash_of("hello\r\nworld  ")` gives.
        #expect(ItemFormat.hash("hello\r\nworld  ") == ItemFormat.hash("hello\nworld"))
        #expect(ItemFormat.hash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

struct FlakyTransport: ImportTransport {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        var failUntil: Int
        var bodies: [Data] = []
        init(failUntil: Int) { self.failUntil = failUntil }
    }
    let state: State
    func post(path: String, body: Data) async throws -> Data {
        try state.lock.withLock {
            state.calls += 1
            if state.calls <= state.failUntil { throw URLError(.networkConnectionLost) }
            state.bodies.append(body)
            return Data()
        }
    }
}

@Suite struct UploaderTests {
    func items(_ n: Int, size: Int = 10) -> [ImportItem] {
        (0..<n).map { i in
            let text = "t\(i)" + String(repeating: "x", count: size)
            return ImportItem(
                item_id: ItemFormat.itemID(seed: "i\(i)"), source_kind: "claude_code",
                content_hash: ItemFormat.hash(text),
                origin: .init(device: "d", path: "/p\(i)", range: nil), project_hint: nil,
                author: .init(kind: "person", name: "me"),
                title: "t", text: text, links: [], started_at: "2026-11-01T09:00:00Z", ended_at: nil)
        }
    }

    @Test func batchesStayUnderTheCap() throws {
        let b = try Uploader.batches(items(30, size: 100_000))
        #expect(b.count > 1)
        for batch in b { #expect(try JSONEncoder().encode(["items": batch]).count < 1_048_576) }
        #expect(b.flatMap { $0 }.count == 30)
    }

    @Test func resumesAfterTheCoreDropsAndDoesNotResend() async throws {
        let state = FlakyTransport.State(failUntil: 2)
        let up = Uploader(transport: FlakyTransport(state: state), retries: 3, pause: { _ in })
        let progress = Uploader.Progress()
        let all = items(5)
        #expect(try await up.upload(all, run: "run-1", progress: progress) == 5)
        #expect(state.calls == 3)  // two drops, then through
        #expect(try await up.upload(all, run: "run-1", progress: progress) == 0)  // nothing is sent twice
        #expect(await progress.count == 5)
    }

    @Test func givesUpAfterTheRetriesAndKeepsWhatWasConfirmed() async throws {
        let state = FlakyTransport.State(failUntil: 1_000)
        let up = Uploader(transport: FlakyTransport(state: state), retries: 2, pause: { _ in })
        let progress = Uploader.Progress()
        await #expect(throws: Uploader.Failure.self) { try await up.upload(items(3), run: "r", progress: progress) }
        #expect(await progress.count == 0 && state.calls == 3)
    }
}
