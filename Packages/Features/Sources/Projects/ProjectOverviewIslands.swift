import CoreUI
import SwiftUI

/// A module of the Overview: a plain well whose header (icon, name, a count, an arrow) opens the module's focused page.
struct ModuleCard<Content: View>: View {
    let model: ProjectsModel
    let module: ProjectModule
    var title: String? = nil
    var sub: String? = nil
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.spaceProject) private var space

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                model.go(module, in: space)
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: module.symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    Text(title ?? module.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    if let sub { Text(sub).foregroundStyle(GlassInk.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s2).frame(height: Space.s8 + Space.s2)
                .background(hovering ? GlassInk.lift(0.07) : .clear, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
            }
            .buttonStyle(.plain).onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
            .help(module.help).accessibilityLabel("Open \(module.title)")
            content.padding(.horizontal, Space.s2)
            Spacer(minLength: 0)
        }
        .padding(Space.s2).padding(.bottom, Space.s1)
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 7, maxHeight: .infinity, alignment: .topLeading)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-module-\(module.title)")
    }
}

/// A row of a module: its words, an optional second line, and what sits at the end.
private struct OverviewRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder let trailing: Trailing
    @State private var hovering = false

    var body: some View {
        let row = HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).lineLimit(1)
                if let subtitle { Text(subtitle).foregroundStyle(GlassInk.secondary).lineLimit(1) }
            }
            Spacer(minLength: Space.s2)
            trailing
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 + 1).frame(minHeight: Space.s8 + Space.s2)
        .background(hovering && action != nil ? GlassInk.lift(0.07) : .clear, in: coreShape(Radius.control))
        .contentShape(coreShape(Radius.control))
        if let action {
            Button(action: action) { row }.buttonStyle(.plain).onHover { hovering = $0 }
                .animation(Motion.out(Motion.hover), value: hovering)
        } else {
            row
        }
    }
}

/// A button under a module's rows: quiet, small.
private func moreButton(_ title: String, symbol: String? = nil, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
    }
    .buttonStyle(CoreButtonStyle(.plain, size: .small))
}

extension Overview {
    // MARK: AI Sessions

    var sessions: some View {
        let list = live?.sessions ?? []
        let counted = project.run?.sessions ?? 0
        let ordered = list.filter { $0.state == .needsYou } + list.filter { $0.state != .needsYou }
        return ModuleCard(
            model: model, module: .ai, sub: list.isEmpty && counted == 0 ? nil : "\(max(list.count, counted)) this week"
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if list.isEmpty {
                    Text(
                        counted > 0
                            ? "\(ProjectItem.count(counted, "AI session")) in this project."
                            : "No AI sessions yet. New ones start in their own copy of this project's repos."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(ordered.prefix(3).enumerated()), id: \.offset) { _, s in
                    OverviewRow(
                        title: s.title, subtitle: "\(s.harness) · \(s.when)",
                        action: s.id.map { id in { model.sessionOpener?(id) } }
                    ) { SessionBadge.badge(s.state) }
                }
                moreButton("New AI Session", symbol: "plus") { model.newSession(in: project) }
                    .disabled(!model.canStartSession(project)).padding(.top, Space.s1)
            }
        }
    }

    // MARK: Brain

    var hasRoom: Bool { live?.room != nil || live?.roomID != nil || project.roomID != nil }

