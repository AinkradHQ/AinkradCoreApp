import CoreUI
import SwiftUI

/// The Overview's islands: AI Sessions, Brain, Notes, Services (or Build history), Repos and Logs, and what a kind adds.
extension Overview {
    // MARK: AI Sessions

    var sessions: some View {
        let list = live?.sessions ?? []
        // One source: the list the Overview reads is the number on the card; when only the count is known, say so.
        let counted = project.run?.sessions ?? 0
        return Island(
            title: "AI Sessions", sub: list.isEmpty && counted == 0 ? nil : "\(max(list.count, counted))",
            accessory: {
                if !list.isEmpty || counted > 0 {
                    CoreIconButton(symbol: "ellipsis", label: "All AI sessions") { model.section = .sessions }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if list.isEmpty, counted > 0 {
                    Text("\(ProjectItem.count(counted, "AI session")) in this project.")
                    Button("Show All") { model.section = .sessions }.buttonStyle(
                        CoreButtonStyle(.secondary, size: .small))
                } else if list.isEmpty {
                    Text(
                        project.repos.isEmpty
                            ? (model.core111
                                ? "No AI sessions yet. New ones start in their own folder, with this project's Brain place."
                                : "No AI sessions yet. This Core runs them in a repo, so add a repo to start one.")
                            : "No AI sessions yet. New ones start in their own clone of this project's repos."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    // Sessions that need you come first.
                    let ordered = list.filter { $0.state == .needsYou } + list.filter { $0.state != .needsYou }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(ordered.prefix(4).enumerated()), id: \.offset) { _, s in
                            CoreRow(
                                s.title, subtitle: "\(s.harness) · \(s.when)",
                                action: s.id.map { id in { model.sessionOpener?(id) } }
                            ) { SessionBadge.badge(s.state) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Brain

    var hasRoom: Bool { live?.room != nil || live?.roomID != nil || project.roomID != nil }

    var brain: some View {
        Island(
            title: "Brain", sub: hasRoom ? "\(project.name) room" : "No room yet",
            accessory: {
                if hasRoom {
                    Button("Open Brain") { model.section = .brain }.buttonStyle(
                        CoreButtonStyle(.secondary, size: .small))
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let room = live?.room {
                    Text(room.summary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text("\(room.rules) rules · from \(room.items.formatted()) items").foregroundStyle(
                        GlassInk.secondary)
                } else if let n = insights.knowledge?.count, n > 0 {
                    Text("Core remembers \(ProjectItem.count(n, "thing")) about this project.")
                    ForEach(insights.knowledge?.prefix(2).map { $0 } ?? []) { KnownRow(r: $0) }
                } else if !hasRoom {
                    Text("This project has no Brain room yet. Link one and it fills from AI sessions and docs.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                    NoRoomActions(model: model, project: project)
                } else {
                    Text(
                        settingUp
                            ? "Creating… It fills from the repos’ instruction files, AI sessions and docs you add."
                            : "Nothing remembered yet. It fills from the repos’ instruction files, AI sessions and docs you add."
                    )
                    .fixedSize(horizontal: false, vertical: true).foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }

    // MARK: Notes

    var notesCard: some View {
        let notes = insights.notes ?? []
        let docs = insights.docs ?? []
        return Island(
            title: "Notes", sub: notes.isEmpty && docs.isEmpty ? nil : "\(notes.count + docs.count)",
            accessory: {
                Button("Open Notes") { model.section = .docs }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        ) {
            VStack(spacing: Space.s1) {
                if notes.isEmpty && docs.isEmpty { Text("No notes yet.").foregroundStyle(GlassInk.secondary) }
                ForEach(notes.prefix(2)) { n in CoreRow(n.title, symbol: "doc.text") { model.openNote?(n.id) } }
                ForEach(docs.prefix(2)) { d in
                    CoreRow(
                        d.title.isEmpty ? d.path : d.title, subtitle: d.sessionTitle.map { "From “\($0)”" },
                        symbol: "sparkles"
                    ) {
                        model.openNote?(d.note)
                    }
                }
            }
        }
    }

    // MARK: Services

    var servicesIsland: some View {
        Island(
            title: "Services", sub: live?.runner ?? model.coreName,
            accessory: {
                if let l = live, !l.services.isEmpty {
                    Button {
                        model.section = .run
                    } label: {
                        Label("Secrets", systemImage: "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        ) { services }
    }

    @ViewBuilder private var services: some View {
        if let l = live, !l.services.isEmpty {
            // State, health and memory of each; a row opens the Runs page.
            // Two rows fit with a way to the rest; a service that needs a look (exited) comes first. Nothing is clipped.
            let ordered = l.services.filter { $0.state == .exited } + l.services.filter { $0.state != .exited }
            let shown = ordered.count > 2 ? Array(ordered.prefix(2)) : ordered
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.name, subtitle: Self.serviceLine(s), action: { model.section = .run }) {
                        if s.state == .up, let m = live?.metrics[s.name], m.memory.count > 1 {
                            Sparkline(values: m.memory, label: "\(s.name) memory, recent minutes")
                        }
                        if s.state == .exited {
                            StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
                        } else if s.state == .up {
                            Text(s.memory).foregroundStyle(GlassInk.secondary).monospacedDigit()
                        }
                    }
                    .help("Open the runs of \(project.name)")
                }
                if ordered.count > shown.count {
                    Button("+\(ordered.count - shown.count) more") { model.section = .run }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
        } else if !project.repos.isEmpty, let draft = project.draft {
            let live = project.tag == .running || project.tag == .starting
            Text(
                live
                    ? "\(ProjectItem.count(draft.services.count, "service")), waiting for the Core to list them"
                    : "\(ProjectItem.count(draft.services.count, "service")), not started"
            )
            .foregroundStyle(GlassInk.secondary)
        } else {
            Text(
                project.repos.isEmpty
                    ? "Drafted once you add repos."
                    : project.setup == .needsSetup ? "No setup yet. Use Set Up… at the top." : "Reading the setup…"
            ).foregroundStyle(GlassInk.secondary)
        }
    }

    /// "Up · healthy", "Exited · restarted 3 times", "Down".
    static func serviceLine(_ s: ProjectLive.Service) -> String {
        switch s.state {
        case .up:
            switch s.health {
            case "healthy": return "Up · healthy"
            case "unhealthy": return "Up · not healthy"
            case "starting": return "Up · checking health"
            default: return "Up"
            }
        case .down: return "Down"
        case .exited: return s.restarts > 0 ? "Exited · restarted \(s.restarts) times" : "Exited"
        }
    }

    // MARK: Repos

    var reposIsland: some View {
        Island(
            title: "Repos", sub: project.repos.isEmpty ? nil : "\(project.repos.count)",
            accessory: {
                CoreIconButton(symbol: "plus", label: "Add repos to \(project.name)") {
                    NewProjectDialogs.openAddRepos(model, project)
                }
                .disabled(model.readOnly)
            }
        ) { repos }
    }

    /// Three rows at most, the ones that need a look first; the rest are one click away.
    static let repoRows = 3

    @ViewBuilder private var repos: some View {
        if project.repos.isEmpty {
            Text(project.kind == .other ? "No code attached. Add a repo if the docs live in one." : "No repos yet.")
                .foregroundStyle(GlassInk.secondary)
        } else {
            let ordered = project.repos.filter { $0.copy.isFailed } + project.repos.filter { !$0.copy.isFailed }
            VStack(alignment: .leading, spacing: Space.s1) {
                // Up to three rows fit; more than three show two and a way to the rest, so the island never grows.
                ForEach(ordered.prefix(ordered.count > Self.repoRows ? Self.repoRows - 1 : Self.repoRows)) { r in
                    CoreRow(
                        r.name, subtitle: repoLine(r), symbol: "arrow.triangle.branch",
                        action: { model.section = .repos }
                    ) {
                        if r.fetchError != nil {
                            StateBadge("Copy failed", tone: .fail, symbol: "exclamationmark.triangle")
                        } else if r.primary, project.repos.count > 1 {
                            StateBadge("Primary", tone: .queue, symbol: "star")
                        }
                    }
                    .help(r.remoteURL)
                }
                if ordered.count > Self.repoRows {
                    Button("Show all \(ordered.count)") { model.section = .repos }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func repoLine(_ r: RepoItem) -> String {
        switch r.copy {
        case .failed(_, let e): return "\(r.branch) · \(e)"
        case .fetching(let since): return "\(r.branch) · \(RepoCopy.elapsed(since: since, now: model.now()))"
        case .ready: return "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        case .unknown: return "\(r.branch) · not copied yet"
        }
    }

    // MARK: Logs

    var logsIsland: some View {
        let real = logs.map { $0.lineCount > 0 } ?? false
        let demo = live?.logs ?? []
        return Island(
            title: "Logs", sub: real || !demo.isEmpty ? LogWords.caption(project) : nil,
            accessory: {
                if real || !demo.isEmpty {
                    CoreIconButton(symbol: "arrow.up.right.square", label: "Show Log in Runs") { model.section = .run }
                }
            }
        ) {
            if let logs, real {
                RunLogView(logs: logs, compact: true)
            } else if !demo.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(Array(demo.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(l.service).foregroundStyle(GlassInk.secondary).frame(
                                width: Space.s8 * 2, alignment: .leading)
                            Text(LogText.plain(l.text)).lineLimit(1)
                                .foregroundStyle(LogWords.isError(l.text) ? GlassInk.redInk : GlassInk.primary)
                        }
                        .font(.system(size: MacTextSize.body, design: .monospaced))
                    }
                }
            } else {
                Text(
                    project.tag == .running || project.tag == .starting
                        ? "Waiting for the first line…"
                        : project.run == nil ? "Logs appear while the project runs." : "The last run wrote no log."
                )
                .foregroundStyle(GlassInk.secondary)
            }
        }
    }
}

/// The badge of one AI session state, shared by the Overview and the Sessions page.
enum SessionBadge {
    static func badge(_ s: ProjectLive.Session.State) -> StateBadge {
        switch s {
        case .needsYou: StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
        case .running: StateBadge("Running", tone: .run, symbol: "play.circle")
        case .done: StateBadge("Done", tone: .queue, symbol: "checkmark.circle")
        }
    }
}

/// The words around the Overview's log.
enum LogWords {
    /// "all services" while it runs; "Last run · failed 20 min ago" once it ended, so the lines say why.
    static func caption(_ project: ProjectItem) -> String? {
        guard let run = project.run else { return nil }
        let when = run.lastRun.map { " \($0)" } ?? ""
        switch run.state {
        case .running, .starting: return "all services"
        case .failed: return "Last run · failed\(when)"
        case .stopped: return "Last run · stopped\(when)"
        }
    }

    static func isError(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("error") || l.contains("failed") || l.contains("exited with")
    }
}
