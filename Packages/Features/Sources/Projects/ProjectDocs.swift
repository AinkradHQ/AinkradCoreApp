// ProjectDocs — the Docs page of a project's space (plan R6-06): the project's Lore notes grouped by tag (plans, specs,
// runbooks, other), a search inside the project, "Import from repo…" (R4-02's `LoreImport.fromRepo`), New Doc, and a click
// opens the note in the Lore space. Note text is outside data: it is read only to find its `#tags`, and titles and snippets
// are shown as plain text, never as links.
import CoreKit
import CoreUI
import LoreImport
import Observation
import SwiftUI

/// The four groups of the page.
enum DocGroup: Int, CaseIterable, Identifiable {
    case plans, specs, runbooks, other
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .plans: "Plans"
        case .specs: "Specs"
        case .runbooks: "Runbooks"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .plans: "list.bullet.rectangle"
        case .specs: "doc.text"
        case .runbooks: "checklist"
        case .other: "doc"
        }
    }

    /// The first of `#plan(s)`, `#spec(s)`, `#runbook(s)` in the text (any case), else Other.
    /// ponytail: a `#tag` inside a code block counts too; the Core's own tag list would be exact once the list route carries tags.
    static func of(text: String) -> DocGroup {
        var found = Set<DocGroup>()
        for word in text.split(whereSeparator: { $0.isWhitespace }) where word.first == "#" {
            let tag = word.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.lowercased()
            switch tag {
            case "plan", "plans": found.insert(.plans)
            case "spec", "specs": found.insert(.specs)
            case "runbook", "runbooks": found.insert(.runbooks)
            default: break
            }
        }
        return [DocGroup.plans, .specs, .runbooks].first(where: found.contains) ?? .other
    }
}

struct DocItem: Identifiable, Equatable {
    var id: String
    var title: String
    var group: DocGroup
}

@MainActor @Observable
final class ProjectDocs {
    enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }

    /// How many notes are read for their tags; the rest of a larger project list as Other.
    static let tagReadLimit = 100

    @ObservationIgnored unowned let model: ProjectsModel
    let project: ProjectItem
    var phase = Phase.loading
    var docs: [DocItem] = []
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    /// nil = not searching; the hits of the typed words otherwise.
    var hits: [DocItem]?
    var notice: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
    }

    private var pid: String { String(project.id) }
    var canImport: Bool { LoreImport.supports(model.lore) && !model.readOnly }

    func grouped() -> [(DocGroup, [DocItem])] {
        DocGroup.allCases.compactMap { g in
            let rows = docs.filter { $0.group == g }
            return rows.isEmpty ? nil : (g, rows)
        }
    }

    func load() async {
        guard let service = model.lore else {
            phase = .failed("Not connected to the Core.")
            return
        }
        do {
            let notes = try await service.list(filter: LoreFilter(kind: "note", project: pid))
            phase = .ready
            docs = notes.map { DocItem(id: $0.id, title: Self.title($0), group: .other) }
            let read = Array(notes.prefix(Self.tagReadLimit))
            // Eight reads at a time: a project with many notes does not open a hundred requests at once.
            var groups: [String: DocGroup] = [:]
            for chunk in stride(from: 0, to: read.count, by: 8).map({ Array(read[$0..<min($0 + 8, read.count)]) }) {
                await withTaskGroup(of: (String, DocGroup)?.self) { all in
                    for n in chunk {
                        all.addTask { (try? await service.note(n.id)).map { (n.id, DocGroup.of(text: $0.text)) } }
                    }
                    for await r in all { if let r { groups[r.0] = r.1 } }
                }
            }
            for i in docs.indices { docs[i].group = groups[docs[i].id] ?? .other }
        } catch {
            phase = .failed("Unable to load the docs. Check the connection to the Core and try again.")
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            hits = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let service = model.lore else { return }
            do {
                let r = try await service.search(
                    words, filter: LoreFilter(kind: "note", project: pid), limit: 40)
                guard !Task.isCancelled else { return }
                hits = r.hits.map { DocItem(id: $0.note.id, title: Self.title($0.note), group: .other) }
            } catch {
                guard !Task.isCancelled else { return }
                hits = []
                notice = "Unable to search the docs."
            }
        }
    }

    func open(_ id: String) { model.openNote?(id) }

    /// A blank note in this project, opened in Lore at once.
    func newDoc() {
        guard let service = model.lore else { return }
        Task {
            do {
                let n = try await service.create(text: "", project: pid)
                open(n.id)
                await load()
            } catch { notice = "Unable to create the doc." }
        }
    }

    func importFromRepo() {
        let names = Dictionary(
            model.projects.map { (String($0.id), $0.name) }, uniquingKeysWith: { a, _ in a })
        LoreImport.fromRepo(host: model.host, service: model.lore, projects: names, project: pid)
    }

    static func title(_ n: LoreNote) -> String { n.title.isEmpty ? "Untitled" : n.title }
}

