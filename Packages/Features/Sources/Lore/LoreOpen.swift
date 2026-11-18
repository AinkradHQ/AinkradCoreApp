// LoreOpen — plan R6-03. ⌘O: search (hybrid, with highlighted snippets), recent notes, the filters (project, tag, daily,
// trash), the trash list with Restore, New (quick, or advanced with a project and tags) and Export… (the R1-06 zip).
//
// Search text and filter values go to the Core as escaped query items (`LiveLoreService`), never into a path. Note text
// comes back only inside a snippet and is shown as plain text: no Markdown, no links, nothing is opened from it.
import AppKit
import CoreKit
import CoreUI
import Observation
import Shell
import SwiftUI
import UniformTypeIdentifiers

enum LoreScope: Hashable, Sendable { case notes, daily, trash }

/// One line of the sheet: a recent note, a hit, or a trashed note.
struct LoreRow: Identifiable, Equatable {
    var id: String
    var title: String
    var sub: String
    var symbol: String
    var snippet: LoreSnippet?
    var trashed: Bool
}

/// Tags typed as words ("garden, #plans") become `#tag` words in a new note's text (the Core reads tags from the text).
enum LoreTags {
    static let max = 10

    static func parse(_ s: String) -> [String] {
        var seen = Set<String>()
        return s.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map {
                String($0.drop(while: { $0 == "#" })).filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(max).map { $0 }
    }

    /// The new note's text: a blank first line, then the tags. No tags = an empty page.
    static func text(_ tags: [String]) -> String {
        tags.isEmpty ? "" : "\n" + tags.map { "#" + $0 }.joined(separator: " ") + "\n"
    }
}

/// Matched words in bold on the tint. The Core's spans are UTF-8 byte offsets: one that is out of range, reversed or
/// inside a character is skipped, never trusted.
enum LoreHighlight {
    static func attributed(_ s: LoreSnippet, tint: Color) -> AttributedString {
        var out = AttributedString(s.text)
        let u = s.text.utf8
        for m in s.matches where m.start >= 0 && m.start < m.end && m.end <= u.count {
            let a = u.index(u.startIndex, offsetBy: m.start)
            let b = u.index(u.startIndex, offsetBy: m.end)
            guard let lo = a.samePosition(in: s.text), let hi = b.samePosition(in: s.text),
                let r = Range(lo..<hi, in: out)
            else { continue }
            out[r].inlinePresentationIntent = .stronglyEmphasized
            out[r].foregroundColor = tint
        }
        return out
    }
}

@MainActor @Observable
final class LoreFinder {
    enum Phase: Equatable {
        case loading, ready
        /// A tag filter with no word: the Core searches words only.
        case needsWord
        case failed(String)
    }

    @ObservationIgnored unowned let lore: LoreModel
    var query = "" { didSet { if query != oldValue { refresh(wait: true) } } }
    var scope = LoreScope.notes { didSet { if scope != oldValue { refresh(wait: false) } } }
    /// The project id as text; "" = every project.
    var project = "" { didSet { if project != oldValue { refresh(wait: false) } } }
    var tag = "" { didSet { if tag != oldValue { refresh(wait: true) } } }
    private(set) var rows: [LoreRow] = []
    private(set) var phase = Phase.loading
    /// false = the Core searched by words only (its model is not ready).
    private(set) var semantic = true
    private(set) var exporting = false
    /// The row ↑↓ and Return act on.
    var picked = 0
    // The advanced New sheet.
    var newProject = ""
    var newTags = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Recent notes shown when nothing is typed.
    static let recentMax = 30

    init(lore: LoreModel) { self.lore = lore }

    var filter: LoreFilter {
        let t = LoreTags.parse(tag).first
        return LoreFilter(
            state: scope == .trash ? "trashed" : "active", kind: scope == .daily ? "daily" : nil,
            project: project.isEmpty ? nil : project, tag: t)
    }

    var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func projectOptions(all: Bool) -> [CoreSelectOption<String>] {
        [
            all
                ? CoreSelectOption("", "All projects", symbol: "tray.full")
                : CoreSelectOption("", "Personal", symbol: "person")
        ]
            + lore.projectNames.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
            .map { CoreSelectOption($0.key, $0.value, symbol: "folder") }
    }

    // MARK: find

