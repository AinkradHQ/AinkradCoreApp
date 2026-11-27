import CoreUI
import SwiftUI

/// The space of one project: a top bar, a thin rail and the page the rail picks. P7-02 builds the top bar, the rail and the
/// Overview, P7-03 the Repos, AI Sessions and Brain pages, P7-04 the Run page; Project Settings is a stub with the mockup's
/// empty words until P7-05.
struct ProjectSpaceView: View {
    let model: ProjectsModel
    let project: ProjectItem
    /// What the back button does; nil goes back to the gallery of the Projects pane.
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s2) {
            TopBar(model: model, project: project, onBack: onBack)
            HStack(alignment: .top, spacing: Space.s2) {
                Rail(model: model)
                page
            }
        }
        .padding(Space.s2)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-space")
        // Reads the run again while it starts or runs, and tells the Core a viewer is on the Overview or Run page.
        .task(id: "\(project.id) \(project.tag)") { await model.watch(project.id) }
    }

    @ViewBuilder private var page: some View {
        switch model.section {
        case .overview:
            Overview(model: model, project: project)
        case .run:
            RunsPage(model: model, project: project).id(project.id)
        case .repos:
            ReposPage(model: model, project: project)
        case .sessions:
            SessionsPage(model: model, project: project)
        case .brain:
            BrainPage(model: model, project: project)
        case .docs:
            DocsPage(model: model, project: project)
        case .settings:
            SettingsPage(model: model, project: project)
        default:
            let e = model.section.empty(project)
            Island(e.title) {
                Text(e.line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("project-page-\(model.section.title)")
        }
    }
}

private struct TopBar: View {
    let model: ProjectsModel
    let project: ProjectItem
    let onBack: (() -> Void)?

    var body: some View {
        AppHeader {
            BackButton("Projects") {
                if let onBack { onBack() } else { model.closeProject() }
            }
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
            runButtons
            // No terminal button: a project's clone lives inside an AI session's folder, and Terminals has no project folder
            // of the Core's to open yet (proposal in the lane report).
            Button {
                model.newSession(in: project)
            } label: {
                Label("New AI Session", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(!model.canStartSession(project))
            .help(model.sessionBlock(project)).accessibilityIdentifier("project-new-session")
        }
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    static let cannot = "Not available while this device cannot change projects or the Core is unreachable"

    /// Restart and Stop while it runs, Stop while it starts, Start otherwise. Each asks the Core's run routes behind Touch ID.
    @ViewBuilder private var runButtons: some View {
        let can = model.canControl(project)
        if project.archived {
            Button {
                Task { await model.unarchive(project) }
            } label: {
                Label("Unarchive", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CoreButtonStyle(.secondary)).disabled(!can)
            .help("Bring \(project.name) back to the Projects list")
        } else {
            switch project.tag {
            case .running:
                run("Restart", "arrow.clockwise", .restart, enabled: can)
                run("Stop", "stop", .stop, enabled: can)
            case .starting:
                run("Stop", "stop", .stop, enabled: can)
            case .stopped, .failed:
                run(
                    "Start", "play", .start, enabled: can && project.startBlock == nil,
                    why: project.startBlock ?? Self.cannot)
            case .settingUp, .new:
                run(
                    "Start", "play", .start, enabled: false,
                    why: project.startBlock ?? "Start is ready once the repos are copied and the setup is read")
            }
        }
    }

    private func run(
        _ title: String, _ symbol: String, _ action: RunAction, enabled: Bool,
        why: String = TopBar.cannot
    ) -> some View {
        Button {
            model.control(action, project)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(CoreButtonStyle(.secondary)).disabled(!enabled)
        .help(enabled ? "\(title) \(project.name)" : why)
    }
}

/// The thin rail of the space: one icon per page, its name and key on hover, ⌘1 to ⌘7 from anywhere in the space.
private struct Rail: View {
    let model: ProjectsModel
    var body: some View {
        VStack(spacing: Space.s1) {
            // Docs (R6-06) is the last case, so it follows Brain; Project Settings stays at the bottom.
            ForEach(ProjectSection.allCases.filter { $0 != .settings }) { tile($0) }
            Spacer(minLength: 0)
            tile(.settings)
        }
        .padding(Space.s1)
        .frame(maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }
    private func tile(_ s: ProjectSection) -> some View {
        CoreIconButton(symbol: s.symbol, label: "\(s.title)  ⌘\(s.key)", selected: model.section == s) {
            model.section = s
        }
        .keyboardShortcut(KeyEquivalent(s.key), modifiers: .command)
        .accessibilityIdentifier("project-rail-\(s.title)")
    }
}

/// A project's space in a pane of its own (Settings > Projects > Options > "Open projects in" = A new workspace). It reads the
/// project again on every change, and going back closes the pane.
struct ProjectPaneView: View {
    let model: ProjectsModel
    let id: Int64

    var body: some View {
        ZStack {
            if let project = model.project(id) {
                ProjectSpaceView(model: model, project: project) {
                    model.host.shell.closePane(ProjectsModel.paneID(id))
                }
            } else {
                Text("This project is not in the list any more.").foregroundStyle(GlassInk.secondary)
            }
        }
        .appLook(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
    }
}
