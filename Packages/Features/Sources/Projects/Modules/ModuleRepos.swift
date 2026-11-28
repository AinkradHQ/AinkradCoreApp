import AppKit
import CoreUI
import SwiftUI

enum RepoWords {
    /// "github.com/lanterna-co/lanterna-api" from a remote link; the browser address of it as `web`.
    static func path(_ url: String) -> String {
        var s = url
        for p in ["https://", "http://", "ssh://", "git@"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        s = s.replacingOccurrences(of: ":", with: "/")
        return s.hasSuffix(".git") ? String(s.dropLast(4)) : s
    }

    static func web(_ url: String) -> URL? { URL(string: "https://" + path(url)) }

    /// The list's second line: the branch and the copy's state, the reason in words when the copy failed.
    static func line(_ r: RepoItem, now: Date) -> String {
        switch r.copy {
        case .failed(let why, _): "\(r.branch) · can’t fetch · \(short(why))"
        case .fetching(let since): "\(r.branch) · \(RepoCopy.elapsed(since: since, now: now))"
        case .ready: "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? now, now))"
        case .unknown: "\(r.branch) · not copied yet"
        }
    }

    static func short(_ f: RepoFailure) -> String {
        switch f {
        case .needsGithub: "GitHub is not connected"
        case .notFoundOrPrivate: "GitHub lost access"
        case .authFailed: "sign-in failed"
        case .timeout: "GitHub did not answer"
        case .sshNotSupported: "SSH links are not supported"
        case .other: "see the details"
        }
    }

    static func broken(_ r: RepoItem) -> Bool { if case .failed = r.copy { true } else { false } }
}

/// The Repos focused page (details v2): the project's repos with their copy state, the picked one beside them.
struct ModuleRepos: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var pick: String?
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    private var ids: [String] { project.repos.map { String($0.id) } }
    /// The pick; before one, the first repo that failed (it needs the person), else the first.
    private var current: RepoItem? {
        let id =
            pick.flatMap { ids.contains($0) ? $0 : nil }
            ?? project.repos.first(where: RepoWords.broken).map { String($0.id) }
        return project.repos.first { String($0.id) == (id ?? ids.first) }
    }

