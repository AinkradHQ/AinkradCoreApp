// LoreModel — the Lore space (plan R6-01): today's note on open, ‹ › days, New, autosave (T2), remote fold-in and local
// drafts (T3).
//
// Security model. Note text is untrusted (imports, AI sessions). The editor renders no HTML and fetches nothing; the
// host (this model) is the gate for the internal links it hands over: only `lore:<note id>` opens a note and only
// `lore-attachment:<64 hex>` reaches the in-app viewer, never `NSWorkspace.open` (`LoreLink`). Drafts are written only
// under Application Support with names this app makes (`LoreDrafts.ok`), never from a name inside a note.
import Admin
import CoreKit
import CoreUI
import Foundation
import LoreEditor
import OSLog
import Observation
import Shell
import SwiftUI

/// The page the model writes into: the editor in the app, a stand-in in tests.
@MainActor protocol LorePageText: AnyObject {
    func markdown() -> String
    /// Replaces the page. `fold`: a change from elsewhere, so the caret and the scroll stay where they were.
    func show(_ markdown: String, fold: Bool)
    func focus()
    /// The person is mid-composition (an input method's marked text): a fold waits.
    var composing: Bool { get }
}

enum LoreLoad: Equatable {
    case notConnected, loading, ready
    case failed(String)
    /// The Core has no Lore module (it answered 404).
    case absent
}

/// What the top bar says about the open note's text.
enum LoreSync: Equatable {
    case saved, saving
    /// The Core could not take it: the text is a draft on this Mac until the link is back.
    case kept
}

@MainActor @Observable
public final class LoreModel {
    let host: any AdminHost
    var service: (any LoreService)?
    var load: LoreLoad = .notConnected
    /// The open daily note's day (`YYYY-MM-DD`), or nil when a plain note is open.
    private(set) var day: String?
    /// The open note; nil on a past day the Core has no note for yet (made on the first save).
    private(set) var note: LoreNote?
    private(set) var sync: LoreSync = .saved
    /// One line under the top bar: a conflict kept as a version, a refused save, a link that was not opened.
    var notice: String? { didSet { noticeAction = nil } }
    /// The button on the notice line, set right after the line itself.
    var noticeAction: LoreNoticeAction?
    /// Notes linking to the open one (R6-04); the island shows only when this is not empty.
    private(set) var backlinks: [LoreBacklink] = []
    var projectNames: [String: String] = [:]

    // Sidebars (E10-1). Both open by default; ⌘. hides both (focus), ⌘[ the left, ⌘] the right.
    var showLeft = LoreSidebarPrefs.read("left") { didSet { LoreSidebarPrefs.write("left", showLeft) } }
    var showRight = LoreSidebarPrefs.read("right") { didSet { LoreSidebarPrefs.write("right", showRight) } }
    /// Every live note without its text, newest change first (the tree, recents, project counts).
    var sideNotes: [LoreNote] = []
    var sideTags: [LoreTagCount] = []
    var sessionDocs: [LoreSessionDoc] = []
    var sideVersions: [LoreVersion] = []
    var outline: [LoreHeading] = []
    var wordCount = 0
    var hasTable = false
    var noteTags: [String] = []
    /// The caret is inside a table (the row and column tools are live).
    var caretInTable = false
    var tablesAsText = false
    /// A project, tag or search the left sidebar is filtered to; `filterHits` are its notes.
    var sideFilter: LoreSideFilter?
    var filterHits: [LoreNote] = []
    @ObservationIgnored var outlineTask: Task<Void, Never>?
    @ObservationIgnored var filterTask: Task<Void, Never>?
    /// The Core serves `/tags` and `/session-docs` (minor 95); true until a connection says otherwise.
    @ObservationIgnored var serves95 = true
    /// Opens an AI session in the Agents space (wired by the app; Lore does not depend on Agents).
    @ObservationIgnored public var openSession: (@MainActor (String) -> Void)?

