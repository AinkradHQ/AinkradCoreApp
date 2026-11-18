import CoreUI
import SwiftUI

/// The space of one project: a top bar, a thin rail and the page the rail picks. P7-02 builds the top bar, the rail and the
/// Overview; the other pages are stubs with the mockup's empty words until P7-03 (Repos, AI Sessions, Brain), P7-04 (Run)
/// and P7-05 (Project Settings).
struct ProjectSpaceView: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        VStack(spacing: Space.s2) {
            TopBar(model: model, project: project)
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
        case .repos:
            ReposPage(model: model, project: project)
        case .sessions:
            SessionsPage(model: model, project: project)
        case .brain:
            BrainPage(model: model, project: project)
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
            runButtons
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

    /// Restart and Stop while it runs, Stop while it starts, Start otherwise. Each asks the Core's run routes behind Touch ID.
    @ViewBuilder private var runButtons: some View {
        let can = model.canControl(project)
        switch project.tag {
        case .running:
            run("Restart", "arrow.clockwise", .restart, enabled: can)
            run("Stop", "stop", .stop, enabled: can)
        case .starting:
            run("Stop", "stop", .stop, enabled: can)
        case .stopped, .failed:
            run("Start", "play", .start, enabled: can)
        case .settingUp, .new:
            run(
                "Start", "play", .start, enabled: false,
                why: "Start is ready once the repos are copied and the run is drafted")
        }
    }

    private func run(
        _ title: String, _ symbol: String, _ action: RunAction, enabled: Bool,
        why: String = "Not available while this device cannot change projects or the Core is unreachable"
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

/// The thin rail of the space: one icon per page, its name and key on hover, ⌘1 to ⌘6 from anywhere in the space.
private struct Rail: View {
    let model: ProjectsModel
    var body: some View {
        VStack(spacing: Space.s1) {
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
