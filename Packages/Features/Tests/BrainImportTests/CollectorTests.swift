import Foundation
import Testing

@testable import BrainImport

/// Records every file read, so a test can prove what was never opened.
final class SpyFiles: FileAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [String] = []
    var opened: [String] { lock.withLock { reads } }
    func listFiles(under root: URL) -> [URL] { DiskFiles().listFiles(under: root) }
    func size(of url: URL) -> UInt64 { DiskFiles().size(of: url) }
    func readLines(_ url: URL, chunk: Int, maxLine: Int, _ each: (Data) async throws -> Bool) async throws {
        lock.withLock { reads.append(url.path) }
        try await DiskFiles().readLines(url, chunk: chunk, maxLine: maxLine, each)
    }
}

/// Keeps every uploaded item, in order, and can be told to drop after some posts.
final class Recorder: ImportTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [ImportItem] = []
    private var posts = 0
    let failAfter: Int?
    init(failAfter: Int? = nil) { self.failAfter = failAfter }
    var items: [ImportItem] { lock.withLock { all } }
    func post(path: String, body: Data) async throws -> Data {
        try lock.withLock {
            if let failAfter, posts >= failAfter { throw URLError(.networkConnectionLost) }
            posts += 1
            all += try JSONDecoder().decode([String: [ImportItem]].self, from: body)["items"] ?? []
        }
        return Data()
    }
}

