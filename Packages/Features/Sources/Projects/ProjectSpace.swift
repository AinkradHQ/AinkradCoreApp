import AppKit
import CoreUI
import SwiftUI

/// The space of one project (details v2): a header, a thin icon rail and the module the rail picks. The Overview is the stage
/// and the modules; every other module opens as its own focused page (`Modules/`).
struct ProjectSpaceView: View {
    let model: ProjectsModel
    let project: ProjectItem
    /// What the back button does; nil goes back to the gallery of the Projects pane.
    var onBack: (() -> Void)?
    @State private var settled = false
    /// The kind the stage shows when the project has several; the header's main action follows it.
    @State private var stageKind: ProjectKind?
    /// The pane this space is in, for the keys it owns (⌘1…).
    var paneID = "projects"

    var body: some View {
        VStack(spacing: Space.s4) {
            ProjectHeader(model: model, project: project, stageKind: stageKind, onBack: onBack).coreRise(settled, 0)
            HStack(alignment: .top, spacing: Space.s4) {
                ProjectRail(model: model, project: project).coreRise(settled, 1)
                // Switching modules cross-fades; the islands of a page rise once, with the space.
                ZStack {
                    page.id(current).transition(
                        .asymmetric(
                            insertion: .opacity.animation(Motion.out(Motion.ui)),
                            removal: .opacity.animation(Motion.exit(0.12))))
                }
                .animation(Motion.out(Motion.ui), value: current)
            }
        }
        .onAppear { settled = true }
        .environment(\.spaceSettled, settled)
        .padding(Space.s4)
        .foregroundStyle(GlassInk.primary)
        .coreFont(size: MacTextSize.body)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-space")
        // Reads the run again while it starts or runs, and tells the Core a viewer is on the Overview or Run page.
        .task(id: "\(project.id) \(project.tag)") {
            await model.watch(project.id) { [model, id = project.id] in [.overview, .run].contains(model.moduleOf(id)) }
        }
        .environment(\.spaceProject, project.id)
        .environment(\.spacePane, paneID)
        // Every space on screen is kept fresh by the Core's events, in the Projects pane and in panes of their own.
        .onAppear { model.spaceAppeared(project.id) }
        .onDisappear { model.spaceGone(project.id) }
        // The live view of a project that is not running any more is left behind; it is made again when it runs.
        .onChange(of: project.tag) { _, tag in if tag != .running { model.dropLiveWeb(project.id) } }
    }

    /// The module shown: one the project's rail does not have (its kinds changed) falls back to the Overview.
    private var current: ProjectModule {
        let m = model.moduleOf(project.id)
        return m == .settings || ProjectModule.rail(for: project.allKinds).contains(m) ? m : .overview
    }

    @ViewBuilder private var page: some View {
        switch current {
        case .overview: Overview(model: model, project: project, stageKind: $stageKind)
        case .live: ModuleLiveSite(model: model, project: project)
        case .builds: ModuleBuilds(model: model, project: project)
        case .services: ModuleServices(model: model, project: project)
        case .docs: ModuleDocs(model: model, project: project)
        case .logs: ModuleLogs(model: model, project: project).id(project.id)
        case .run: RunsPage(model: model, project: project)
        case .ai: ModuleAISessions(model: model, project: project)
        case .brain: ModuleBrain(model: model, project: project)
        case .repos: ModuleRepos(model: model, project: project)
        case .activity: ModuleActivity(model: model, project: project)
        case .settings: ModuleSettings(model: model, project: project)
        }
    }
}

/// A project's space in a pane of its own (Settings > Projects > Options > "Open projects in" = A new workspace). It reads the
/// project again on every change, and going back closes the pane.
struct ProjectPaneView: View {
    let model: ProjectsModel
    let id: Int64
    @FocusState private var paneFocus: Bool

    private func close() { model.leaveSpace(id) { model.host.shell.closePane(ProjectsModel.paneID(id)) } }

    var body: some View {
        ZStack {
            if let project = model.project(id) {
                ProjectSpaceView(model: model, project: project, onBack: { close() }, paneID: ProjectsModel.paneID(id))
                    .id(project.id)
            } else {
                Text("This project is not in the list any more.").foregroundStyle(GlassInk.secondary)
            }
        }
        // Like every app: the pane draws Settings › Appearance (blur, transparency), or the Projects own Look.
        .paneLook(AppLookPrefs.shared("projects").look)
        .appLookTheme(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
        // Esc goes back here as it does in the Projects pane.
        .focusable()
        .focused($paneFocus)
        .focusEffectDisabled()
        .onAppear { paneFocus = true }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }
}

private struct SpaceProjectKey: EnvironmentKey { static let defaultValue: Int64 = 0 }
private struct SpacePaneKey: EnvironmentKey { static let defaultValue = "projects" }
extension EnvironmentValues {
    /// The project the space around a view shows.
    var spaceProject: Int64 {
        get { self[SpaceProjectKey.self] }
        set { self[SpaceProjectKey.self] = newValue }
    }
    /// The pane the space is in: only the one in front owns the ⌘ keys.
    var spacePane: String {
        get { self[SpacePaneKey.self] }
        set { self[SpacePaneKey.self] = newValue }
    }
}
