import Brain
import CoreUI
import SwiftUI

enum BrainSection: String, CaseIterable, Identifiable {
    case about = "What it is"
    case rules = "Rules"
    case decisions = "Decisions"
    case knowledge = "Knowledge"
    case sources = "Sources"
    var id: String { rawValue }

    /// What the section's head says it holds.
    var line: String {
        switch self {
        case .about: "What the room says this project is"
        case .rules: "How work is done here · AI sessions follow these"
        case .decisions: "What was decided · AI sessions follow these"
        case .knowledge: "What the Brain remembers about this project"
        case .sources: "Where the Brain read it from"
        }
    }
}

/// One thing the Brain holds and where it came from.
struct BrainItem: Identifiable, Equatable {
    let id: String
    let text: String
    let source: String
}

/// What the Brain page lists, worked out from the room's overview and the room's records (nothing is guessed).
struct BrainContent: Equatable {
    var summary = ""
    var stack: String?
    var rules: [BrainItem] = []
    var decisions: [BrainItem] = []
    var knowledge: [BrainItem] = []
    var sources: [BrainItem] = []
    /// Items in the room, of which `sources` lists the ones a rule cites.
    var sourceCount = 0

    init() {}

    init(room: ProjectLive.Room?, rules records: [KnownRecord]?, knowledge known: [KnownRecord]?) {
        if let room {
            summary = room.summary
            stack = room.overview.overview?.facts.stack
            let titles = room.overview.sourceTitles
            let r = room.overview.overview?.rules ?? OverviewRules()
            for (group, list) in [
                ("Workflow", r.workflow), ("Code", r.code), ("Design", r.design), ("Never do", r.never),
            ] {
                for rule in list {
                    let from = rule.sources.compactMap { titles[$0] }
                    rules.append(
                        BrainItem(
                            id: "r\(group)\(rule.text)", text: rule.text,
                            source: from.isEmpty ? group : "\(group) · from \(from.joined(separator: ", "))"))
                }
            }
            sources = titles.sorted { $0.value < $1.value }.map {
                BrainItem(id: "s\($0.key)", text: $0.value, source: "Cited by a rule")
            }
            sourceCount = max(room.items, sources.count)
        }
        let have = Set(rules.map(\.text))
        rules += (records ?? []).filter { !have.contains($0.body) }.map {
            BrainItem(id: "k\($0.id)", text: $0.body, source: "A Brain record")
        }
        for k in known ?? [] {
            let item = BrainItem(
                id: "k\(k.id)", text: k.body, source: k.kind.isEmpty ? "A Brain record" : k.kind.capitalized)
            if k.kind.localizedCaseInsensitiveContains("decision") {
                decisions.append(item)
            } else {
                knowledge.append(item)
            }
        }
    }

    func items(_ s: BrainSection) -> [BrainItem] {
        switch s {
        case .about: []
        case .rules: rules
        case .decisions: decisions
        case .knowledge: knowledge
        case .sources: sources
        }
    }

    func count(_ s: BrainSection) -> Int {
        switch s {
        case .about: summary.isEmpty ? 0 : 1
        case .sources: sourceCount
        default: items(s).count
        }
    }

    /// The items of a section that hold the search words (all of them for an empty search).
    func items(_ s: BrainSection, matching query: String) -> [BrainItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items(s).filter {
            q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || $0.source.localizedCaseInsensitiveContains(q)
        }
    }
}

