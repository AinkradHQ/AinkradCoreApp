import Admin
import CoreKit
import Foundation
import Shell
import Testing

@testable import LoreImport

@MainActor
final class ImportHost: AdminHost {
    func open(_ url: URL) {}  // never a real browser in a test
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    func clearElevationNotice() {}
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

/// A Core that keeps one run in memory and moves it through the states.
final class FakeImports: LoreImportService, @unchecked Sendable {
    private let lock = NSLock()
    private var run = LoreImportRun(
        id: "li_aaaaaaaaaaaa", source: "mirror", project: "7", state: "review", items: 3, include: 3)
    private(set) var calls: [String] = []
    var itemsList = [
        LoreImportItem(seq: 1, path: "plans/a.md", title: "A"),
        LoreImportItem(seq: 2, path: "plans/b.md", title: "B", flag: "changed"),
        LoreImportItem(seq: 3, path: "plans/c.md", title: "C", flag: "conflict"),
    ]
    var failCommitOnce = false

    func log() -> [String] { lock.withLock { calls } }
    private func note(_ s: String) { lock.withLock { calls.append(s) } }

    func importRuns() async throws -> [LoreImportRun] { [run] }
    func importRun(_ id: String) async throws -> LoreImportRun { run }
    func startImport(repo: Bool, project: String?) async throws -> LoreImportRun {
        note("start \(repo) \(project ?? "personal")")
        return run
    }
    func addImportFiles(_ run: String, _ files: [LoreImportFile]) async throws -> LoreImportRun { self.run }
    func addImportZip(_ run: String, _ zip: Data) async throws -> LoreImportRun { self.run }
    func finishImport(_ run: String) async throws -> LoreImportRun {
        note("finish")
        return self.run
    }
    func importItems(_ run: String, after: Int, limit: Int) async throws -> [LoreImportItem] {
        itemsList.filter { $0.seq > after }
    }
    func markImportItems(_ run: String, seqs: [Int], include: Bool) async throws -> LoreImportRun {
        note("mark \(seqs) \(include)")
        self.run.include += include ? 1 : -1
        return self.run
    }
    func moveImportItems(_ run: String, seqs: [Int], project: String?) async throws -> LoreImportRun {
        note("move \(project ?? "personal")")
        self.run.project = project
        return self.run
    }
    func commitImport(_ run: String) async throws -> LoreImportRun {
        note("commit")
        if failCommitOnce {
            failCommitOnce = false
            throw CoreError.offline("down")
        }
        self.run.state = "committed"
        self.run.results = ["created": 2, "updated": 1]
        return self.run
    }
    func undoImport(_ run: String) async throws -> LoreImportRun {
        note("undo")
        self.run.state = "undone"
        self.run.undone = 3
        return self.run
    }
    func abandonImport(_ run: String) async throws -> LoreImportRun {
        note("abandon")
        self.run.state = "abandoned"
        return self.run
    }
}

@MainActor
struct LoreImportModelTests {
    func make(_ fake: FakeImports) -> LoreImportModel {
        LoreImportModel(host: ImportHost(), service: fake, projectNames: ["7": "Garden Club Website"], project: "7")
    }

    @Test func aRepoImportOpensTheReviewWithItsItems() async {
        let fake = FakeImports()
        let m = make(fake)
        m.readRepo()
        #expect(await until { m.phase == .review && m.items.count == 3 })
        #expect(fake.log().first == "start true 7")
        #expect(LoreImportWords.summary(m.run!, into: m.place) == "Import 3 notes into Garden Club Website")
    }

    @Test func aRepoImportNeedsAProject() async {
        let fake = FakeImports()
        let m = make(fake)
        m.project = ""
        m.readRepo()
        #expect(fake.log().isEmpty && m.phase == .chooser)
    }

    @Test func skippingAnItemTellsTheCoreAndLockedItemsDoNothing() async {
        let fake = FakeImports()
        let m = make(fake)
        m.readRepo()
        #expect(await until { m.items.count == 3 })
        m.set(m.items[0], include: false)
        #expect(m.items[0].mark == "skip")
        #expect(await until { fake.log().contains("mark [1] false") })
        let locked = LoreImportItem(seq: 9, path: "x.md", flag: "too_large", mark: "skip")
        m.items.append(locked)
        m.set(locked, include: true)
        #expect(!fake.log().contains("mark [9] true"))
    }

