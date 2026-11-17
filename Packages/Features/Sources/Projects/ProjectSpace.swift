import CoreUI
import SwiftUI

/// The space of one project: a top bar, a thin rail and the Overview. P7-01 builds the shell and the states a new project
/// passes through (no repos, setting up, ready to start); the Overview's islands fill in with P7-02.
struct ProjectSpaceView: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        VStack(spacing: Space.s2) {
            TopBar(model: model, project: project)
            HStack(alignment: .top, spacing: Space.s2) {
                Rail()
                Overview(model: model, project: project)
            }
        }
        .padding(Space.s2)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-space")
    }
}

/// An island: a titled card over the pane's surface.
private struct Island<Content: View, Accessory: View>: View {
    let title: String
    let sub: String?
    let accessory: Accessory
    let content: Content
    init(
        title: String, sub: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.accessory = accessory()
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                if let sub { Text(sub).foregroundStyle(GlassInk.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                accessory
            }
            content
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
}

extension Island where Accessory == EmptyView {
    fileprivate init(_ title: String, sub: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, sub: sub, accessory: { EmptyView() }, content: content)
    }
}

/// A control whose feature is not built yet: the real control, off, with its reason as the tooltip.
private struct Soon<Label: View>: View {
    let prominent: Bool
    let help: String
    @ViewBuilder let label: Label
    var body: some View {
        Button {
        } label: {
            label
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary)).disabled(true).help(help)
    }
}

