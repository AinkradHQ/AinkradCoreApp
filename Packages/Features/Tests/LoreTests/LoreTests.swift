import Admin
import CoreKit
import Foundation
import Shell
import Testing

@testable import Lore

@MainActor
final class FakeHost: AdminHost {
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

@MainActor
final class FakePage: LorePageText {
    var text = ""
    var folds = 0
    func markdown() -> String { text }
    func show(_ markdown: String, fold: Bool) {
        text = markdown
        if fold { folds += 1 }
    }
    func focus() {}
    var composing = false
}

/// An in-memory Core with the append-only merge the real one gives for an AI append.
final class FakeLore: LoreService, @unchecked Sendable {
    private let lock = NSLock()
    var notes: [String: LoreNote] = [:]
    var history: [String: [Int: String]] = [:]
    var offline = false
    private(set) var calls: [String] = []

    func put(_ n: LoreNote) {
        lock.withLock {
            notes[n.id] = n
            history[n.id, default: [:]][n.rev] = n.text
        }
    }
    func append(_ id: String, _ s: String) -> Int {
        lock.withLock {
            notes[id]!.text += s
            notes[id]!.rev += 1
            history[id]![notes[id]!.rev] = notes[id]!.text
            return notes[id]!.rev
        }
    }
    func log() -> [String] { lock.withLock { calls } }

    func today(_ day: String) async throws -> LoreNote {
        try lock.withLock {
            calls.append("today \(day)")
            if offline { throw CoreError.offline("down") }
            if let n = notes.values.first(where: { $0.day == day }) { return n }
            let n = LoreNote(id: "ln_aaaaaaaaaaaa", kind: "daily", day: day, rev: 1)
            notes[n.id] = n
            history[n.id] = [1: ""]
            return n
        }
    }
    func daily(_ day: String) async throws -> LoreNote? {
        lock.withLock {
            calls.append("daily \(day)")
            return notes.values.first { $0.day == day }
        }
    }
    func note(_ id: String) async throws -> LoreNote {
        try lock.withLock {
            calls.append("get \(id)")
            guard let n = notes[id] else { throw CoreError.http(status: 404, code: "not_found", message: "") }
            return n
        }
    }
    func create(text: String, project: String?) async throws -> LoreNote {
        lock.withLock {
            calls.append("create \(project ?? "personal")")
            let n = LoreNote(id: "ln_bbbbbbbbbbbb", project: project, text: text)
            notes[n.id] = n
            history[n.id] = [1: text]
            return n
        }
    }
    func save(_ id: String, baseRev: Int, text: String) async throws -> LoreSaveResult {
        try lock.withLock {
            calls.append("save \(id) \(baseRev)")
            if offline { throw CoreError.offline("down") }
            var n = notes[id]!
            var merged = text
            var outcome = "saved"
            if baseRev < n.rev, let base = history[id]?[baseRev], n.text.hasPrefix(base) {
                merged = text + n.text.dropFirst(base.count)
                outcome = "merged"
            }
            if merged != n.text {
                n.rev += 1
                n.text = merged
            }
            notes[id] = n
            history[id, default: [:]][n.rev] = merged
            return LoreSaveResult(note: n, outcome: outcome)
        }
    }
    func projectNames() async throws -> [String: String] { ["7": "Garden Club"] }