    @Test func commitThenUndo() async {
        let fake = FakeImports()
        let m = make(fake)
        m.readRepo()
        #expect(await until { m.phase == .review })
        m.commit()
        #expect(await until { m.phase == .done })
        #expect(LoreImportWords.result(m.run!) == "2 added · 1 updated")
        m.undo()
        #expect(await until { m.phase == .undone })
        #expect(LoreImportWords.undone(m.run!) == "3 notes put back as they were.")
    }

    @Test func aFailedCommitCanBeTriedAgain() async {
        let fake = FakeImports()
        fake.failCommitOnce = true
        let m = make(fake)
        m.readRepo()
        #expect(await until { m.phase == .review })
        m.commit()
        #expect(await until { if case .failed = m.phase { true } else { false } })
        #expect(m.canTryAgain)
        m.tryAgain()
        #expect(await until { m.phase == .done })
        #expect(fake.log().filter { $0 == "commit" }.count == 2)
    }

    @Test func historyResumesACommittingRunAndOpensAReviewRun() async {
        let fake = FakeImports()
        let m = make(fake)
        m.resume(LoreImportRun(id: "li_aaaaaaaaaaaa", state: "committing", include: 3))
        #expect(await until { m.phase == .done })
        m.resume(LoreImportRun(id: "li_aaaaaaaaaaaa", state: "review", items: 3, include: 3))
        #expect(await until { m.phase == .review && m.items.count == 3 })
        m.resume(LoreImportRun(id: "li_aaaaaaaaaaaa", state: "abandoned"))
        #expect(m.phase == .review)
    }
}

struct LoreImportDiskTests {
    func tree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "lore-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "contracts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "b"), withIntermediateDirectories: true)
        try "# One".write(to: root.appending(path: "one.md"), atomically: true, encoding: .utf8)
        try "# Two".write(to: root.appending(path: "b/one.md"), atomically: true, encoding: .utf8)
        try "# Secret".write(to: root.appending(path: "contracts/deal.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appending(path: "photo.png"), atomically: true, encoding: .utf8)
        try String(repeating: "a", count: LoreImportDisk.fileMax + 1).write(
            to: root.appending(path: "big.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func onlyMarkdownIsReadAndPrivateOrHugeFilesAreCounted() throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["one.md", "b/one.md", "contracts/deal.md", "photo.png", "big.md"].map { root.appending(path: $0) }
        let pick = LoreImportDisk.read(urls)
        // A second file with the same name takes its folder's name.
        #expect(pick.files.map(\.path) == ["one.md", "b/one.md"])
        #expect(pick.skipped == ["private file": 1, "not Markdown": 1, "over 1 MB": 1])
        #expect(pick.skippedCount == 3 && !pick.isEmpty)
    }

    @Test func batchesStayUnderTheCall() {
        let files = (0..<450).map { LoreImportFile(path: "n\($0).md", text: String(repeating: "word\n", count: 400)) }
        let batches = LoreImportDisk.batches(files)
        #expect(batches.flatMap { $0 } == files)
        for b in batches {
            #expect(b.count <= LoreImportDisk.batchItems)
            #expect(((try? JSONEncoder().encode(["items": b]).count) ?? Int.max) <= 1 << 20)
        }
        #expect(batches.count > 1)
    }
}

struct LoreImportWordsTests {
    @Test func theReviewLineAndPlan() {
        let run = LoreImportRun(
            id: "li_x", state: "review", items: 6, include: 5, flags: ["changed": 2, "conflict": 1, "duplicate": 1])
        #expect(LoreImportWords.plan(run) == "2 new · 2 updated · 1 kept as you edited them · 1 unchanged")
        #expect(LoreImportWords.summary(run, into: "Personal") == "Import 5 notes into Personal")
        #expect(
            LoreImportWords.summary(LoreImportRun(id: "li_y", include: 1), into: "Personal")
                == "Import 1 note into Personal")
        #expect(LoreImportWords.notTaken(refused: 1, ignored: 0) == "1 refused as unsafe")
        #expect(LoreImportWords.notTaken(refused: 0, ignored: 0) == nil)
    }

    @Test func aFinishedRunHasNothingToResume() {
        #expect(LoreImportWords.resumeHelp("undone") == nil && LoreImportWords.resumeHelp("abandoned") == nil)
        #expect(LoreImportWords.resumeHelp("committing") != nil)
    }
}
