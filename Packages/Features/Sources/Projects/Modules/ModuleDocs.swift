import AppKit
import CoreUI
import SwiftUI

/// The Docs focused page (details v2): the project's docs grouped by kind with search and New Doc, the picked one as
/// a preview (title, meta, text) with Open, and "Ask the AI" to start an AI session about it. Reuses `ProjectDocs`.
struct ModuleDocs: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var docs: ProjectDocs
    @State private var insights: ProjectInsightsModel
    @State private var selected: String?
    @State private var text: String?
    @State private var textFailed = false

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _docs = State(initialValue: ProjectDocs(model: model, project: project))
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    private var aiDocs: [SessionDocItem] { insights.docs ?? [] }
    private var listed: [DocItem] { docs.hits ?? docs.docs }
    private var currentID: String? {
        if let selected,
            listed.contains(where: { $0.id == selected }) || aiDocs.contains(where: { $0.note == selected })
        {
            return selected
        }
        return listed.first?.id ?? aiDocs.first?.note
    }
    private var currentTitle: String {
        listed.first { $0.id == currentID }?.title
            ?? aiDocs.first { $0.note == currentID }.map { $0.title.isEmpty ? $0.path : $0.title } ?? "Untitled"
    }

    @State private var stageKind: ProjectKind? = .other

    var body: some View {
        // The approved details v2 page: the documents as large tiles on the stage, and the list beside it to search, open,
        // write a new one or ask the AI.
        HStack(alignment: .top, spacing: Space.s4) {
            OverviewStage(model: model, project: project, kind: $stageKind)
            side.frame(width: 340)
        }
        .task(id: project.id) { await docs.load() }
        .task(id: project.id) { await insights.loadDocs() }
        .accessibilityIdentifier("project-page-Docs")
    }

    private var side: some View {
        ModulePage(
            title: "Docs",
            tools: {
                if docs.canImport {
                    // An icon in the 340 pt panel; the words are in its tooltip.
                    Button {
                        docs.importFromRepo()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import from Repo")
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help(
                        "Bring this project’s Markdown docs in from its repos")
                }
                Button {
                    docs.newDoc()
                } label: {
                    Label("New Doc", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: model.creatingDoc.contains(project.id)))
                .disabled(model.readOnly || model.lore == nil || model.creatingDoc.contains(project.id))
                .help(model.lore == nil ? "Not connected to the Core" : "Write a new doc in \(project.name)")
            }
        ) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch docs.phase {
        case .loading: PgQuiet("Loading docs…").padding(.horizontal, Space.s5)
        case .failed(let why):
            ModuleQuiet(symbol: "exclamationmark.triangle", title: "Unable to load docs", line: why) {
                Button("Try Again") { Task { await docs.load() } }.buttonStyle(CoreButtonStyle(.prominent))
            }
        case .ready where docs.docs.isEmpty && aiDocs.isEmpty:
            ModuleQuiet(
                symbol: "doc.text", title: "No docs yet",
                line: "Write the first one, or import the Markdown docs from this project’s repos."
            ) {
                HStack(spacing: Space.s2) {
                    if docs.canImport {
                        Button("Import from Repo…") { docs.importFromRepo() }.buttonStyle(CoreButtonStyle(.secondary))
                    }
                    Button("New Doc") { docs.newDoc() }
                        .buttonStyle(CoreButtonStyle(.prominent, busy: model.creatingDoc.contains(project.id)))
                        .disabled(model.creatingDoc.contains(project.id))
                }
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) {
                    if !docs.docs.isEmpty {
                        FilterField(text: Bindable(docs).query, label: "Search documents").frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, Space.s1)
                    }
                    if let hits = docs.hits {
                        if hits.isEmpty { PgQuiet("No document matches “\(docs.query)”.").padding(Space.s3) }
                        ForEach(hits) { row($0.id, $0.title, "doc.text") }
                    } else {
                        ForEach(docs.grouped(), id: \.0) { g, rows in
                            PgGroup(g.title)
                            ForEach(rows) { row($0.id, $0.title, g.symbol) }
                        }
                        if !aiDocs.isEmpty {
                            PgGroup("From AI sessions")
                            ForEach(aiDocs) { row($0.note, $0.title.isEmpty ? $0.path : $0.title, "sparkles") }
                        }
                    }
                    PgBlock("Ask the AI") {
                        Text("Draft or improve these documents with an AI session in this project.")
                            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Start AI Session") { model.newSession(in: project) }
                            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                            .disabled(!model.canStartSession(project))
                            .help(model.sessionBlock(project))
                    }
                }
                .padding(.horizontal, Space.s3)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func row(_ id: String, _ title: String, _ symbol: String) -> some View {
        CoreRow(title, symbol: symbol, selected: currentID == id, action: { docs.open(id) }) {}
    }

    private func loadText() async {
        text = nil
        textFailed = false
        guard let id = currentID, let lore = model.lore else { return }
        do { text = try await lore.note(id).text } catch { if !Task.isCancelled { textFailed = true } }
    }

    @ViewBuilder private var detail: some View {
        if let id = currentID {
            let words = text.map { $0.split(whereSeparator: \.isWhitespace).count }
            PgHead(
                kicker: [listed.first { $0.id == id }.map { $0.group.title }, words.map { "\($0) words" }]
                    .compactMap { $0 }.joined(separator: " · "),
                title: currentTitle
            ) {
                Button {
                    docs.open(id)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).help("Open “\(currentTitle)” to read and edit it")
            }
            if let text {
                Text(preview(text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if textFailed {
                PgQuiet("The text could not be read. Try again in a moment.")
            } else {
                PgQuiet("Loading…")
            }
            PgBlock("Ask the AI") {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "sparkles").foregroundStyle(GlassInk.blue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(prompt)
                        Button("Start AI Session") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prompt, forType: .string)
                            model.host.shell.showToast("Prompt copied. Paste it into the new session.")
                            model.newSession(in: project)
                        }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(
                            !model.canStartSession(project)
                        )
                        .help(
                            model.canStartSession(project)
                                ? "Start an AI session in \(project.name) with this prompt on the clipboard"
                                : model.sessionBlock(project))
                    }
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(coreShape(Radius.row).fill(GlassInk.blue.opacity(0.14)))
            }
        } else {
            PgQuiet("Pick a document to read it here.")
        }
    }

    private var prompt: String { "Read “\(currentTitle)” and suggest what to write or fix next." }

    /// The first part of a long note, as plain text.
    private func preview(_ t: String) -> String { t.count > 3000 ? String(t.prefix(3000)) + "…" : t }
}