    /// R6-03: a word search over titles and text, newest first; `semantic` is what the test sets.
    var semantic = true
    func search(_ query: String, filter: LoreFilter, limit: Int) async throws -> LoreSearchResult {
        try lock.withLock {
            calls.append(
                "search \(query) \(filter.state) \(filter.kind ?? "-") \(filter.project ?? "-") \(filter.tag ?? "-")")
            if offline { throw CoreError.offline("down") }
            let hits = notes.values.filter { Self.match($0, filter) && $0.text.localizedCaseInsensitiveContains(query) }
                .sorted { $0.id < $1.id }
                .map { LoreHit(note: $0, snippet: LoreSnippet(text: $0.text, matches: [])) }
            return LoreSearchResult(hits: hits, semantic: semantic)
        }
    }
    func list(filter: LoreFilter) async throws -> [LoreNote] {
        try lock.withLock {
            calls.append("list \(filter.state) \(filter.kind ?? "-") \(filter.project ?? "-")")
            if offline { throw CoreError.offline("down") }
            return notes.values.filter { Self.match($0, filter) }.sorted { $0.id < $1.id }
        }
    }
    var docs: [LoreSessionDoc] = []
    func sessionDocs() async throws -> [LoreSessionDoc] { lock.withLock { docs } }
    func trash(_ id: String) async throws -> LoreNote {
        lock.withLock {
            calls.append("trash \(id)")
            notes[id]!.trashed = true
            return notes[id]!
        }
    }
    func restore(_ id: String) async throws -> LoreNote {
        lock.withLock {
            calls.append("restore \(id)")
            notes[id]!.trashed = false
            return notes[id]!
        }
    }
    private static func match(_ n: LoreNote, _ f: LoreFilter) -> Bool {
        n.trashed == (f.state == "trashed") && (f.kind == nil || n.kind == f.kind)
            && (f.project == nil || n.project == f.project)
    }

    var links: [String: [LoreBacklink]] = [:]
    /// Version id to its text, per note; `restored` counts the auto versions made by restores.
    var kept: [String: [String: String]] = [:]
    func backlinks(_ id: String) async throws -> [LoreBacklink] { lock.withLock { links[id] ?? [] } }
    func versions(_ id: String) async throws -> [LoreVersion] {
        lock.withLock { (kept[id] ?? [:]).keys.sorted().map { LoreVersion(id: $0) } }
    }
    func versionText(_ id: String, version: String) async throws -> String { lock.withLock { kept[id]![version]! } }
    func restore(_ id: String, version: String) async throws -> LoreSaveResult {
        lock.withLock {
            calls.append("restore \(id) \(version)")
            var n = notes[id]!
            let undo = "lv_u\(kept[id]!.count)"
            kept[id]![undo] = n.text
            n.text = kept[id]![version]!
            n.rev += 1
            notes[id] = n
            history[id, default: [:]][n.rev] = n.text
            return LoreSaveResult(note: n, outcome: "restored", version: undo)
        }
    }
    func move(_ id: String, project: String?) async throws -> LoreNote {
        lock.withLock {
            calls.append("move \(id) \(project ?? "personal")")
            notes[id]!.project = project
            return notes[id]!
        }
    }
}

@MainActor
struct LoreModelTests {
    let host = FakeHost()
    let page = FakePage()
    let core = FakeLore()
    let model: LoreModel
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lore-tests-\(UUID().uuidString)")
    let today = LoreModel.key(Date())

    init() {
        model = LoreModel(host: host, page: page, drafts: LoreDrafts(dir: dir))
        model.debounce = .milliseconds(20)
    }

    private func open() async {
        model.service = core
        await model.openDay(today)
    }

    @Test func opensTodayOnABlankPage() async {
        await open()
        #expect(model.load == .ready)
        #expect(model.note?.day == today)
        #expect(page.text == "")
        // The sidebars load their lists beside it, so only the first call is fixed.
        #expect(core.log().first == "today \(today)")
    }

    @Test func aNoteFromAnAISessionFileKnowsItsSessionAndFile() async {
        core.put(LoreNote(id: "ln_cccccccccccc", project: nil, title: "Plan", rev: 1, text: "# Plan\n"))
        core.docs = [LoreSessionDoc(note: "ln_cccccccccccc", session: "as_1", path: "docs/login-plan.md")]
        model.service = core
        await model.openNote("ln_cccccccccccc")
        #expect(await until { model.openDoc?.session == "as_1" })
        #expect(model.savedIn == "docs/login-plan.md")
        await model.openDay(today)
        #expect(model.openDoc == nil && model.savedIn == "Lore")
    }

    @Test func autosavesFromTheBaseRevision() async {
        await open()
        page.text = "# Hello\n"
        model.changed()
        #expect(await until { core.notes["ln_aaaaaaaaaaaa"]?.text == "# Hello\n" })
        #expect(core.log().contains("save ln_aaaaaaaaaaaa 1"))
        #expect(await until { model.base == 2 && model.sync == .saved })
        #expect(LoreDrafts(dir: dir).read("ln_aaaaaaaaaaaa") == nil)
    }

