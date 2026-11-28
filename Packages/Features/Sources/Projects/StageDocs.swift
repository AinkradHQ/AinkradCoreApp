import CoreUI
import SwiftUI

/// The docs stage: the project's documents as large tiles, newest groups first, and a tile that makes a new one.
struct DocsStageView: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var docs: ProjectDocs

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _docs = State(initialValue: ProjectDocs(model: model, project: project))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s3 + 2), count: 3)

    var body: some View {
        Group {
            switch docs.phase {
            case .loading: Text("Loading docs…").foregroundStyle(GlassInk.secondary)
            case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
            case .ready:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Space.s3 + 2) {
                        ForEach(docs.grouped().flatMap { g, rows in rows.map { (g, $0) } }.prefix(5), id: \.1.id) {
                            g, d in
                            DocTile(title: d.title, symbol: g.symbol, group: g.title) { docs.open(d.id) }
                                .frame(height: 150)
                        }
                        newTile
                    }
                    .padding(Space.s4 + 2)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project.id) { await docs.load() }
        .accessibilityIdentifier("project-docs-stage")
    }

    private var newTile: some View {
        Button {
            model.newDoc(in: project)
        } label: {
            VStack(spacing: Space.s2) {
                Image(systemName: "plus").coreFont(size: MacTextSize.large)
                Text("New Doc")
            }
            .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
        }
        .buttonStyle(.plain).frame(height: 150)
        .disabled(model.readOnly || model.lore == nil || model.creatingDoc.contains(project.id))
        .help(model.lore == nil ? "Docs are not available on this Core" : "Write a new doc in \(project.name)")
    }
}

extension ProjectsModel {
    /// A new, empty doc in the project, opened in Lore.
    func newDoc(in project: ProjectItem) {
        Task { if let why = await createDoc(in: project) { host.shell.showToast(why, kind: .warn) } }
    }

    /// Makes the doc and opens it; one at a time per project, so a double click makes one doc. The answer is what to tell the
    /// person when it did not end with the doc open, nil when it did.
    func createDoc(in project: ProjectItem) async -> String? {
        guard let lore, !creatingDoc.contains(project.id) else { return nil }
        creatingDoc.insert(project.id)
        defer { creatingDoc.remove(project.id) }
        do {
            let n = try await lore.create(text: "", project: String(project.id))
            guard let openNote else { return "The doc is made. Open Docs to find it; this window cannot open it." }
            openNote(n.id)
            return nil
        } catch {
            return "Could not create the doc: \(words(error))"
        }
    }
}
