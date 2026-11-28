import CoreUI
import SwiftUI

/// One session as the page lists it: the Core's id when it has one, else its place and title.
struct SessionEntry: Identifiable, Equatable {
    let id: String
    let session: ProjectLive.Session
}

/// A titled run of rows.
struct ModuleGroupData<Item: Identifiable & Equatable>: Equatable {
    let title: String
    let items: [Item]
}

enum SessionGroups {
    static func entries(_ sessions: [ProjectLive.Session]) -> [SessionEntry] {
        sessions.enumerated().map {
            SessionEntry(id: $0.element.id ?? "t\($0.offset) \($0.element.title)", session: $0.element)
        }
    }

    /// Needs you, Working, Done this week, in that order; a search keeps titles, tools and branches that hold it; empty groups go.
    static func groups(_ all: [SessionEntry], query: String) -> [ModuleGroupData<SessionEntry>] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let kept = all.filter {
            q.isEmpty
                || [$0.session.title, $0.session.harness, $0.session.branch].contains {
                    $0.localizedCaseInsensitiveContains(q)
                }
        }
        return [
            ("Needs you", ProjectLive.Session.State.needsYou), ("Working", .running), ("Done this week", .done),
        ]
        .map { g in ModuleGroupData(title: g.0, items: kept.filter { $0.session.state == g.1 }) }
        .filter { !$0.items.isEmpty }
    }
}

/// The AI Sessions focused page (details v2): sessions grouped by what they need, the picked one beside them.
struct ModuleAISessions: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var query = ""
    @State private var pick: String?

    private var entries: [SessionEntry] { SessionGroups.entries(project.live?.sessions ?? []) }
    private var groups: [ModuleGroupData<SessionEntry>] { SessionGroups.groups(entries, query: query) }
    private var ids: [String] { groups.flatMap { $0.items.map(\.id) } }
    private var current: SessionEntry? {
        let id = ModuleNav.effective(pick, in: ids)
        return entries.first { $0.id == id }
    }

    var body: some View {
        ModulePage(title: "AI Sessions") {
            if !entries.isEmpty { ModuleSearch(placeholder: "Search sessions", text: $query) }
            Button {
                model.newSession(in: project)
            } label: {
                Label("New AI Session", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: model.startingSession.contains(project.id)))
            .disabled(!model.canStartSession(project))
            .help(model.sessionBlock(project)).accessibilityIdentifier("module-new-session")
        } content: {
            if entries.isEmpty, let why = model.liveFailures[project.id]?["sessions"] {
                LoadFailed(what: "the AI sessions", why: why) { Task { await model.refreshLive(project.id) } }
                    .padding(Space.s4)
            } else if entries.isEmpty {
                ModuleQuiet(
                    symbol: "sparkles", title: "No AI sessions yet",
                    line: "A session works in its own copy of this project's repos, with the project's Brain room.")
            } else {
                ModuleSplit(pickID: current?.id) {
                    list
                } detail: {
                    if let e = current { detail(e.session) } else { none }
                }
            }
        }
        .task(id: project.id) { await model.refreshLive(project.id) }
    }

    private var list: some View {
        ModuleList(ids: ids, pick: $pick, onOpen: { if let s = current?.session { open(s) } }) {
            ForEach(groups, id: \.title) { g in
                ModuleGroup(g.title)
                ForEach(g.items) { e in
                    ModuleRow(
                        id: e.id, title: e.session.title, sub: line(e.session), selected: e.id == current?.id,
                        action: { pick = e.id }
                    ) { ModuleDot(tone: tone(e.session.state)) }
                }
            }
            if groups.isEmpty {
                Text("No session matches “\(query)”.").foregroundStyle(GlassInk.secondary).padding(Space.s3)
            }
        }
    }

    private var none: some View {
        ModuleQuiet(symbol: "sparkles", title: "No session picked", line: "Pick a session to see its details.")
    }

    private func tone(_ s: ProjectLive.Session.State) -> Tone {
        switch s {
        case .needsYou: .warn
        case .running: .done
        case .done: .queue
        }
    }

    private func line(_ s: ProjectLive.Session) -> String {
        let when = "\(s.harness) · \(s.when)"
        return s.state == .needsYou ? "\(when) · waiting for your answer" : when
    }

    /// Opens the session in AI Sessions; a window that cannot open one by id opens the AI Sessions app instead.
    private func open(_ s: ProjectLive.Session) {
        if let id = s.id, let opener = model.sessionOpener { opener(id) } else {
            model.host.shell.launcher.entry("agents")?.run()
        }
    }

    @ViewBuilder private func detail(_ s: ProjectLive.Session) -> some View {
        ModuleHead(caption: caption(s), title: s.title) {
            Button {
                open(s)
            } label: {
                Label("Open Session", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(s.id == nil)
            .help(s.id == nil ? "This session has no page in AI Sessions yet" : "Read and steer it in AI Sessions")
        }
        ModuleFacts(facts: [("Tool", s.harness), ("Runner", s.runner), ("Branch", s.branch), ("Cost", s.cost)])
        if s.state == .needsYou {
            // The question and its answer buttons live in AI Sessions; Projects only knows that the session waits.
            CoreNotice(
                symbol: "sparkles", title: "\(s.harness) is waiting for your answer",
                text: "Open the session to read the question and answer it.", tone: .warn)
        }
    }

    private func caption(_ s: ProjectLive.Session) -> String {
        switch s.state {
        case .needsYou: "Needs you · \(s.when)"
        case .running: "Working · \(s.when)"
        case .done: "Done · \(s.when)"
        }
    }
}