    @ObservationIgnored let page: any LorePageText
    /// Quick capture ⇧⌘N (R6-05).
    @ObservationIgnored public private(set) lazy var capture = QuickCapture(lore: self)
    @ObservationIgnored let editor: LoreEditorController?
    @ObservationIgnored var drafts: LoreDrafts
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var debounce: Duration = .milliseconds(800)
    /// The revision the page was edited from (0: no note yet) and the text the Core has at it.
    @ObservationIgnored private(set) var base = 0
    @ObservationIgnored private var synced = ""
    @ObservationIgnored private var saving = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var opening = 0
    @ObservationIgnored private var registeredNotes: Set<String> = []
    @ObservationIgnored private var backlinkOwner = ""
    /// The space was opened since the Core was attached.
    @ObservationIgnored private var opened = false
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.ainkrad.core", category: "lore")
    @ObservationIgnored private var openSign: OSSignpostIntervalState?

    public convenience init(host: any AdminHost) {
        let editor = LoreEditorController()
        self.init(host: host, page: EditorPage(editor), editor: editor, drafts: .standard)
    }

    init(host: any AdminHost, page: any LorePageText, editor: LoreEditorController? = nil, drafts: LoreDrafts) {
        self.host = host
        self.page = page
        self.editor = editor
        self.drafts = drafts
        editor?.onChange = { [weak self] in self?.changed() }
        editor?.onTable = { [weak self] in self?.caretInTable = $0 }
        editor?.onOpenInternal = { [weak self] in self?.openInternal($0) }
        editor?.onNotice = { [weak self] in self?.host.shell.showToast($0, kind: .info) }
    }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        use(LiveLoreService(connection: connection))
        Task { [weak self] in
            let ok = await connection.serverSupports(minor: 95)
            self?.serves95 = ok
            await self?.refreshSide()
        }
    }

    func use(_ service: any LoreService) {
        self.service = service
        load = .loading
        Task {
            projectNames = (try? await service.projectNames()) ?? [:]
            await syncLauncherNotes()
            // Today's note is made on the first open of the space (T7), not on every connect.
            if opened { await reload() }
        }
    }

    public func detach() {
        timer?.cancel()
        opened = false
        service = nil
        note = nil
        backlinks = []
        sideNotes = []
        sideTags = []
        sessionDocs = []
        sideVersions = []
        outline = []
        day = nil
        base = 0
        synced = ""
        load = .notConnected
        sync = .saved
        notice = nil
        page.show("", fold: false)
    }

    /// The Core link is live again: send what is waiting, or load what failed.
    public func linkUp() {
        guard service != nil, opened else { return }
        if load == .ready {
            if dirty || sync == .kept { Task { await save() } }
        } else {
            Task { await reload() }
        }
    }

    /// `lore.note.changed {id, rev, origin}` (ids only, T3): the open note changed on the Core.
    public func remote(_ fields: [String: String]) {
        Task { await refreshSide() }
        guard let id = fields["id"], id == note?.id, let rev = Int(fields["rev"] ?? ""), rev > base else { return }
        Task { await pull() }
    }

    // MARK: open

    /// Opens `id` in the Lore space (the Projects Docs page, R6-06). Lore's own pane, then that note, not today's.
    public func open(note id: String) {
        show(today: false)
        Task { await openNote(id) }
    }

    func show(today: Bool = true) {
        openSign = signposter.beginInterval("open", id: signposter.makeSignpostID())
        opened = true
        let shell = host.shell
        var spec = PaneSpec(id: "lore", title: "Lore", sub: "Notes", symbol: "text.book.closed", minWidth: 720) {
            LoreView(model: self)
        }
        spec.tab = "Lore"
        spec.fullScreenOnly = true
        spec.onNew = { [weak self] in Task { await self?.newNote() } }
        shell.openPane(spec)
        if today, load != .ready { Task { await openDay(todayKey) } }
    }

    /// The page is on screen and takes typing (L1). Ends the open signpost.
    func ready() {
        page.focus()
        if let s = openSign {
            signposter.endInterval("open", s)
            openSign = nil
        }
    }

    var todayKey: String { Self.key(now()) }
    var isToday: Bool { day == todayKey }

    func step(_ days: Int) {
        let from = day.flatMap(Self.date) ?? now()
        guard let to = Calendar.current.date(byAdding: .day, value: days, to: from) else { return }
        Task { await openDay(Self.key(to)) }
    }

    func openDay(_ key: String) async {
        opened = true
        await leave()
        day = key
        note = nil
        await reload()
    }

    func openNote(_ id: String) async {
        guard LoreLink.isNoteID(id) else { return }
        opened = true
        await leave()
        day = nil
        note = LoreNote(id: id)
        await reload()
    }

    /// New ⌘N: a blank note in the open note's project (personal from a daily note), opened at once. R6-03's advanced
    /// line passes the chosen project (`nil` = personal) and tags, which go into the text as `#tag` words.
    func newNote(inProject chosen: String?? = nil, tags: [String] = []) async {
        guard let service, load == .ready else { return }
        await leave()
        do {
            let n = try await service.create(
                text: LoreTags.text(tags), project: chosen ?? (note?.kind == "note" ? note?.project : nil))
            day = nil
            apply(n)
        } catch { say(error) }
    }

    func reload() async {
        guard let service else {
            load = .notConnected
            return
        }
        opening += 1
        let mine = opening
        if note?.text.isEmpty ?? true { load = .loading }
        do {
            let n: LoreNote?
            if let day {
                n = day == todayKey ? try await service.today(day) : try await service.daily(day)
            } else if let id = note?.id {
                n = try await service.note(id)
            } else {
                n = try await service.today(todayKey)
                day = todayKey
            }
            guard mine == opening else { return }
            apply(n)
            Task { await syncLauncherNotes() }
        } catch {
            guard mine == opening else { return }
            switch Self.status(error) {
            case 404 where note != nil && day == nil: load = .failed("That note is gone.")
            case 404, 501: load = .absent
            default: load = .failed(words(error))
            }
        }
    }

    /// Shows a note (or a day without one), taking a waiting draft over the Core's text: the next save merges it.
    func apply(_ n: LoreNote?) {
        note = n
        if let d = n?.day { day = d }
        base = n?.rev ?? 0
        synced = n?.text ?? ""
        notice = n?.trashed == true ? "This note is in the trash." : nil
        refreshBacklinks()
        let draft = n.flatMap { drafts.read($0.id) } ?? day.flatMap { drafts.read("day-\($0)") }
        let waiting = draft.map { $0.text != synced } ?? false
        if let draft, waiting {
            base = n == nil ? 0 : max(draft.base, 1)
            page.show(draft.text, fold: false)
            schedule(.zero)
        } else {
            page.show(synced, fold: false)
            if let n { drafts.remove(n.id) }
            if let day { drafts.remove("day-\(day)") }
        }
        sync = waiting ? .kept : .saved
        load = .ready
        refreshOutline(after: .zero)
        Task { await refreshSide() }
    }

    /// Before the page changes: send what was typed.
    func leave() async {
        timer?.cancel()
        if dirty { await save() }
    }

    // MARK: save (T2)

    var dirty: Bool { load == .ready && page.markdown() != synced }

    func changed() {
        guard load == .ready else { return }
        schedule(debounce)
        refreshOutline(after: .milliseconds(400))
    }

    private func schedule(_ wait: Duration) {
        timer?.cancel()
        timer = Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Sends the page. Stale: the Core merges it with the head and the answer is folded back in. Unsent text is a draft.
    func save() async {
        guard let service, load == .ready, note?.trashed != true else { return }
        if saving {
            again = true
            return
        }
        let text = page.markdown()
        guard text != synced || sync == .kept else { return }
        let key = note?.id ?? day.map { "day-\($0)" } ?? ""
        drafts.write(key, base: base, text: text)
        saving = true
        sync = .saving
        defer {
            saving = false
            if again || (dirty && sync != .kept) {
                again = false
                schedule(debounce)
            }
        }
        do {
            var target = note
            var from = base
            if target == nil, let day {
                // A past day's first words: the Core makes its note now. Rev 1 is its empty start, so the save merges.
                let made = try await service.today(day)
                target = made
                note = made
                from = 1
                drafts.remove(key)
                drafts.write(made.id, base: from, text: text)
                base = from
            }
            guard let id = target?.id else { return }
            let r = try await service.save(id, baseRev: from, text: text)
            note = r.note
            if r.keptVersion {
                notice =
                    "Changed elsewhere at the same time. Your lines were kept; the other text is saved as a version."
                if let v = r.version { noticeAction = .seeChanges(v) }
            }
            if page.markdown() == text {
                if r.note.text != text { fold(r.note.text) }
                synced = r.note.text
                base = r.note.rev
                drafts.remove(id)
            } else if r.note.text == text {
                // Typed on while it was sent: the page is that text plus more, edited from the new head.
                synced = text
                base = r.note.rev
            } else {
                // Typed on, and the Core merged in text from elsewhere: send again from the old base so it merges.
                again = true
            }
            sync = .saved
        } catch {
            sync = .kept
            switch error {
            case CoreError.bodyTooLarge:
                notice = "This note is too long to send. It is kept on this Mac."
            case CoreError.http(409, _, _):
                notice = "This note is in the trash. It is kept on this Mac."
            default: break
            }
        }
    }

    /// The open note changed on the Core: typed text goes up to merge; an untouched page takes the head.
    private func pull() async {
        if dirty || saving {
            schedule(.zero)
            return
        }
        guard let service, let id = note?.id else { return }
        guard let n = try? await service.note(id), n.id == note?.id, n.rev > base, !dirty, !saving else {
            if dirty { schedule(.zero) }
            return
        }
        note = n
        if n.text != synced { fold(n.text) }
        synced = n.text
        base = n.rev
    }

    private func fold(_ text: String) {
        if page.composing {
            // ponytail: the fold waits for the next save, which merges the head in.
            again = true
            return
        }
        page.show(text, fold: true)
    }

    // MARK: history (R6-04: `LoreHistory.swift`)
    /// A restore made `n` the head: the page shows it (the caret stays near where it was) and the base moves up.
    func adopt(_ n: LoreNote) {
        note = n
        synced = n.text
        base = n.rev
        drafts.remove(n.id)
        page.show(n.text, fold: true)
        sync = .saved
        refreshBacklinks()
        refreshOutline(after: .zero)
        Task { await refreshSide() }
    }

    /// The note moved projects: only the project changes, so typed text and the base stay.
    func moved(_ n: LoreNote) { note?.project = n.project }

    func refreshBacklinks() {
        guard let service, let id = note?.id, load != .absent else {
            backlinks = []
            return
        }
        if id != backlinkOwner { backlinks = [] }
        backlinkOwner = id
        Task {
            let list = (try? await service.backlinks(id)) ?? []
            if note?.id == id { backlinks = list }
        }
    }

    // MARK: links

    func openInternal(_ url: URL) {
        switch LoreLink(url) {
        case .note(let id): Task { await openNote(id) }
        // TODO(R1-05): the in-app attachment viewer, from `GET /modules/lore/v1/attachments/{sha}`.
        case .attachment: host.shell.showToast("Attachments come later.", kind: .info)
        case nil: host.shell.showToast("That link does not open from a note.", kind: .info)
        }
    }

    // MARK: words

    var title: String {
        if let day, let d = Self.date(day) {
            return d.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        }
        let t = note?.title.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? "Untitled note" : t
    }

    var projectName: String {
        guard let p = note?.project else { return "Personal" }
        return projectNames[p] ?? "Project"
    }

    var syncWords: String {
        switch sync {
        case .saved: ""
        case .saving: "Saving…"
        case .kept: "Kept on this Mac"
        }
    }

    func say(_ error: any Error) { host.shell.showToast(words(error), kind: .warn) }

    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        return (CoreFailure.of(error) ?? CoreError.unwrapping(error))?.localizedDescription
            ?? error.localizedDescription
    }

    static func status(_ error: any Error) -> Int {
        if case .http(let s, _, _)? = CoreFailure.of(error) ?? CoreError.unwrapping(error) { return s }
        return 0
    }

    // MARK: dates

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
        shell.launcher.register(
            LauncherEntry(
                id: "lore", title: "Lore", sub: "Today's note, and every note on your Core", symbol: "text.book.closed",
                keywords: ["notes", "note", "today", "daily", "journal", "write", "docs"]
            ) { [weak self] in self?.show() })
        shell.launcher.register(
            LauncherEntry(
                id: "lore-capture", title: "Quick capture", sub: "Add a line to today's note from any app  ⇧⌘N",
                symbol: "square.and.pencil", keywords: ["note", "capture", "jot", "today", "lore"], isAction: true
            ) { [weak self] in self?.capture.toggle() })
        shell.settings.section(
            SettingsSection(
                id: "lore", group: .apps, title: "Lore", sub: "The quick capture shortcut", symbol: "text.book.closed",
                order: 40
            ) { [capture] in LoreSettingsSection(capture: capture) })
        shell.launcher.registerFallback(
            LauncherFallback(id: "lore-search", symbol: "magnifyingglass", title: { "Search notes for “\($0)”" }) {
                [weak self] q in if let self { LoreOpenSheet.open(self, query: q) }
            })
        shell.launcher.registerFallback(
            LauncherFallback(id: "lore-new", symbol: "square.and.pencil", title: { _ in "New note" }) { [weak self] _ in
                guard let self else { return }
                self.show(today: false)
                Task { await self.newNote() }
            })
        capture.start()
        Task { await syncLauncherNotes() }
    }

    /// The eight most recent notes as launcher entries (⌘K → Notes).
    func syncLauncherNotes() async {
        guard let service, let list = try? await service.list(filter: LoreFilter(state: "active", kind: nil, project: nil, tag: nil))
        else { return }
        let shell = host.shell
        let names = projectNames
        let recent = list.prefix(8).map { LoreFinder.row($0, names, nil) }
        let ids = Set(recent.map { "note-\($0.id)" })
        for gone in registeredNotes.subtracting(ids) { shell.launcher.unregister(gone) }
        for r in recent {
            shell.launcher.register(
                LauncherEntry(id: "note-\(r.id)", title: r.title, sub: r.sub, symbol: r.symbol, keywords: ["note", "lore"]) {
                    [weak self] in self?.open(note: r.id)
                })
        }
        registeredNotes = ids
    }
}

/// The editor as the model's page. A fold keeps the caret on the same text and the scroll where it was.
@MainActor final class EditorPage: LorePageText {
    let editor: LoreEditorController
    init(_ editor: LoreEditorController) { self.editor = editor }

    private var view: NSTextView? { editor.scrollView.documentView as? NSTextView }

    func markdown() -> String { editor.markdown() }
    func focus() { editor.focus() }
    var composing: Bool { view?.hasMarkedText() ?? false }

    func show(_ markdown: String, fold: Bool) {
        guard fold, let tv = view else { return editor.load(markdown: markdown) }
        // ponytail: the editor's `load` clears undo; a fold that keeps the undo stack needs an editor seam (proposal).
        let old = tv.string
        let sel = tv.selectedRange()
        let origin = editor.scrollView.contentView.bounds.origin
        editor.load(markdown: markdown)
        let new = tv.string
        let start = LoreFold.caret(sel.location, from: old, to: new)
        let end = LoreFold.caret(NSMaxRange(sel), from: old, to: new)
        tv.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        editor.scrollView.contentView.scroll(to: origin)
        editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
    }
}
