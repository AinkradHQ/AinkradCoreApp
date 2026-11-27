import CoreUI
import SwiftUI

/// What each kind adds to the Overview beyond the web page. Where a section needs data the Core does not serve yet (app build
/// artefacts, infrastructure hosts and plans) the island is there with an honest empty state, never invented numbers.
extension Overview {
    // MARK: App

    /// The newest runs as builds: when, where, how it ended.
    var buildHistoryIsland: some View {
        let list = runs.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }.prefix(4)
        return Island("Build history", sub: list.isEmpty ? nil : "Latest \(list.count)") {
            if list.isEmpty {
                Text("No builds yet. Build and Run makes the first one.").foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(Array(list)) { r in
                            CoreRow(
                                "Built \(runsAgo(r.startedAt, now: model.now()))",
                                subtitle: [r.runner, r.environment].compactMap { $0 }.joined(separator: " · "),
                                action: { model.section = .run }
                            ) { Self.runBadge(r.state) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    static func runBadge(_ state: String) -> StateBadge {
        switch state {
        case "running": StateBadge("Running", tone: .run, symbol: "play.circle")
        case "starting": StateBadge("Starting", tone: .warn, symbol: "gearshape")
        case "failed": StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
        default: StateBadge("Finished", tone: .queue, symbol: "stop.circle")
        }
    }

    /// Test results are not reported by the Core yet.
    var testsIsland: some View {
        Island("Tests") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("No test results yet. The Core does not report them for an app.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Soon(prominent: false, help: "Test runs arrive when the Core reports them") {
                    Label("Run Tests", systemImage: "checkmark.seal")
                }
            }
        }
    }

    // MARK: Infrastructure

    /// Plan and apply are not served by the Core yet.
    var changesPlanIsland: some View {
        Island("Changes", sub: "Plan, then apply") {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("No plan yet. Hosts and a plan to apply appear once the Core reports them.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Soon(prominent: false, help: "Plan and apply arrive with the Core's infrastructure support") {
                    Label("Plan", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    // MARK: Not software

    /// Docs are the core object: recent docs as large tiles, with AI Sessions and Brain beside them.
    var docsFirst: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                DocsStage(model: model, project: project).coreRise(settled, 0)
                VStack(spacing: Space.s2) {
                    sessions.frame(height: Space.s8 * 9 + Space.s3).coreRise(settled, 1)
                    brain.coreRise(settled, 2)
                }
                .frame(width: Self.columnWidth)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: Space.s2) {
                aiDocsIsland.coreRise(settled, 3)
                reposIsland.coreRise(settled, 4)
            }
            .frame(height: Self.bottomHeight)
        }
    }

    private var aiDocsIsland: some View {
        let list = insights.docs ?? []
        return Island("AI documents", sub: list.isEmpty ? nil : "\(list.count)") {
            if list.isEmpty {
                Text("None yet. Documents an AI session writes in this project show up here.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(list.prefix(6)) { d in
                            CoreRow(
                                d.title.isEmpty ? d.path : d.title, subtitle: d.sessionTitle.map { "From “\($0)”" },
                                symbol: "sparkles"
                            ) { model.openNote?(d.note) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

/// The big island of a project that is not software: its recent docs as large tiles.
struct DocsStage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var docs: ProjectDocs

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _docs = State(initialValue: ProjectDocs(model: model, project: project))
    }

    private let columns = [GridItem(.adaptive(minimum: Space.s8 * 6, maximum: Space.s8 * 9), spacing: Space.s2)]

    var body: some View {
        Island(
            title: "Docs", sub: docs.phase == .ready && !docs.docs.isEmpty ? "\(docs.docs.count) in this project" : nil,
            accessory: {
                if !docs.docs.isEmpty {
                    Button("All Docs") { model.section = .docs }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        ) {
            switch docs.phase {
            case .loading: Text("Loading docs…").foregroundStyle(GlassInk.secondary)
            case .failed(let why): Text(why).foregroundStyle(GlassInk.secondary)
            case .ready where docs.docs.isEmpty:
                CoreStateCard(
                    symbol: "doc.text", title: "No docs yet",
                    line: "Write the first one with New Doc… at the top, or bring in the Markdown from a repo.",
                    secondary: docs.canImport ? CoreAction("Import from Repo…") { docs.importFromRepo() } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Space.s2) {
                        ForEach(docs.grouped().flatMap { g, rows in rows.map { (g, $0) } }.prefix(12), id: \.1.id) {
                            g, d in
                            DocTile(title: d.title, symbol: g.symbol, group: g.title) { docs.open(d.id) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .task(id: project.id) { await docs.load() }
        .accessibilityIdentifier("project-docs-stage")
    }
}

/// A doc as a large tile: a plain well that lights on hover, lifts 3 pt (not with Reduce Motion) and sinks a little on press.
struct DocTile: View {
    let title: String
    let symbol: String
    let group: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Image(systemName: symbol).coreFont(size: MacTextSize.large).foregroundStyle(GlassInk.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Text(group).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, minHeight: Space.s8 * 3, alignment: .topLeading)
            .coreCard(hovering ? GlassInk.wellHover : GlassInk.well, radius: Radius.cardMac)
            .offset(y: hovering && !reduce ? -3 : 0)
            .animation(Motion.out(Motion.hover), value: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help("Open “\(title)”")
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(Motion.out(Motion.press), value: configuration.isPressed)
    }
}