    var body: some View {
        ModulePage(title: "Repos") {
            Button("Fetch All") { model.fetchAll(project) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(
                    model.readOnly || project.repos.isEmpty
                )
                .help("Copy the latest changes of every repo into the Core now")
            Button {
                NewProjectDialogs.openAddRepos(model, project)
            } label: {
                Label("Add Repos…", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(model.readOnly)
            .help(
                model.readOnly
                    ? "This device can look at projects but not change them." : "Pick the repos this project is made of"
            )
        } content: {
            if project.repos.isEmpty {
                ModuleQuiet(
                    symbol: "arrow.triangle.branch", title: "No repos yet",
                    line: "Add a repo and the Core keeps a copy of it here. AI sessions and runs get a copy of it.")
            } else {
                ModuleSplit(pickID: current.map { String($0.id) }) {
                    ModuleList(
                        ids: ids, pick: $pick,
                        onOpen: { if let r = current, let u = RepoWords.web(r.remoteURL) { NSWorkspace.shared.open(u) } }
                    ) {
                        ForEach(project.repos) { r in
                            ModuleRow(
                                id: String(r.id), title: r.name, sub: RepoWords.line(r, now: model.now()),
                                symbol: "arrow.triangle.branch", selected: r.id == current?.id,
                                action: { pick = String(r.id) }
                            ) { trailing(r) }
                            .help(r.remoteURL)
                        }
                    }
                } detail: {
                    if let r = current { detail(r) }
                }
            }
        }
        .task(id: project.id) { await insights.loadCode() }
    }

    @ViewBuilder private func trailing(_ r: RepoItem) -> some View {
        HStack(spacing: Space.s2) {
            if r.primary, project.repos.count > 1 {
                StateBadge("Primary", tone: .queue, symbol: "star").help("Sessions and runs start in the primary repo")
            }
            if RepoWords.broken(r) { ModuleDot(tone: .fail) }
            if model.isCopying(r) { ModuleDot(tone: .warn) }
        }
    }

    // MARK: detail

    @ViewBuilder private func detail(_ r: RepoItem) -> some View {
        let copying = model.isCopying(r)
        let info = insights.code?.first { $0.repo == r.name }
        let extra = project.live?.repoExtras[r.name]
        ModuleHead(
            caption: RepoWords.path(r.remoteURL) + (r.primary && project.repos.count > 1 ? " · Primary" : ""),
            title: r.name
        ) {
            HStack(spacing: Space.s2) {
                Button("Change Branch…") { RepoDialogs.openBranch(model, project, r) }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(
                        !model.core110 || model.readOnly || copying || model.busy
                    )
                    .help(
                        !model.core110
                            ? "Changing the branch needs a newer Core. Update the Core to use it."
                            : copying ? "The Core is copying this repo now" : "Make \(r.name) follow another branch")
                Button("Open on GitHub") { if let u = RepoWords.web(r.remoteURL) { NSWorkspace.shared.open(u) } }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(RepoWords.web(r.remoteURL) == nil)
                Button {
                    model.fetchRepo(project, r)
                } label: {
                    Label("Fetch Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: copying)).disabled(model.readOnly || copying)
                .help(copying ? "The Core is copying this repo now" : "Copy the latest changes into the Core now")
                more(r)
            }
        }
        if case .failed(let why, let text) = r.copy { failure(r, why, text) }
        ModuleFacts(facts: facts(r, info: info, extra: extra))
        let commits = extra?.commits ?? []
        if !commits.isEmpty {
            ModuleSection(title: "Recent commits") {
                ForEach(Array(commits.enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text(c.hash).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(
                            GlassInk.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.title)
                            Text(c.by).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        }
                    }
                    .padding(.vertical, Space.s1)
                }
            }
        } else if let c = info?.last {
            ModuleSection(title: "Last commit") {
                Text("\(c.message) · \(c.author) · \(runsAgo(c.at, now: model.now()))")
            }
        }
    }

    private func facts(_ r: RepoItem, info: CodeInfo?, extra: ProjectLive.RepoExtra?) -> [(String, String)] {
        let short = r.head.map { String($0.prefix(7)) } ?? "–"
        var branch = r.branch
        if let i = info, i.ahead > 0 || i.behind > 0 { branch += " · \(i.ahead) ahead, \(i.behind) behind" }
        var out = [("Branch", branch), ("Core copy", r.head == nil ? copyAge(r) : "\(short) · \(copyAge(r))")]
        if let i = info { out.append(("Files", i.files.formatted())) }
        if let e = extra { out += [("Used by", e.usedBy), ("Size", e.size)] }
        return out
    }

    private func copyAge(_ r: RepoItem) -> String {
        switch r.copy {
        case .fetching(let since): RepoCopy.elapsed(since: since, now: model.now())
        case .failed: r.fetchedAt.map { "last fetched \(PickRepo.ago($0, model.now()))" } ?? "never copied"
        case .ready: "fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        case .unknown: "not copied yet"
        }
    }

    private func failure(_ r: RepoItem, _ why: RepoFailure, _ text: String) -> some View {
        let last =
            r.head == nil ? "" : " Sessions and runs keep using the last copy (\(String(r.head?.prefix(7) ?? "")))."
        return CoreNotice(
            symbol: "exclamationmark.triangle", title: "The Core could not copy this repo.", text: text + last,
            tone: .fail
        ) {
            if why.needsConnection {
                Button("Connect GitHub") { model.connectGithub() }.buttonStyle(
                    CoreButtonStyle(.secondary, size: .small))
            } else if why != .sshNotSupported {
                Button("Try Again") { model.fetchRepo(project, r) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
            }
        }
        .padding(.bottom, Space.s4)
    }

    private func more(_ r: RepoItem) -> some View {
        let only = project.repos.count <= 1
        let lastPrimary = r.primary && !only
        return Menu {
            Button("Make Primary") { Task { await model.makePrimary(project, r) } }
                .disabled(model.readOnly || model.busy || r.primary || only)
            Button("Remove…") { model.confirmRemove(project, r) }
                .disabled(model.readOnly || model.busy || lastPrimary)
        } label: {
            Image(systemName: "ellipsis").accessibilityLabel("More for \(r.name)")
        }
        .menuStyle(.button).buttonStyle(CoreButtonStyle(.secondary)).fixedSize()
        .help(
            lastPrimary
                ? "Make another repo primary before removing this one."
                : "Make it primary or take it out of the project")
    }
}
