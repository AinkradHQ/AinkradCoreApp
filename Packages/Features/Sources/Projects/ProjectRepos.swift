import CoreUI
import SwiftUI

/// The Repos page: the project's repos on the left, the picked one on the right (branch, the Core's copy, who uses it,
/// recent commits). GitHub holds the source; the Core keeps one copy of each repo and every AI session and run gets a clone.
struct ReposPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var pick: Int64?
    @State private var settled = false
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    /// The picked repo; before a pick, the first one that failed to fetch (it needs the person), else the first.
    private var current: RepoItem? {
        project.repos.first { $0.id == pick } ?? project.repos.first { $0.fetchError != nil } ?? project.repos.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            list.coreRise(settled, 0).frame(width: Space.s8 * 18)
            Group {
                if let r = current {
                    RepoDetail(
                        model: model, project: project, repo: r, info: insights.code?.first { $0.repo == r.name })
                } else {
                    Island("Repos") {
                        Text("Add a repo and the Core keeps a copy of it here.").foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            .id(current?.id)
            .coreRise(settled, 1)
        }
        .onAppear { settled = true }
        .task(id: project.id) {
            await insights.loadCode()
            await insights.loadTuning()
        }
        .accessibilityIdentifier("project-page-Repos")
    }

    private var list: some View {
        Island(
            title: "Repos", sub: project.repos.isEmpty ? nil : "\(project.repos.count)",
            accessory: {
                CoreIconButton(symbol: "arrow.clockwise", label: "Check the Core's copies again") { model.resync() }
                Button("Fetch All") { model.fetchAll(project) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(model.readOnly || project.repos.isEmpty)
                    .help("Copy the latest changes of every repo into the Core now")
                Button {
                    NewProjectDialogs.openAddRepos(model, project)
                } label: {
                    Label("Add Repo…", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(spacing: Space.s1) {
                    ForEach(project.repos) { r in
                        CoreRow(
                            r.name, subtitle: line(r), symbol: "arrow.triangle.branch", selected: r.id == current?.id,
                            action: { pick = r.id }
                        ) {
                            switch r.copy {
                            case .failed: StateBadge("Can’t fetch", tone: .fail, symbol: "exclamationmark.triangle")
                            case .fetching: StateBadge("Copying", tone: .warn, symbol: "gearshape")
                            case .unknown: StateBadge("Not copied", tone: .queue, symbol: "tray")
                            case .ready:
                                if model.fetching.contains(r.id) {
                                    StateBadge("Copying", tone: .warn, symbol: "gearshape")
                                } else if let i = insights.code?.first(where: { $0.repo == r.name }) {
                                    HStack(spacing: Space.s1) {
                                        if i.ahead > 0 { StateBadge("↑ \(i.ahead)", tone: .run, symbol: "arrow.up") }
                                        if i.behind > 0 {
                                            StateBadge("↓ \(i.behind)", tone: .warn, symbol: "arrow.down")
                                        }
                                    }
                                }
                            }
                        }
                        .help(r.remoteURL)
                    }
                }
                Text(
                    "GitHub holds the source. The Core keeps one copy of each repo and fetches new changes \(insights.supported ? FetchInterval.line(insights.tuning.fetchInterval) : "every 15 minutes") by itself; every AI session and run gets its own clone."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ r: RepoItem) -> String {
        switch r.copy {
        case .failed(let why, let text): return why.needsConnection ? "\(r.branch) · private" : "\(r.branch) · \(text)"
        case .fetching(let since): return "\(r.branch) · \(RepoCopy.elapsed(since: since, now: model.now()))"
        case .ready: return "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        case .unknown: return "\(r.branch) · not copied yet"
        }
    }
}

private struct RepoDetail: View {
    let model: ProjectsModel
    let project: ProjectItem
    let repo: RepoItem
    var info: CodeInfo?

    private var extra: ProjectLive.RepoExtra? { project.live?.repoExtras[repo.name] }
    private var short: String { repo.head.map { String($0.prefix(7)) } ?? "–" }

    var body: some View {
        Island(
            title: repo.name, sub: Self.path(repo.remoteURL),
            accessory: {
                if !repo.primary, project.repos.count > 1 {
                    Button("Make Primary") { Task { await model.makePrimary(project, repo) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly || model.busy)
                        .help("Sessions and runs start in the primary repo")
                }
                Button("Remove…") { model.confirmRemove(project, repo) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(model.readOnly || model.busy || (repo.primary && project.repos.count > 1))
                    .help(
                        repo.primary && project.repos.count > 1
                            ? "Make another repo primary before removing this one."
                            : "Take it out of the project. It stays on GitHub.")
                Button("Fetch Now") { model.fetchRepo(project, repo) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly || copying)
                    .help(copying ? "The Core is copying this repo now" : "Copy the latest changes into the Core now")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if case .failed(let why, let text) = repo.copy { failure(why, text) }
                facts
                if let commits = extra?.commits, !commits.isEmpty { commitList(commits) }
            }
        }
    }

    private var copying: Bool { model.isCopying(repo) }

    private func failure(_ why: RepoFailure, _ text: String) -> some View {
        let last = repo.head == nil ? "" : " Sessions and runs keep using the last copy (\(short))."
        return CoreNotice(
            symbol: "exclamationmark.triangle", title: "The Core could not copy this repo.", text: text + last,
            tone: .fail
        ) {
            if why.needsConnection {
                Button("Connect GitHub") { model.connectGithub() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            } else if why != .sshNotSupported {
                Button("Try again") { model.fetchRepo(project, repo) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
            GridRow {
                label("Branch")
                HStack(spacing: Space.s2) {
                    Text(repo.branch)
                    Button("Change…") { RepoDialogs.openBranch(model, project, repo) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .disabled(!model.core110 || model.readOnly || copying || model.busy)
                        .help(
                            !model.core110
                                ? "Changing the branch needs a newer Core. Update the Core to use it."
                                : model.readOnly
                                    ? "This device can look at projects but not change them."
                                    : copying
                                        ? "The Core is copying this repo now"
                                        : "Make \(repo.name) follow another branch")
                }
            }
            GridRow {
                label("Core copy")
                HStack(spacing: Space.s2) {
                    Text(short).font(.system(size: MacTextSize.body, design: .monospaced))
                    Text(copyAge).foregroundStyle(GlassInk.secondary)
                }
            }
            if let info {
                GridRow {
                    label("Files")
                    Text(info.files.formatted())
                }
                GridRow {
                    label("Against \(repo.branch)")
                    Text(
                        info.ahead == 0 && info.behind == 0
                            ? "Up to date" : "\(info.ahead) ahead · \(info.behind) behind")
                }
                if let c = info.last {
                    GridRow {
                        label("Last commit")
                        Text("\(c.message) · \(c.author) · \(runsAgo(c.at))").lineLimit(2)
                    }
                }
            }
            if let extra {
                GridRow {
                    label("Used by")
                    Text(extra.usedBy)
                }
                GridRow {
                    label("Size")
                    Text(extra.size)
                }
            }
        }
    }

    private var copyAge: String {
        switch repo.copy {
        case .fetching(let since): return RepoCopy.elapsed(since: since, now: model.now())
        case .failed:
            guard let at = repo.fetchedAt else { return "never copied" }
            return "· last fetched \(PickRepo.ago(at, model.now()))"
        case .ready: return "· fetched \(PickRepo.ago(repo.fetchedAt ?? model.now(), model.now()))"
        case .unknown: return "not copied yet"
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).gridColumnAlignment(.leading)
    }

    private func commitList(_ commits: [ProjectLive.Commit]) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Recent commits").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(
                GlassInk.secondary)
            ForEach(Array(commits.enumerated()), id: \.offset) { _, c in
                CoreRow(c.title, subtitle: c.by) {
                    Text(c.hash).font(.system(size: MacTextSize.body, design: .monospaced)).foregroundStyle(
                        GlassInk.secondary)
                }
            }
        }
    }

    /// "github.com/lanterna-co/lanterna-admin" from the remote link.
    private static func path(_ url: String) -> String {
        var s = url
        for p in ["https://", "ssh://", "git@"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        s = s.replacingOccurrences(of: ":", with: "/")
        return s.hasSuffix(".git") ? String(s.dropLast(4)) : s
    }
}
