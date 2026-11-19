import CoreUI
import SwiftUI

/// The Overview: the live app, then AI Sessions, Brain, Services, Repos and Logs as islands. They settle in one after another
/// (`coreRise`; Reduce Motion fades only). What the Core does not serve yet (run state, services, logs, sessions, the room)
/// comes from `ProjectLive`, which only the Debug demo fills; see its TODOs.
struct Overview: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var settled = false

    private var live: ProjectLive? { project.live }
    private var settingUp: Bool { !project.repos.isEmpty && project.draft == nil && project.run == nil }

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                LiveApp(model: model, project: project).coreRise(settled, 0)
                VStack(spacing: Space.s2) {
                    sessions.coreRise(settled, 1)
                    brain.coreRise(settled, 2)
                    if let designs = model.designsIsland {
                        designs(ProjectRef(id: String(project.id), name: project.name)).coreRise(settled, 3)
                    }
                }
                .frame(width: Space.s8 * 10)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: Space.s2) {
                servicesIsland.coreRise(settled, 3).frame(width: Space.s8 * 14)
                reposIsland.coreRise(settled, 4).frame(width: Space.s8 * 14)
                logsIsland.coreRise(settled, 5)
            }
            .frame(height: Space.s8 * 10)
        }
        .onAppear { settled = true }
    }

    // MARK: AI Sessions

    private var sessions: some View {
        let list = live?.sessions ?? []
        return Island(
            title: "AI Sessions", sub: list.isEmpty ? nil : "\(list.count)",
            accessory: {
                if !list.isEmpty {
                    CoreIconButton(symbol: "ellipsis", label: "All AI sessions") { model.section = .sessions }
                }
            }
        ) {
            if list.isEmpty {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("No AI sessions yet. New ones start in their own clone of this project's repos.")
                        .fixedSize(horizontal: false, vertical: true)
                    Soon(prominent: false, help: "AI sessions in a project arrive with the next update") {
                        Label("New AI Session", systemImage: "plus")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, s in
                        CoreRow(s.title, subtitle: "\(s.harness) · \(s.when)") { badge(s.state) }
                    }
                }
            }
        }
    }

    private func badge(_ s: ProjectLive.Session.State) -> StateBadge {
        switch s {
        case .needsYou: StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
        case .running: StateBadge("Running", tone: .run, symbol: "play.circle")
        case .done: StateBadge("Done", tone: .queue, symbol: "checkmark.circle")
        }
    }

    // MARK: Brain

    private var brain: some View {
        Island(
            title: "Brain", sub: "\(project.name) room",
            accessory: {
                if live?.room != nil {
                    Button("Details") { model.section = .brain }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        ) {
            // TODO(P1-03): `room` on the project; nil until it lands, and for a project that has no room yet.
            if let room = live?.room {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(room.summary).fixedSize(horizontal: false, vertical: true)
                    if room.instructionsInUse {
                        StateBadge("Instructions in use for AI sessions", tone: .done, symbol: "checkmark.circle")
                    }
                    Text("\(room.rules) rules · from \(room.items.formatted()) items").foregroundStyle(
                        GlassInk.secondary)
                }
            } else {
                Text(
                    settingUp
                        ? "Creating… It fills from the repos’ instruction files, AI sessions and docs you add."
                        : "New room, nothing in it yet. It fills from the repos’ instruction files, AI sessions and docs you add."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Services

    private var servicesIsland: some View {
        Island(
            title: "Services", sub: model.coreName,
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
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(l.services.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.name, symbol: Self.symbol(s.state)) {
                        if s.state == .exited {
                            StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
                        } else {
                            Text(s.state == .up ? s.memory : "–").foregroundStyle(GlassInk.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } else if let draft = project.draft {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(draft.services, id: \.self) { s in
                    HStack(spacing: Space.s2) {
                        StateBadge(s, tone: .queue, symbol: "circle")
                        Spacer(minLength: 0)
                        Text("–").foregroundStyle(GlassInk.secondary)
                    }
                }
            }
        } else {
            Text(project.repos.isEmpty ? "Drafted once you add repos." : "Drafting…").foregroundStyle(
                GlassInk.secondary)
        }
    }

    private static func symbol(_ s: ProjectLive.Service.State) -> String {
        switch s {
        case .up: "checkmark.circle"
        case .down: "circle"
        case .exited: "exclamationmark.triangle"
        }
    }

    // MARK: Repos

    private var reposIsland: some View {
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

    @ViewBuilder private var repos: some View {
        if project.repos.isEmpty {
            Text("No repos yet.").foregroundStyle(GlassInk.secondary)
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(project.repos) { r in
                    CoreRow(r.name, subtitle: repoLine(r), symbol: "arrow.triangle.branch") {
                        if r.fetchError != nil {
                            StateBadge("Copy failed", tone: .fail, symbol: "exclamationmark.triangle")
                        }
                    }
                    .help(r.remoteURL)
                }
            }
        }
    }

    private func repoLine(_ r: RepoItem) -> String {
        switch r.copy {
        case .failed(_, let e): return "\(r.branch) · \(e)"
        case .fetching(let since): return "\(r.branch) · \(RepoCopy.elapsed(since: since, now: model.now()))"
        case .ready: return "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        }
    }

    // MARK: Logs

    private var logsIsland: some View {
        Island(
            title: "Logs", sub: live?.logs.isEmpty == false ? "all services" : nil,
            accessory: {
                if live?.logs.isEmpty == false {
                    CoreIconButton(symbol: "ellipsis", label: "Open the logs in Run") { model.section = .run }
                }
            }
        ) {
            if let lines = live?.logs, !lines.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(l.service).foregroundStyle(GlassInk.secondary).frame(
                                width: Space.s8 * 2, alignment: .leading)
                            Text(l.text).lineLimit(1)
                        }
                        .font(.system(size: MacTextSize.body, design: .monospaced))
                    }
                }
            } else {
                Text("No runs yet.").foregroundStyle(GlassInk.secondary)
            }
        }
    }
}