/// Runs the real streamer over `root` and returns what reached the transport.
func gather(
    _ root: URL, files: any FileAccess = DiskFiles(), chunk: Int = ClaudeCodeCollector.defaultChunk,
    maxLine: Int = ClaudeCodeCollector.defaultMaxLine, gauge: BufferGauge? = nil
) async throws -> (items: [ImportItem], report: CollectReport) {
    let rec = Recorder()
    let streamer = ImportStreamer(
        collector: ClaudeCodeCollector(device: "mac-1", files: files, chunk: chunk, maxLine: maxLine, gauge: gauge),
        uploader: Uploader(transport: rec, retries: 0, pause: { _ in }), gauge: gauge)
    let report = try await streamer.run(
        root: root, runID: "r", resume: .init(), uploaded: .init(), save: { _ in }, onProgress: { _ in })
    return (rec.items, report)
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
    @Test func normalisesASyntheticSessionExactly() async throws {
        let root = try fixtureRoot()
        try write(
            root, "-synthetic-work-alpha/s1.jsonl",
            session(cwd: "/synthetic/work/alpha", [("user", "Fix the parser"), ("assistant", "Done, see KAN-12")]))
        // an unknown record and a tool call block are skipped, a tool result is trimmed
        let (items, report) = try await gather(root)
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
        #expect(try await gather(root).items.first?.item_id == i.item_id)
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

    @Test func restrictedAndDeprecatedPathsAreNeverOpened() async throws {
        let root = try fixtureRoot()
        try write(root, "-synthetic-ok/a.jsonl", session(cwd: "/synthetic/ok", [("user", "hi")]))
        try write(
            root, "-Users-x-Projects-GitScope-app/b.jsonl",
            session(cwd: "/Users/x/Projects/GitScope/app", [("user", "old")]))
        try write(root, "-synthetic-ok/.env", "SECRET=1")
        try write(root, "contracts/c.jsonl", session(cwd: "/x", [("user", "legal")]))
        try write(root, "-synthetic-ok/server.pem", "KEY")
        let spy = SpyFiles()
        let (items, report) = try await gather(root, files: spy)
        #expect(items.count == 1)
        let opened = spy.opened.joined(separator: "|")
        #expect(opened.contains("a.jsonl"))
        #expect(
            !opened.contains("GitScope") && !opened.contains(".env") && !opened.contains("contracts")
                && !opened.contains(".pem"))
        #expect(report.skipped["deprecated:GitScope"] == 1 && report.skipped["restricted"] == 1)
    }

    @Test func aSessionWhoseCwdIsDeprecatedIsSkippedAfterTheFirstRead() async throws {
        let root = try fixtureRoot()
        try write(root, "-misc/c.jsonl", session(cwd: "/home/me/Projects/Finvo/api", [("user", "old")]))
        let (items, report) = try await gather(root)
        #expect(items.isEmpty && report.skipped["deprecated:Finvo"] == 1)
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

/// Streaming: bounded memory, order, resume. Synthetic data only.
@Suite struct StreamingTests {
    static let chunk = 64 * 1024
    static let maxLine = 256 * 1024

    func record(_ type: String, _ text: String, at i: Int) -> String {
        "{\"type\":\"\(type)\",\"cwd\":\"/synthetic/p\",\"timestamp\":\"2026-11-01T09:\(String(format: "%02d", i % 60)):00Z\",\"message\":{\"role\":\"\(type)\",\"content\":\"\(text)\"}}"
    }

    /// 40 small files and one of ~8 MB (many times the chunk and part sizes).
    func tree() throws -> (root: URL, bigEntries: [String], total: Int) {
        let root = try fixtureRoot()
        for i in 0..<40 {
            try write(
                root, "-p\(i % 4)/s\(String(format: "%02d", i)).jsonl",
                session(cwd: "/synthetic/p", [("user", "hello \(i)")]))
        }
        var lines: [String] = []
        var entries: [String] = []
        for i in 0..<5_000 {
            let text = "n\(i) " + String(repeating: "abcd ", count: 300)
            let type = i % 2 == 0 ? "user" : "assistant"
            lines.append(record(type, text, at: i))
            entries.append("\(type == "user" ? "User" : "Assistant"): \(text.trimmingCharacters(in: .whitespaces))")
        }
        try write(root, "-p1/zz-big.jsonl", lines.joined(separator: "\n"))
        let total = try FileManager.default.subpathsOfDirectory(atPath: root.path).reduce(0) {
            $0
                + ((try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent($1).path)[.size]
                    as? Int) ?? 0)
        }
        return (root, entries, total)
    }

    @Test func peakBufferedBytesStayUnderTheBoundNotTheTotal() async throws {
        let (root, _, total) = try tree()
        let gauge = BufferGauge()
        let (items, _) = try await gather(root, chunk: Self.chunk, maxLine: Self.maxLine, gauge: gauge)
        // reader (chunk + a line) + a part being built and one held + one upload batch
        let bound = Self.chunk + Self.maxLine + 2 * ItemFormat.partBytes + Uploader.maxBatchBytes + 500 * 1024
        print("STREAMING peak buffered \(gauge.peak) bytes, bound \(bound), input \(total)")
        #expect(total > 7_000_000 && gauge.peak > 0)
        #expect(gauge.peak < bound)
        #expect(gauge.peak < total / 3)
        #expect(items.count > 40 + 20)
    }

    @Test func itemsArriveInFileOrderAndTheBigFileIsCompleteInOrderedParts() async throws {
        let (root, entries, _) = try tree()
        let (items, report) = try await gather(root, chunk: Self.chunk, maxLine: Self.maxLine)
        let paths = items.map(\.origin.path)
        #expect(paths == paths.sorted())  // sorted by path, parts of one file adjacent
        #expect(Set(items.map(\.item_id)).count == items.count)
        #expect(report.found == 41 && report.items == items.count)
        let big = items.filter { $0.origin.path.hasSuffix("zz-big.jsonl") }
        #expect(big.count > 1)
        #expect(big.enumerated().allSatisfy { $0.element.origin.range?.first == UInt64($0.offset) })
        #expect(big.allSatisfy { $0.text.utf8.count <= ItemFormat.maxText })
        #expect(big.map(\.text).joined(separator: "\n\n") == entries.joined(separator: "\n\n"))
        #expect(items.filter { !$0.origin.path.hasSuffix("zz-big.jsonl") }.count == 40)
    }

    @Test func aLineOverTheCapIsDroppedAndTheNextLineStillRead() async throws {
        let root = try fixtureRoot()
        let huge = String(repeating: "x", count: 3 * Self.chunk)
        try write(
            root, "-p/a.jsonl",
            [record("user", "first", at: 0), record("user", huge, at: 1), record("assistant", "last", at: 2)].joined(
                separator: "\n"))
        let (items, _) = try await gather(root, chunk: Self.chunk, maxLine: Self.chunk)
        #expect(items.count == 1 && items[0].text == "User: first\n\nAssistant: last")
    }

    @Test func resumeAfterAnInterruptionSkipsFinishedFilesAndLosesNothing() async throws {
        let root = try fixtureRoot()
        for i in 0..<10 {
            try write(root, "-p/s\(i).jsonl", session(cwd: "/synthetic/p", [("user", "msg \(i)")]))
        }
        var saved = SourceResume()
        let first = Recorder(failAfter: 3)  // the Core drops on the 4th file
        let spy1 = SpyFiles()
        let s1 = ImportStreamer(
            collector: ClaudeCodeCollector(device: "d", files: spy1),
            uploader: Uploader(transport: first, retries: 0, pause: { _ in }), saveEvery: 0)
        let box = SavedBox()
        await #expect(throws: Uploader.Failure.self) {
            try await s1.run(
                root: root, runID: "r", resume: .init(), uploaded: .init(), save: { box.set($0) }, onProgress: { _ in })
        }
        saved = box.value
        #expect(saved.done.count == 3 && first.items.count == 3)

        let second = Recorder()
        let spy2 = SpyFiles()
        let s2 = ImportStreamer(
            collector: ClaudeCodeCollector(device: "d", files: spy2),
            uploader: Uploader(transport: second, retries: 0, pause: { _ in }), saveEvery: 0)
        let progress = ProgressBox()
        let report = try await s2.run(
            root: root, runID: "r", resume: saved, uploaded: .init(), save: { box.set($0) },
            onProgress: { progress.add($0) })
        #expect(spy2.opened.count == 7)  // the three finished files are not opened again
        #expect(spy2.opened.allSatisfy { p in !saved.done.contains(where: { p.hasSuffix($0) }) })
        let all = Set((first.items + second.items).map(\.text))
        #expect(all == Set((0..<10).map { "User: msg \($0)" }))
        #expect(report.items == 10 && box.value.done.count == 10)
        // progress starts with the finished files already counted and ends complete
        #expect(progress.all.first?.filesDone == 3 && progress.all.first?.filesTotal == 10)
        #expect(progress.all.last?.filesDone == 10 && progress.all.last?.bytesDone == progress.all.last?.bytesTotal)
    }

    @Test func progressCountsBytesFromAttributesAndNamesTheCurrentFile() async throws {
        let (root, _, _) = try tree()
        let progress = ProgressBox()
        let streamer = ImportStreamer(
            collector: ClaudeCodeCollector(device: "d", chunk: Self.chunk, maxLine: Self.maxLine),
            uploader: Uploader(transport: Recorder(), retries: 0, pause: { _ in }))
        _ = try await streamer.run(
            root: root, runID: "r", resume: .init(), uploaded: .init(), save: { _ in },
            onProgress: { progress.add($0) })
        let sizes = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".jsonl") }
            .reduce(UInt64(0)) { $0 + DiskFiles().size(of: root.appendingPathComponent($1)) }
        let last = try #require(progress.all.last)
        #expect(last.bytesTotal == sizes && last.bytesDone == sizes && last.filesTotal == 41 && last.filesDone == 41)
        #expect(progress.all.contains { $0.current.hasSuffix("zz-big.jsonl") })
    }

    @Test func resumeStoreRoundTripsPathsOnly() throws {
        let store = ResumeStore(url: try fixtureRoot().appendingPathComponent("state.json"))
        var st = ResumeState()
        st.run = "r9"
        st.sources["claude_code"] = SourceResume(done: ["/a/b.jsonl"], items: 2, skipped: ["empty": 1])
        store.save(st)
        #expect(store.load() == st)
        store.clear()
        #expect(store.load() == ResumeState())
    }
}

final class SavedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var v = SourceResume()
    var value: SourceResume { lock.withLock { v } }
    func set(_ s: SourceResume) { lock.withLock { v = s } }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var a: [StreamProgress] = []
    var all: [StreamProgress] { lock.withLock { a } }
    func add(_ p: StreamProgress) { lock.withLock { a.append(p) } }
}
