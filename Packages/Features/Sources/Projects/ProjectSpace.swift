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
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
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

private struct TopBar: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        HStack(spacing: Space.s3) {
            BackButton("Projects") { model.closeProject() }
            ProjectMark(name: project.name, colour: model.colour(project), size: 28).padding(.leading, Space.s2)
            Text(project.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
            StateWord(tag: project.tag)
            Spacer(minLength: Space.s3)
            Text("Public link").foregroundStyle(GlassInk.secondary)
            CoreSwitch(
                "",
                isOn: Binding(
                    get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
            )
            .disabled(model.readOnly).accessibilityLabel("Public link")
            .help("While this project runs, anyone with \(project.link) can open it")
            soon("Start", symbol: "play", prominent: false, help: "Starting a project arrives with the run engine")
            soon("", symbol: "terminal", prominent: false, help: "A project terminal arrives with the run engine")
            soon(
                "New AI Session", symbol: "plus", prominent: true,
                help: "AI sessions in a project arrive with the next update")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, minHeight: Space.s8 + Space.s5)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    /// A control whose feature is not built yet: drawn dim and off, with its reason as the tooltip.
    private func soon(_ title: String, symbol: String, prominent: Bool, help: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
            if !title.isEmpty { Text(title).coreFont(size: MacTextSize.body, weight: .semibold) }
        }
        .foregroundStyle(prominent ? Color.white : GlassInk.primary)
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
        .background(prominent ? GlassInk.blue : GlassInk.well, in: coreShape(Radius.control))
        .opacity(0.5)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? "Terminal" : title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(help)
    }
}

/// The state beside the name: its square and word, no card.
private struct StateWord: View {
    let tag: ProjectItem.Tag
    var body: some View {
        HStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(hue).frame(width: 8, height: 8)
            Text(word).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    private var word: String {
        switch tag {
        case .running: "Running"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .settingUp: "Setting up"
        case .new: "Stopped"
        }
    }
    private var hue: Color {
        switch tag {
        case .running: GlassInk.green
        case .failed: GlassInk.red
        case .settingUp: GlassInk.amber
        default: GlassInk.slate
        }
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
        .frame(width: Space.s8 + Space.s3).frame(maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
    private func tile(_ name: String, _ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol).coreFont(size: MacTextSize.title, weight: .regular)
            .frame(width: Space.s8, height: Space.s8)
            .background(on ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .opacity(on ? 1 : 0.45)
            .help(on ? name : "\(name) arrives with the next update")
            .accessibilityLabel(name)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
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
                        Text("No AI sessions yet. New ones start in their own clone of this project's repos.")
                            .fixedSize(horizontal: false, vertical: true)
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
                            Button {
                                NewProjectDialogs.openAddRepos(model, project)
                            } label: {
                                Image(systemName: "plus").coreFont(size: MacTextSize.title, weight: .regular)
                                    .frame(width: 24, height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help("Add repos to \(project.name)").accessibilityLabel("Add repos")
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
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(GlassInk.slate).frame(
                            width: 8, height: 8)
                        Text(s)
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
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(project.repos) { r in
                    HStack(spacing: Space.s3) {
                        Image(systemName: "arrow.triangle.branch").coreFont(size: MacTextSize.title)
                            .foregroundStyle(GlassInk.secondary).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.name).lineLimit(1)
                            Text(repoLine(r)).foregroundStyle(
                                r.fetchError == nil ? GlassInk.secondary : GlassInk.redInk
                            )
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .help(r.remoteURL)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func repoLine(_ r: RepoItem) -> String {
        if let e = r.fetchError { return "\(r.branch) · copy failed: \(e)" }
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
                RoundedRectangle(cornerRadius: Radius.cardMac, style: .continuous).fill(GlassInk.well)
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

    private var steps: [(String, Step, String)] {
        let failed = project.repos.first { $0.fetchError != nil }
        let copied = project.repos.allSatisfy { $0.fetchedAt != nil }
        let copy: Step = failed != nil ? .failed : copied ? .done : .active
        let after: Step = copy == .done ? .done : .waiting
        return [
            (
                "Copy \(ProjectItem.count(project.repos.count, "repo")) to the Core", copy,
                failed != nil ? "failed" : copied ? "done" : ""
            ),
            ("Read the repos", after, after == .done ? "done" : ""),
            ("Draft the run from the repos", copy == .done ? .active : .waiting, ""),
            ("Create the Brain room “\(project.name)”", .waiting, ""),
        ]
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            Text("Setting up \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: Space.s3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(hue(s.1)).frame(width: 8, height: 8)
                        Text(s.0).foregroundStyle(s.1 == .waiting ? GlassInk.secondary : GlassInk.primary)
                        Spacer(minLength: Space.s5)
                        Text(s.2).foregroundStyle(GlassInk.secondary)
                    }
                    .padding(.horizontal, Space.s3).frame(height: Space.s8 + Space.s1)
                    .background(s.1 == .active ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(label(s.1))
                }
            }
            .frame(width: Space.s8 * 11)
            if let e = project.repos.compactMap(\.fetchError).first {
                Text(e).foregroundStyle(GlassInk.redInk).multilineTextAlignment(.center)
                    .frame(maxWidth: Space.s8 * 11)
            }
        }
    }

    private func hue(_ s: Step) -> Color {
        switch s {
        case .done: GlassInk.green
        case .active: GlassInk.amber
        case .failed: GlassInk.red
        case .waiting: GlassInk.slate
        }
    }
    private func label(_ s: Step) -> String {
        switch s {
        case .done: "done"
        case .active: "in progress"
        case .failed: "failed"
        case .waiting: "waiting"
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
                    HStack(spacing: Space.s2) {
                        // The converter (P4) and its undo arrive with the run engine; the words are in place for them.
                        Text("See Changes").underline().foregroundStyle(GlassInk.secondary)
                        Text("·").foregroundStyle(GlassInk.secondary)
                        Text("Undo").underline().foregroundStyle(GlassInk.secondary)
                    }
                }
            }
            .padding(Space.s3).frame(maxWidth: Space.s8 * 14, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            if !draft.secrets.isEmpty {
                Text(secretsLine).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 14)
            }
            HStack(spacing: Space.s2) {
                tile("Set Secrets…", "key", prominent: false)
                tile("Start", "play", prominent: false).opacity(0.5)
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

    private func tile(_ title: String, _ symbol: String, prominent: Bool) -> some View {
        Label(title, systemImage: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
            .background(GlassInk.wellHover, in: coreShape(Radius.control))
            .help(title == "Start" ? "Start stays off until the secrets are set" : "Secrets arrive with the run engine")
    }
}
