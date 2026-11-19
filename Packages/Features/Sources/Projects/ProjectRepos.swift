import CoreUI
import SwiftUI

/// The Repos page: the project's repos on the left, the picked one on the right (branch, the Core's copy, who uses it,
/// recent commits). GitHub holds the source; the Core keeps one copy of each repo and every AI session and run gets a clone.
struct ReposPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var pick: Int64?
    @State private var settled = false

    /// The picked repo; before a pick, the first one that failed to fetch (it needs the person), else the first.
    private var current: RepoItem? {
        project.repos.first { $0.id == pick } ?? project.repos.first { $0.fetchError != nil } ?? project.repos.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            list.coreRise(settled, 0).frame(width: Space.s8 * 18)
            Group {
                if let r = current {
                    RepoDetail(model: model, project: project, repo: r)
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
        .accessibilityIdentifier("project-page-Repos")
    }

    private var list: some View {
        Island(
            title: "Repos", sub: project.repos.isEmpty ? nil : "\(project.repos.count)",
            accessory: {
                CoreIconButton(symbol: "arrow.clockwise", label: "Check the Core's copies again") { model.resync() }
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
                            case .ready: EmptyView()
                            }
                        }
                        .help(r.remoteURL)
                    }
                }
                Text(
                    "GitHub holds the source. The Core keeps one copy of each repo; every AI session and run gets its own clone."
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
        }
    }
}

private struct RepoDetail: View {
    let model: ProjectsModel
    let project: ProjectItem
    let repo: RepoItem

    private var extra: ProjectLive.RepoExtra? { project.live?.repoExtras[repo.name] }
    private var short: String { repo.head.map { String($0.prefix(7)) } ?? "–" }

    var body: some View {
        Island(
            title: repo.name, sub: Self.path(repo.remoteURL),
            accessory: {
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

    private var copying: Bool { if case .fetching = repo.copy { true } else { false } }

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
                    // TODO(core): changing a repo's branch has no route in the synced client.
                    Button("Change…") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(true)
                        .help("Changing the branch arrives with the next Core update")
                }
            }
            GridRow {
                label("Core copy")
                HStack(spacing: Space.s2) {
                    Text(short).font(.system(size: MacTextSize.body, design: .monospaced))
                    Text(copyAge).foregroundStyle(GlassInk.secondary)
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