private struct TopBar: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        AppHeader {
            BackButton("Projects") { model.closeProject() }
            ProjectMark(name: project.name, colour: model.colour(project), size: MacSize.controlMd)
            Text(project.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
            ProjectStateBadge(project: project)
        } actions: {
            Text("Public link").foregroundStyle(GlassInk.secondary)
            CoreSwitch(
                "",
                isOn: Binding(
                    get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
            )
            .disabled(model.readOnly).accessibilityLabel("Public link")
            .help("While this project runs, anyone with \(project.link) can open it")
            Soon(prominent: false, help: "Starting a project arrives with the run engine") {
                Label("Start", systemImage: "play")
            }
            CoreIconButton(symbol: "terminal", label: "A project terminal arrives with the run engine") {}
                .disabled(true)
            Soon(prominent: true, help: "AI sessions in a project arrive with the next update") {
                Label("New AI Session", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
}

/// The thin rail of the space. Only Overview exists in P7-01; the others show where they will be.
private struct Rail: View {
    private let items: [(String, String)] = [
        ("Overview", "square.grid.2x2"), ("Run", "display"), ("Repos", "arrow.triangle.branch"),
        ("AI Sessions", "sparkles"), ("Brain", "brain.head.profile"),
    ]
    var body: some View {
        VStack(spacing: Space.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                tile(item.0, item.1, on: i == 0)
            }
            Spacer(minLength: 0)
            tile("Project Settings", "slider.horizontal.3", on: false)
        }
        .padding(Space.s1)
        .frame(maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
    private func tile(_ name: String, _ symbol: String, on: Bool) -> some View {
        CoreIconButton(symbol: symbol, label: on ? name : "\(name) arrives with the next update", selected: on) {}
            .disabled(!on)
    }
}

private struct Overview: View {
    let model: ProjectsModel
    let project: ProjectItem

    private var settingUp: Bool { !project.repos.isEmpty && project.draft == nil }

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                LiveApp(model: model, project: project)
                VStack(spacing: Space.s2) {
                    Island("AI Sessions") {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            Text("No AI sessions yet. New ones start in their own clone of this project's repos.")
                                .fixedSize(horizontal: false, vertical: true)
                            Soon(prominent: false, help: "AI sessions in a project arrive with the next update") {
                                Label("New AI Session", systemImage: "plus")
                            }
                        }
                    }
                    Island("Brain", sub: "\(project.name) room") {
                        Text(
                            settingUp
                                ? "Creating… It fills from the repos’ instruction files, AI sessions and docs you add."
                                : "New room, nothing in it yet. It fills from the repos’ instruction files, AI sessions and docs you add."
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: Space.s8 * 10)
            }
            Grid(horizontalSpacing: Space.s2, verticalSpacing: 0) {
                GridRow {
                    Island("Services", sub: model.coreName) { services }
                    Island(
                        title: "Repos", sub: project.repos.isEmpty ? nil : "\(project.repos.count)",
                        accessory: {
                            CoreIconButton(symbol: "plus", label: "Add repos to \(project.name)") {
                                NewProjectDialogs.openAddRepos(model, project)
                            }
                            .disabled(model.readOnly)
                        }
                    ) { repos }
                    Island("Logs") { Text("No runs yet.").foregroundStyle(GlassInk.secondary) }
                        .gridCellColumns(2)
                }
            }
            .frame(height: Space.s8 * 5 + Space.s4)
        }
    }

    @ViewBuilder private var services: some View {
        if let draft = project.draft {
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
        if let e = r.fetchError { return "\(r.branch) · \(e)" }
        guard let at = r.fetchedAt else { return "\(r.branch) · copying…" }
        return "\(r.branch) · fetched \(PickRepo.ago(at, model.now()))"
    }
}

/// The big island: the live app's address, and what stands in for the app while it cannot run yet.
private struct LiveApp: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(project.link)
                Text(project.expose ? "· public while running" : "· private").foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2)
            ZStack {
                Color.clear.coreCard(GlassInk.well, radius: Radius.cardMac)
                stage.padding(Space.s5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var stage: some View {
        if project.repos.isEmpty {
            noRepos
        } else if let draft = project.draft {
            ReadyToStart(project: project, draft: draft)
        } else {
            SettingUp(project: project)
        }
    }

    private var noRepos: some View {
        VStack(spacing: Space.s2) {
            Text("Add a repo to \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .multilineTextAlignment(.center)
            Text("Pick repos from GitHub. The Core keeps a copy and drafts how to run them.")
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 11)
            Button {
                NewProjectDialogs.openAddRepos(model, project)
            } label: {
                Label("Add Repos…", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.readOnly)
            .padding(.top, Space.s1).accessibilityIdentifier("project-add-repos-button")
        }
    }
}

/// Copy, read, draft, room: where a new project stands. The Core copies the repos; drafting arrives with the run engine,
/// so while it is the step in progress the project stays here.
private struct SettingUp: View {
    let project: ProjectItem
    private enum Step { case done, active, failed, waiting }

    private var steps: [(String, Step)] {
        let failed = project.repos.contains { $0.fetchError != nil }
        let copied = project.repos.allSatisfy { $0.fetchedAt != nil }
        let copy: Step = failed ? .failed : copied ? .done : .active
        return [
            ("Copy \(ProjectItem.count(project.repos.count, "repo")) to the Core", copy),
            ("Read the repos", copy == .done ? .done : .waiting),
            ("Draft the run from the repos", copy == .done ? .active : .waiting),
            ("Create the Brain room “\(project.name)”", .waiting),
        ]
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            Text("Setting up \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.0) { badge(s.1) }
                        .coreCard(s.1 == .active ? GlassInk.wellHover : .clear, radius: Radius.row)
                }
            }
            .frame(width: Space.s8 * 13)
            if let e = project.repos.compactMap(\.fetchError).first {
                Text(e).foregroundStyle(GlassInk.redInk).multilineTextAlignment(.center)
                    .frame(maxWidth: Space.s8 * 13)
            }
        }
    }

    private func badge(_ s: Step) -> StateBadge {
        switch s {
        case .done: StateBadge("Done", tone: .done, symbol: "checkmark.circle")
        case .active: StateBadge("In progress", tone: .warn, symbol: "gearshape")
        case .failed: StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
        case .waiting: StateBadge("Waiting", tone: .queue, symbol: "clock")
        }
    }
}

/// "Ready to start": the drafted run in one line (See Changes, Undo) and what is still missing. Start waits for the secrets.
private struct ReadyToStart: View {
    let project: ProjectItem
    let draft: RunDraft

    var body: some View {
        VStack(spacing: Space.s4) {
            Text("\(project.name) is ready to start").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "sparkle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(summary).fixedSize(horizontal: false, vertical: true)
                    // The converter (P4) and its undo arrive with the run engine; the actions are in place for them.
                    HStack(spacing: Space.s1) {
                        Button("See Changes") {}.buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(true)
                        Button("Undo") {}.buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(true)
                    }
                    .help("The drafted run and its undo arrive with the run engine")
                }
            }
            .padding(Space.s3).frame(maxWidth: Space.s8 * 14, alignment: .leading)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            if !draft.secrets.isEmpty {
                Text(secretsLine).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 14)
            }
            HStack(spacing: Space.s2) {
                Soon(prominent: false, help: "Secrets arrive with the run engine") {
                    Label("Set Secrets…", systemImage: "key")
                }
                Soon(prominent: false, help: "Start stays off until the secrets are set") {
                    Label("Start", systemImage: "play")
                }
            }
        }
    }

    private var summary: AttributedString {
        var a = AttributedString("Run drafted from ")
        var f = AttributedString(draft.source)
        f.font = .system(size: MacTextSize.body, design: .monospaced)
        a += f
        a += AttributedString(": \(draft.services.count) services (\(draft.services.joined(separator: ", "))).")
        return a
    }

    private var secretsLine: AttributedString {
        var a = AttributedString("\(draft.secrets.count) secrets are needed before the first start: ")
        for (i, s) in draft.secrets.enumerated() {
            var n = AttributedString(s)
            n.font = .system(size: MacTextSize.body, design: .monospaced)
            a += n
            a += AttributedString(i < draft.secrets.count - 1 ? ", " : ".")
        }
        return a
    }
}