struct DocsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var docs: ProjectDocs
    @State private var settled = false
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _docs = State(initialValue: ProjectDocs(model: model, project: project))
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            docsIsland
            if insights.supported { aiDocs.frame(width: Space.s8 * 14) }
        }
        .task(id: project.id) { await insights.loadDocs() }
    }

    /// Notes an AI session wrote in its folder (E10): a person's edit saves back to the file.
    private var aiDocs: some View {
        let list = insights.docs ?? []
        return Island("AI documents", sub: "Edits save back to the file") {
            ScrollView {
                VStack(spacing: Space.s1) {
                    if list.isEmpty {
                        Text("None yet. Documents an AI session writes show up here.").foregroundStyle(
                            GlassInk.secondary)
                    }
                    ForEach(list) { d in
                        CoreRow(
                            d.title.isEmpty ? d.path : d.title, subtitle: d.sessionTitle.map { "From “\($0)”" },
                            symbol: "sparkles"
                        ) {
                            docs.open(d.note)
                        }
                    }
                }
            }
        }
    }

    private var docsIsland: some View {
        Island(
            title: "Docs", sub: docs.phase == .ready && !docs.docs.isEmpty ? "\(docs.docs.count) in this project" : nil,
            accessory: {
                if !docs.docs.isEmpty {
                    FilterField(text: Bindable(docs).query, label: "Search docs")
                }
                CoreIconButton(symbol: "arrow.clockwise", label: "Reload the docs") { Task { await docs.load() } }
                Button {
                    docs.importFromRepo()
                } label: {
                    Label("Import from repo…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(!docs.canImport)
                .help(
                    docs.canImport
                        ? "Bring this project’s Markdown docs in from its repos"
                        : "Not available while this device cannot change projects or the Core is unreachable")
                Button {
                    docs.newDoc()
                } label: {
                    Label("New Doc", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.readOnly || model.lore == nil)
                .help("Write a new doc in \(project.name)")
            }
        ) {
            content
        }
        .coreRise(settled, 0)
        .onAppear { settled = true }
        .task(id: project.id) { await docs.load() }
        .accessibilityIdentifier("project-page-Docs")
    }

    @ViewBuilder private var content: some View {
        switch docs.phase {
        case .loading:
            Text("Loading docs…").foregroundStyle(GlassInk.secondary)
        case .failed(let why):
            CoreStateCard(
                symbol: "exclamationmark.triangle", title: "Unable to Load Docs", line: why,
                primary: CoreAction("Try Again") { Task { await docs.load() } }
            )
            .frame(maxWidth: .infinity)
        case .ready where docs.docs.isEmpty:
            CoreStateCard(
                symbol: "doc.text", title: "No Docs Yet",
                line: "Import the Markdown docs from this project’s repos, or write the first one.",
                secondary: CoreAction("New Doc") { docs.newDoc() },
                primary: docs.canImport ? CoreAction("Import from Repo…") { docs.importFromRepo() } : nil
            )
            .frame(maxWidth: .infinity)
        case .ready:
            list
        }
    }

    @ViewBuilder private var list: some View {
        if let notice = docs.notice {
            Text(notice).foregroundStyle(GlassInk.secondary)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s1) {
                if let hits = docs.hits {
                    if hits.isEmpty {
                        Text("No doc matches “\(docs.query)”.").foregroundStyle(GlassInk.secondary)
                    }
                    ForEach(hits) { row($0) }
                } else {
                    ForEach(docs.grouped(), id: \.0) { group, rows in
                        Text(group.title).coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(GlassInk.secondary)
                            .padding(.top, Space.s3).padding(.horizontal, Space.s3)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(rows) { row($0, symbol: group.symbol) }
                    }
                }
            }
        }
    }

    private func row(_ d: DocItem, symbol: String = "doc.text") -> some View {
        CoreRow(d.title, symbol: symbol) { docs.open(d.id) }
            .help("Open “\(d.title)” in Lore")
    }
}