    var brain: some View {
        ModuleCard(model: model, module: .brain, sub: hasRoom ? "\(project.name) room" : "No room yet") {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let room = live?.room {
                    fact(room.summary)
                    if room.approved.isEmpty == false || room.instructionsInUse {
                        fact("Instructions in use\(room.approved.isEmpty ? "" : " since \(room.approved)").")
                    }
                    Text("\(ProjectItem.count(room.rules, "rule")) · \(room.items.formatted()) items · Open Brain")
                        .foregroundStyle(GlassInk.secondary)
                } else if let n = insights.knowledge?.count, n > 0 {
                    ForEach(insights.knowledge?.prefix(2).map { $0 } ?? []) { KnownRow(r: $0) }
                    Text("Core remembers \(ProjectItem.count(n, "thing")) about this project.")
                        .foregroundStyle(GlassInk.secondary)
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

    private func fact(_ s: String) -> some View {
        Text(s).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2).frame(maxWidth: .infinity, alignment: .leading)
            .coreCard(GlassInk.well, radius: Radius.cardMac - 2)
    }

    // MARK: Services

    var servicesCard: some View {
        let list = live?.services ?? []
        let up = list.filter { $0.state == .up }.count
        let ordered = list.filter { $0.state == .exited } + list.filter { $0.state != .exited }
        let shown = Array(ordered.prefix(4))
        return ModuleCard(
            model: model, module: .services,
            sub: list.isEmpty ? nil : project.tag == .running || up > 0 ? "\(up) up" : "not running"
        ) {
            if list.isEmpty {
                Text(servicesWords).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2
                    ) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, s in serviceTile(s) }
                    }
                    if ordered.count > shown.count {
                        moreButton("+\(ordered.count - shown.count) more · Open Services") { model.go(.services, in: project.id) }
                    }
                }
            }
        }
    }

    private var servicesWords: String {
        if project.repos.isEmpty { return "No setup yet. Add repos first." }
        if let d = project.draft {
            let n = ProjectItem.count(d.services.count, "service")
            return project.tag == .running || project.tag == .starting
                ? "\(n), waiting for the Core to list them" : "\(n), not started"
        }
        return project.repos.isEmpty
            ? "Drafted once you add repos."
            : project.setup == .needsSetup ? "No setup yet. Use Set Up… at the top." : "Reading the setup…"
    }

    private func serviceTile(_ s: ProjectLive.Service) -> some View {
        VStack(alignment: .leading, spacing: Space.s1 + 2) {
            HStack(spacing: Space.s2) {
                StatusDot(colour: tileColour(s))
                Text(s.name).coreFont(size: MacTextSize.meta + 1, weight: .semibold).lineLimit(1)
                Spacer(minLength: 0)
                if s.state == .up, !project.stale { Text(s.memory).foregroundStyle(GlassInk.secondary).monospacedDigit() }
            }
            if project.stale {
                Text("–").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else
            if s.state == .up, let m = live?.metrics[s.name], m.memory.count > 1 {
                HStack(spacing: Space.s2) {
                    Text(s.health == "unhealthy" ? "Up · not healthy" : "Up").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                    Sparkline(values: m.memory, label: "\(s.name) memory, recent minutes", tint: GlassInk.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(s.state == .up ? Self.serviceLine(s) : s.state == .exited ? Self.serviceLine(s) : "Not started")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(
                        s.state == .exited ? GlassInk.redInk : GlassInk.secondary
                    )
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.cardMac - 2)
        .accessibilityElement(children: .combine)
    }

    /// A service tile's square: green up, orange up but not healthy, red down or crashed, grey when nothing is known.
    private func tileColour(_ s: ProjectLive.Service) -> Color {
        if project.stale { return GlassInk.secondary }
        if project.crash?.service == s.name { return GlassInk.red }
        switch s.state {
        case .up: return s.health == "unhealthy" ? GlassInk.amber : GlassInk.green
        case .exited: return GlassInk.red
        case .down: return GlassInk.secondary
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

    // MARK: Builds

    /// Each run is a build: a bar per run (its length in time), red where it failed.
    var buildsCard: some View {
        let list = runs.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }.suffix(12)
        let longest =
            list.compactMap { r in r.startedAt.flatMap { s in r.stoppedAt.map { $0.timeIntervalSince(s) } } }
            .max() ?? 0
        return ModuleCard(model: model, module: .builds, sub: list.isEmpty ? nil : "last \(list.count)") {
            if let last = list.last {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(alignment: .bottom, spacing: Space.s1) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, r in
                            let failed = r.state == "failed"
                            let d = r.startedAt.flatMap { s in r.stoppedAt.map { $0.timeIntervalSince(s) } } ?? 0
                            coreShape(3).fill(failed ? GlassInk.red : GlassInk.green)
                                .frame(height: failed ? 18 : longest > 0 && d > 0 ? 14 + 30 * CGFloat(d / longest) : 36)
                                .frame(width: 16)
                        }
                    }
                    .frame(height: 44, alignment: .bottom)
                    OverviewRow(
                        title: "Built \(runsAgo(last.startedAt, now: model.now()))",
                        subtitle: [last.runner, last.environment].compactMap { $0 }.joined(separator: " · "),
                        action: { model.go(.builds, in: project.id) }
                    ) { Self.runBadge(last.state) }
                }
            } else {
                Text("No builds yet. Build and Run makes the first one.").foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func runBadge(_ state: String) -> StateBadge {
        switch state {
        case "running", "starting": StateBadge("Building", tone: .warn, symbol: "gearshape")
        case "failed": StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
        default: StateBadge("Passed", tone: .run, symbol: "checkmark.circle")
        }
    }

    // MARK: Repos

    /// Three rows at most, the ones that need a look first; the rest are one click away.
    static let repoRows = 3

    var reposCard: some View {
        let ordered = project.repos.filter { $0.copy.isFailed } + project.repos.filter { !$0.copy.isFailed }
        return ModuleCard(model: model, module: .repos, sub: project.repos.isEmpty ? nil : "\(project.repos.count)") {
            if project.repos.isEmpty {
                Text(project.kind == .other ? "No code attached. Add a repo if the docs live in one." : "No repos yet.")
                    .foregroundStyle(GlassInk.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ordered.prefix(ordered.count > Self.repoRows ? Self.repoRows - 1 : Self.repoRows)) { r in
                        OverviewRow(title: r.name, subtitle: repoLine(r), action: { model.go(.repos, in: project.id) }) {
                            if r.fetchError != nil {
                                StateBadge("Copy failed", tone: .fail, symbol: "exclamationmark.triangle")
                            } else if r.primary, project.repos.count > 1 {
                                KindChipText("Primary")
                            }
                        }
                        .help(r.remoteURL)
                    }
                    if ordered.count > Self.repoRows {
                        moreButton("Show all \(ordered.count)") { model.go(.repos, in: project.id) }
                    }
                }
            }
        }
    }

    func repoLine(_ r: RepoItem) -> String {
        switch r.copy {
        case .failed(_, let e): return "\(r.branch) · \(e)"
        case .fetching(let since): return "\(r.branch) · \(RepoCopy.elapsed(since: since, now: model.now()))"
        case .ready: return "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        case .unknown: return "\(r.branch) · not copied yet"
        }
    }

    // MARK: Activity

    var activityCard: some View {
        let lines = ActivityLine.timeline(repos: project.repos, runs: runs, names: names, limit: 4)
        return ModuleCard(model: model, module: .activity) {
            if lines.isEmpty {
                Text("Nothing yet.").foregroundStyle(GlassInk.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { l in
                        HStack(alignment: .top, spacing: Space.s3) {
                            coreShape(3).fill(tint(l)).frame(width: 10, height: 10).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(l.title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                                Text(runsAgo(l.at, now: model.now())).foregroundStyle(GlassInk.secondary)
                                    .coreFont(size: MacTextSize.meta)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: Space.s8 + Space.s2, alignment: .top)
                    }
                }
                .background(alignment: .topLeading) {
                    coreShape(1).fill(GlassInk.lift(0.13)).frame(width: 2).padding(.leading, 4).padding(.vertical, 8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tint(_ l: ActivityLine) -> Color {
        l.symbol == "exclamationmark.triangle" ? GlassInk.red : l.symbol == "bolt" ? GlassInk.blue : GlassInk.green
    }

    // MARK: Logs

    var logsCard: some View {
        let real = logs.map { $0.lineCount > 0 } ?? false
        let demo = live?.logs ?? []
        return ModuleCard(
            model: model, module: .logs, sub: real || !demo.isEmpty ? LogWords.caption(project) : nil
        ) {
            if let logs, real {
                RunLogView(logs: logs, compact: true).frame(height: Space.s8 * 4)
            } else if !demo.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(demo.suffix(6).enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(l.service).foregroundStyle(GlassInk.secondary).frame(
                                width: Space.s8 + Space.s6, alignment: .leading)
                            Text(LogText.plain(l.text)).lineLimit(1)
                                .foregroundStyle(LogWords.isError(l.text) ? GlassInk.redInk : GlassInk.secondary)
                        }
                        .font(.system(size: MacTextSize.body - 1, design: .monospaced))
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

/// A word on a small quiet chip ("Primary").
struct KindChipText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta + 1, weight: .medium)
            .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm)
            .coreCard(GlassInk.well, radius: Radius.chip).fixedSize()
    }
}

/// The badge of one AI session state, shared by the Overview and the Sessions page.
enum SessionBadge {
    static func badge(_ s: ProjectLive.Session.State) -> StateBadge {
        switch s {
        case .needsYou: StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
        case .running: StateBadge("Working", tone: .run, symbol: "play.circle")
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
