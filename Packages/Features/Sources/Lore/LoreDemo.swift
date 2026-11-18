#if DEBUG
import CoreKit
import Foundation
import Shell

/// Debug only: the Lore space on made-up notes and a stand-in Core, for screenshots and for the reviewer to click through.
/// Nothing here reaches a Core; drafts go to a temporary folder.
@MainActor
public final class LoreDemo {
    final class Service: LoreService, @unchecked Sendable {
        private let lock = NSLock()
        private var notes: [String: LoreNote] = [:]
        /// Every saved text by note and rev, for the stand-in merge.
        private var history: [String: [Int: String]] = [:]
        var conflict = false
        var offline = false
        private let originals: [LoreNote]
        init(_ list: [LoreNote]) {
            originals = list
            reset()
        }
        /// Every scene starts from the same notes.
        func reset() {
            lock.withLock {
                notes = [:]
                history = [:]
                for n in originals {
                    notes[n.id] = n
                    history[n.id] = [n.rev: n.text]
                }
            }
        }

        func today(_ day: String) async throws -> LoreNote {
            try lock.withLock {
                if offline { throw CoreError.offline("demo") }
                if let n = notes.values.first(where: { $0.day == day }) { return n }
                let tail = day.filter(\.isNumber).suffix(5).map {
                    Character(UnicodeScalar(UInt8(97) + UInt8(String($0))!))
                }
                let n = LoreNote(id: "ln_demoday\(String(tail))", kind: "daily", day: day)
                notes[n.id] = n
                return n
            }
        }
        func daily(_ day: String) async throws -> LoreNote? { lock.withLock { notes.values.first { $0.day == day } } }
        func note(_ id: String) async throws -> LoreNote {
            try lock.withLock {
                guard let n = notes[id] else { throw CoreError.http(status: 404, code: "not_found", message: "") }
                return n
            }
        }
        func create(text: String, project: String?) async throws -> LoreNote {
            lock.withLock {
                let n = LoreNote(
                    id: "ln_demonewnote\(["a", "b", "c", "d"][notes.count % 4])", project: project, text: text)
                notes[n.id] = n
                return n
            }
        }
        func save(_ id: String, baseRev: Int, text: String) async throws -> LoreSaveResult {
            try lock.withLock {
                if offline { throw CoreError.offline("demo") }
                guard var n = notes[id] else { throw CoreError.http(status: 404, code: "not_found", message: "") }
                var outcome = conflict ? "conflict" : "saved"
                var merged = text
                // The stand-in merge: text appended at the head since the base is kept after the client's text.
                if baseRev < n.rev, let base = history[id]?[baseRev], n.text.hasPrefix(base) {
                    merged = text + n.text.dropFirst(base.count)
                    outcome = "merged"
                }
                n.rev += 1
                n.text = merged
                notes[id] = n
                history[id, default: [:]][n.rev] = merged
                return LoreSaveResult(note: n, outcome: outcome, version: conflict ? "lv_1" : nil)
            }
        }
        /// Empties a day's note: the blank page of L1.
        func blank(day: String) {
            lock.withLock {
                for (id, n) in notes where n.day == day { notes[id]?.text = "" }
            }
        }
        /// Text an AI session appended at the head: returns the new rev.
        func append(_ id: String, _ line: String) -> Int {
            lock.withLock {
                notes[id]?.text += line
                notes[id]?.rev += 1
                guard let n = notes[id] else { return 0 }
                history[id, default: [:]][n.rev] = n.text
                return n.rev
            }
        }
        func projectNames() async throws -> [String: String] { ["7": "Garden Club Website"] }

        // R6-03: the stand-in's list, word search (one hit per note, the first match in bold) and Restore.
        func list(filter: LoreFilter) async throws -> [LoreNote] {
            lock.withLock {
                notes.values.filter { Self.match($0, filter) }.sorted { $0.id < $1.id }
            }
        }
        func search(_ query: String, filter: LoreFilter, limit: Int) async throws -> LoreSearchResult {
            lock.withLock {
                let hits: [LoreHit] = notes.values.filter { Self.match($0, filter) }.sorted { $0.id < $1.id }
                    .compactMap { n in
                        let flat = n.text.replacingOccurrences(of: "\n", with: " ")
                        guard let r = flat.range(of: query, options: .caseInsensitive) else { return nil }
                        let start = flat.utf8.distance(from: flat.startIndex, to: r.lowerBound)
                        let end = flat.utf8.distance(from: flat.startIndex, to: r.upperBound)
                        return LoreHit(
                            note: n, snippet: LoreSnippet(text: flat, matches: [LoreSpan(start: start, end: end)]))
                    }
                return LoreSearchResult(hits: Array(hits.prefix(limit)), semantic: true)
            }
        }
        func restore(_ id: String) async throws -> LoreNote {
            try lock.withLock {
                guard var n = notes[id] else { throw CoreError.http(status: 404, code: "not_found", message: "") }
                n.trashed = false
                notes[id] = n
                return n
            }
        }
        private static func match(_ n: LoreNote, _ f: LoreFilter) -> Bool {
            n.trashed == (f.state == "trashed") && (f.kind == nil || n.kind == f.kind)
                && (f.project == nil || n.project == f.project)
        }
    }