    @Test func anAIAppendWhileTypingIsMergedAndFoldedIn() async {
        await open()
        page.text = "typed\n"
        let rev = core.append("ln_aaaaaaaaaaaa", "ai line\n")
        model.remote(["id": "ln_aaaaaaaaaaaa", "rev": String(rev), "origin": "session"])
        #expect(await until { page.text == "typed\nai line\n" })
        #expect(page.folds == 1)
        #expect(core.notes["ln_aaaaaaaaaaaa"]?.text == "typed\nai line\n")
    }

    @Test func aRemoteChangeOnAnUntouchedPageIsPulled() async {
        await open()
        let rev = core.append("ln_aaaaaaaaaaaa", "from the phone\n")
        model.remote(["id": "ln_aaaaaaaaaaaa", "rev": String(rev), "origin": "person"])
        #expect(await until { page.text == "from the phone\n" && model.base == rev })
        // An older or own revision is ignored.
        model.remote(["id": "ln_aaaaaaaaaaaa", "rev": "1", "origin": "person"])
        #expect(page.folds == 1)
    }

    @Test func textTypedWhileTheLinkIsDownIsKeptAndSentLater() async {
        await open()
        core.offline = true
        page.text = "while away\n"
        model.changed()
        #expect(await until { model.sync == .kept })
        #expect(LoreDrafts(dir: dir).read("ln_aaaaaaaaaaaa") == .init(base: 1, text: "while away\n"))
        core.offline = false
        model.linkUp()
        #expect(await until { core.notes["ln_aaaaaaaaaaaa"]?.text == "while away\n" && model.sync == .saved })
        #expect(LoreDrafts(dir: dir).read("ln_aaaaaaaaaaaa") == nil)
    }

    @Test func aDraftFoundOnOpenIsShownAndMerged() async {
        core.put(LoreNote(id: "ln_aaaaaaaaaaaa", kind: "daily", day: today, rev: 1, text: "start\n"))
        _ = core.append("ln_aaaaaaaaaaaa", "ai\n")
        LoreDrafts(dir: dir).write("ln_aaaaaaaaaaaa", base: 1, text: "start\nmine\n")
        await open()
        #expect(await until { core.notes["ln_aaaaaaaaaaaa"]?.text == "start\nmine\nai\n" })
        #expect(await until { page.text == "start\nmine\nai\n" })
    }

    @Test func aPastDayIsMadeOnTheFirstWords() async {
        model.service = core
        let past = LoreModel.key(Date().addingTimeInterval(-3 * 86_400))
        await model.openDay(past)
        #expect(model.note == nil && model.load == .ready)
        #expect(!core.log().contains("today \(past)"))
        page.text = "late entry\n"
        model.changed()
        #expect(await until { core.log().contains("save ln_aaaaaaaaaaaa 1") })
        #expect(core.notes["ln_aaaaaaaaaaaa"]?.text == "late entry\n")
    }

    @Test func newNoteKeepsTheProject() async {
        core.put(LoreNote(id: "ln_cccccccccccc", project: "7", title: "Plan", rev: 1, text: "# Plan\n"))
        model.service = core
        await model.openNote("ln_cccccccccccc")
        #expect(model.projectName == "Project")  // names arrive with `use`
        await model.newNote()
        #expect(core.log().contains("create 7"))
        #expect(model.note?.id == "ln_bbbbbbbbbbbb")
    }

    @Test func onlyWellFormedInternalLinksOpen() async {
        core.put(LoreNote(id: "ln_cccccccccccc", title: "Plan", rev: 1, text: "x"))
        await open()
        model.openInternal(URL(string: "lore:ln_cccccccccccc")!)
        #expect(await until { model.note?.id == "ln_cccccccccccc" })
        model.openInternal(URL(string: "lore-attachment:" + String(repeating: "a", count: 64))!)
        #expect(host.shell.toast?.message == "Attachments come later.")
        for bad in [
            "lore:../../etc", "lore://ln_cccccccccccc", "lore:ln_CCCCCCCCCCCC", "lore-attachment:abc", "file:/x",
        ] {
            host.shell.toast = nil
            model.openInternal(URL(string: bad)!)
            #expect(host.shell.toast?.message == "That link does not open from a note.", "\(bad)")
        }
        #expect(model.note?.id == "ln_cccccccccccc")
    }