    /// Reads the Core for the current query and filters. A newer ask makes an older answer fall away.
    func refresh(wait: Bool) {
        task?.cancel()
        guard let service = lore.service else {
            rows = []
            phase = .failed("Not connected to your Core.")
            return
        }
        let q = typed
        let f = filter
        if q.isEmpty, f.tag != nil {
            rows = []
            phase = .needsWord
            return
        }
        generation += 1
        let mine = generation
        let names = lore.projectNames
        if rows.isEmpty { phase = .loading }
        task = Task { [weak self] in
            if wait { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            do {
                let found: [LoreRow]
                var sem = true
                if q.isEmpty {
                    found = try await service.list(filter: f).prefix(Self.recentMax).map { Self.row($0, names, nil) }
                } else {
                    let r = try await service.search(q, filter: f, limit: 30)
                    sem = r.semantic
                    found = r.hits.map { Self.row($0.note, names, $0.snippet) }
                }
                guard let self, mine == self.generation else { return }
                self.rows = found
                self.semantic = sem
                self.picked = 0
                self.phase = .ready
            } catch {
                guard let self, mine == self.generation, !(error is CancellationError) else { return }
                self.rows = []
                self.phase = .failed(self.lore.words(error))
            }
        }
    }

    static func row(_ n: LoreNote, _ names: [String: String], _ snippet: LoreSnippet?) -> LoreRow {
        var title = n.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title =
                n.day.flatMap(LoreModel.date).map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) }
                ?? "Untitled note"
        }
        let place = n.project.map { names[$0] ?? "Project" } ?? "Personal"
        return LoreRow(
            id: n.id, title: title, sub: n.kind == "daily" ? "Daily note" : place,
            symbol: n.trashed ? "trash" : n.kind == "daily" ? "calendar" : "doc.text", snippet: snippet,
            trashed: n.trashed)
    }

    // MARK: keys and open

    func move(_ step: Int) {
        guard !rows.isEmpty, scope != .trash else { return }
        picked = min(max(picked + step, 0), rows.count - 1)
    }

    /// Return, or a click: opens the picked note and closes the sheet. In the trash nothing opens (Restore is the action).
    func openPicked() {
        guard scope != .trash, rows.indices.contains(picked) else { return }
        open(rows[picked])
    }

    func open(_ row: LoreRow) {
        lore.host.shell.closeDialog()
        Task { await lore.openNote(row.id) }
    }

    // MARK: trash

    func restore(_ row: LoreRow) async {
        guard let service = lore.service else { return }
        do {
            _ = try await service.restore(row.id)
            rows.removeAll { $0.id == row.id }
            picked = min(picked, max(rows.count - 1, 0))
            if lore.note?.id == row.id { await lore.reload() }
            lore.host.shell.showToast("Restored “\(row.title)”", kind: .ok)
        } catch { lore.host.shell.showToast("Unable to restore: \(lore.words(error))", kind: .warn) }
    }

    // MARK: new

    /// New Note: blank, in the open note's project (personal from a daily note), at once.
    func quickNew() {
        lore.host.shell.closeDialog()
        Task { await lore.newNote() }
    }

    func advancedNew() {
        newProject = lore.note?.kind == "note" ? lore.note?.project ?? "" : ""
        newTags = ""
        lore.host.shell.present(ShellDialog(id: "lore-new") { LoreNewView(finder: self) })
    }

    func createAdvanced() {
        lore.host.shell.closeDialog()
        let project = newProject.isEmpty ? nil : newProject
        let tags = LoreTags.parse(newTags)
        Task { await lore.newNote(inProject: project, tags: tags) }
    }

    func backToOpen() { lore.host.shell.present(ShellDialog(id: "lore-open") { LoreOpenView(finder: self) }) }

    // MARK: export

    /// Export…: asks where first, then downloads the zip (the project filter's notes, or all) and writes it there.
    func export() async {
        guard let service = lore.service, !exporting else { return }
        let pid = project.isEmpty ? nil : project
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = (pid.flatMap { lore.projectNames[$0] } ?? "Lore") + " notes.zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        defer { exporting = false }
        do {
            // ponytail: the zip is held in memory; a streamed download if a Core's notes ever outgrow that.
            let zip = try await service.export(project: pid)
            try zip.write(to: url, options: .atomic)
            lore.host.shell.showToast("Exported to \(url.lastPathComponent)", kind: .ok)
        } catch { lore.host.shell.showToast("Unable to export: \(lore.words(error))", kind: .warn) }
    }
}

/// ⌘O.
enum LoreOpenSheet {
    @MainActor static func open(_ model: LoreModel) {
        let finder = LoreFinder(lore: model)
        finder.refresh(wait: false)
        finder.backToOpen()
    }
}