    public static let scenes = [
        "today-blank", "today", "past-day", "project-note", "conflict", "kept", "not-connected", "open-sheet",
    ]

    private let model: LoreModel
    private let service: Service

    public init(model: LoreModel) {
        self.model = model
        model.drafts = LoreDrafts(
            dir: FileManager.default.temporaryDirectory.appendingPathComponent("lore-demo-drafts"))
        let today = LoreModel.key(Date())
        let yesterday = LoreModel.key(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        service = Service([
            LoreNote(id: "ln_demotodayaaa", kind: "daily", day: today, title: "", rev: 3, text: Self.todayText),
            LoreNote(id: "ln_demopastaaaa", kind: "daily", day: yesterday, title: "", rev: 5, text: Self.pastText),
            LoreNote(
                id: "ln_demoprojecta", project: "7", title: "Launch checklist", rev: 2, text: Self.projectText),
            LoreNote(
                id: "ln_demoshedplan", title: "Shed plan", rev: 4, text: "# Shed plan\n\nA lean-to shed by the fence.",
                trashed: true),
        ])
    }

    public func show(_ scene: String) async {
        model.host.shell.closeDialog()
        model.detach()
        service.conflict = false
        service.offline = false
        service.reset()
        try? FileManager.default.removeItem(at: model.drafts.dir)
        if scene != "not-connected" {
            model.use(service)
            try? await Task.sleep(for: .milliseconds(300))
        }
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "today-blank":
            service.blank(day: model.todayKey)
            await model.openDay(model.todayKey)
        case "today": await model.openDay(model.todayKey)
        case "past-day": model.step(-1)
        case "project-note": await model.openNote("ln_demoprojecta")
        case "conflict":
            await model.openNote("ln_demoprojecta")
            service.conflict = true
            model.page.show(Self.projectText + "\n- [ ] Ask Mira about the photos\n", fold: false)
            await model.save()
        case "kept":
            await model.openDay(model.todayKey)
            service.offline = true
            model.page.show(Self.todayText + "\nA line written while the Core was away.\n", fold: false)
            await model.save()
        case "open-sheet":
            await model.openDay(model.todayKey)
            LoreOpenSheet.open(model)
        default: break
        }
    }

    /// Quick capture over whatever app is in front: `quick`, `advanced` or `error`, with made-up text, left open.
    public func capture(_ scene: String) {
        model.use(service)
        let c = model.capture
        c.text = "Ask Mira whether the seed swap moves to Saturday"
        c.advanced = scene == "advanced"
        c.project = scene == "advanced" ? "7" : ""
        c.error =
            scene == "error" ? "Unable to save: The Core did not answer. Your text is still here." : nil
        c.open()
    }

    // MARK: checks for the walk

    /// An AI session appends to the open note on the Core, and the event arrives.
    public func remoteAppend(_ line: String) {
        guard let id = model.note?.id else { return }
        let rev = service.append(id, line)
        model.remote(["id": id, "rev": String(rev), "origin": "session"])
    }

    /// The Core link drops (saves fail) or comes back (`linkUp` sends the draft).
    public func setOffline(_ on: Bool) {
        service.offline = on
        if !on { model.linkUp() }
    }

    public var syncWords: String { model.syncWords }
    public var hasDraft: Bool { model.note.map { model.drafts.read($0.id) != nil } ?? false }
    public func coreText() async -> String {
        guard let id = model.note?.id else { return "" }
        return (try? await service.note(id).text) ?? ""
    }

    static let todayText = """
        # Morning pages

        Slow start. The kettle took forever and the light over the yard was grey and soft.

        - Water the tomato seedlings
        - Sketch the new shelf for the hallway
        - [ ] Call the bike shop about the wheel
        - [x] Send the garden club minutes

        A thought worth keeping: small notes every day beat one long note a month.
        """

    static let pastText = """
        # A quiet Monday

        Walked the long way round the park. The pond has ducks again.

        ## Reading
        - Half of *The Wandering Orchard*, slow and lovely
        - An essay on hand-bound notebooks

        Tomorrow: finish the shelf drawing.
        """

    static let projectText = """
        # Launch checklist

        The club site goes live once these are done.

        - [x] Pick the colour scheme
        - [x] Write the welcome page
        - [ ] Add the plot map
        - [ ] Test the sign-up form on a phone

        Notes from the last meeting are in [[Meeting notes]].
        """
}

#endif