    @Test func restoreThenUndoRoundTrips() async {
        core.put(LoreNote(id: "ln_cccccccccccc", title: "A", rev: 2, text: "new\n"))
        core.kept["ln_cccccccccccc"] = ["lv_a": "old\n"]
        model.service = core
        await model.openNote("ln_cccccccccccc")
        await model.restore("lv_a")
        #expect(page.text == "old\n" && model.base == 3)
        #expect(model.notice == "Restored" && model.noticeAction == .undoRestore("lv_u1"))
        await model.restore("lv_u1", offerUndo: false)
        #expect(page.text == "new\n" && model.notice == nil && model.base == 4)
    }

    @Test func backlinksShowOnlyWhenThereAreSome() async {
        core.put(LoreNote(id: "ln_cccccccccccc", title: "A", rev: 1, text: "x"))
        core.links["ln_cccccccccccc"] = [LoreBacklink(note: "ln_dddddddddddd", title: "B", context: "see [[A]]")]
        model.service = core
        await model.openNote("ln_cccccccccccc")
        #expect(await until { model.backlinks.count == 1 })
        await model.openDay(today)
        #expect(model.backlinks.isEmpty)
    }

    @Test func movingANoteChangesOnlyItsProject() async {
        core.put(LoreNote(id: "ln_cccccccccccc", title: "A", rev: 1, text: "x"))
        model.service = core
        await model.openNote("ln_cccccccccccc")
        await model.move(to: "7")
        #expect(model.note?.project == "7" && model.projectName == "Project")
        await model.move(to: nil)
        #expect(model.note?.project == nil)
        // A daily note never moves.
        await model.openDay(today)
        await model.move(to: "7")
        #expect(model.note?.project == nil)
    }
}

struct LoreFoldTests {
    @Test func caretStaysWhenTextIsAddedAfterIt() {
        #expect(LoreFold.caret(3, from: "abcdef", to: "abcdefXYZ") == 3)
    }
    @Test func caretMovesWithTextAddedBeforeIt() {
        #expect(LoreFold.caret(3, from: "abcdef", to: "XYabcdef") == 5)
    }
    @Test func caretBetweenTwoRemoteChanges() {
        // A line added at the top and one at the end; the caret sits in the middle line.
        let old = "one\ntwo\nthree\n"
        let new = "zero\none\ntwo\nthree\nfour\n"
        #expect(LoreFold.caret(6, from: old, to: new) == 11)
    }
    @Test func textInsertedAtTheCaretLandsAfterIt() {
        #expect(LoreFold.caret(2, from: "abcd", to: "abXXcd") == 2)
    }
    @Test func removedTextBeforeTheCaret() {
        #expect(LoreFold.caret(4, from: "abcdef", to: "aef") == 1)
    }
}

struct LoreDraftsTests {
    @Test func writeReadRemove() {
        let d = LoreDrafts(dir: FileManager.default.temporaryDirectory.appendingPathComponent("lore-d-\(UUID())"))
        d.write("ln_aaaaaaaaaaaa", base: 4, text: "a")
        d.write("ln_aaaaaaaaaaaa", base: 5, text: "b")
        #expect(d.read("ln_aaaaaaaaaaaa") == .init(base: 5, text: "b"))
        d.write("day-2026-11-17", base: 0, text: "c")
        #expect(d.read("day-2026-11-17") == .init(base: 0, text: "c"))
        d.write("../evil", base: 1, text: "x")
        #expect(d.read("../evil") == nil)
        d.remove("ln_aaaaaaaaaaaa")
        #expect(d.read("ln_aaaaaaaaaaaa") == nil)
    }
}