/// The Brain focused page (details v2): the project's room by section, with where each item came from.
struct ModuleBrain: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var insights: ProjectInsightsModel
    @State private var pick: String? = BrainSection.decisions.rawValue
    @State private var query = ""

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    private var linked: Bool { project.live?.roomID != nil || project.roomID != nil || project.live?.room != nil }
    private var content: BrainContent {
        BrainContent(room: project.live?.room, rules: insights.rules, knowledge: insights.knowledge)
    }
    private var ids: [String] { BrainSection.allCases.map(\.rawValue) }
    private var section: BrainSection { BrainSection(rawValue: ModuleNav.effective(pick, in: ids) ?? "") ?? .about }

    var body: some View {
        ModulePage(title: "Brain · \(project.name) room") {
            if linked {
                if section != .about { ModuleSearch(placeholder: "Search the Brain", text: $query) }
                Button {
                    open()
                } label: {
                    Label("Open Brain", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Opens the Brain. It does not pick this room for you.")
            }
        } content: {
            if linked, let why = insights.failures["knowledge"] ?? model.liveFailures[project.id]?["room"] {
                LoadFailed(what: "the room", why: why) {
                    Task {
                        await model.refreshLive(project.id)
                        await insights.loadKnowledge()
                    }
                }
                .padding(Space.s4)
            } else if linked {
                let c = content
                ModuleSplit(pickID: section.rawValue) {
                    ModuleList(ids: ids, pick: $pick, onOpen: {}) {
                        ForEach(BrainSection.allCases) { s in
                            ModuleRow(
                                id: s.rawValue, title: s.rawValue, selected: s == section, action: { pick = s.rawValue }
                            ) {
                                Text(c.count(s).formatted()).foregroundStyle(GlassInk.secondary).monospacedDigit()
                            }
                        }
                    }
                } detail: {
                    detail(c)
                }
            } else {
                ModuleQuiet(
                    symbol: "brain", title: "No room yet",
                    line:
                        "This project has no Brain room linked. Link one and the Brain's rules and decisions show here."
                ) { NoRoomActions(model: model, project: project) }
            }
        }
        .onChange(of: pick) { _, _ in query = "" }
        .task(id: project.id) {
            await model.refreshLive(project.id)
            await insights.loadKnowledge()
        }
    }

    private func open() { model.host.shell.launcher.entry("brain")?.run() }

    @ViewBuilder private func detail(_ c: BrainContent) -> some View {
        ModuleHead(caption: section.line, title: section.rawValue) {
            switch section {
            case .decisions:
                // The Brain's add route is not reachable from Projects; the Brain adds it, with this room picked.
                Button {
                    open()
                } label: {
                    Label("Add in Brain", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).help("Opens the Brain, where decisions are written. It does not pick this room for you.")
            case .about:
                if project.live?.room != nil {
                    Button("Edit Instructions…") { model.openInstructions(project) }
                        .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly)
                        .help("Change the instructions AI sessions read, and approve them")
                }
            default: EmptyView()
            }
        }
        if section == .about { about(c) } else { list(c) }
    }

    @ViewBuilder private func about(_ c: BrainContent) -> some View {
        if c.summary.isEmpty {
            Text(
                "The room has no written summary yet. It fills from the repos' instruction files, AI sessions and docs you add."
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Text(c.summary).fixedSize(horizontal: false, vertical: true)
            if let stack = c.stack, !stack.isEmpty { ModuleFacts(facts: [("Stack", stack)]).padding(.top, Space.s3) }
            if let room = project.live?.room {
                ModuleSection(title: "Instructions for AI sessions") {
                    StateBadge(
                        room.instructionsInUse ? "In use · approved \(room.approved)" : "Not approved yet",
                        tone: room.instructionsInUse ? .done : .warn,
                        symbol: room.instructionsInUse ? "checkmark.circle" : "clock")
                }
            }
        }
    }

    @ViewBuilder private func list(_ c: BrainContent) -> some View {
        let items = c.items(section, matching: query)
        if items.isEmpty {
            Text(query.isEmpty ? "Nothing here yet. The Brain learns as you work." : "Nothing matches “\(query)”.")
                .foregroundStyle(GlassInk.secondary)
        } else {
            VStack(spacing: Space.s2) {
                ForEach(items) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.text).coreFont(size: MacTextSize.body, weight: .medium).fixedSize(
                            horizontal: false, vertical: true)
                        Text(i.source).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coreCard(GlassInk.well, radius: Radius.control)
                    .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: items)
            if section == .sources, c.sourceCount > items.count {
                Text("\(c.sourceCount.formatted()) items in the room; these are the ones its rules cite.")
                    .foregroundStyle(GlassInk.secondary).padding(.top, Space.s3)
            }
        }
    }
}
