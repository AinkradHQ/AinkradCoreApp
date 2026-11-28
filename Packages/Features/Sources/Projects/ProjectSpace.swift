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
        .task(id: "\(project.id) \(project.tag)") { await model.watch(project.id) }
    }

    /// The module shown: one the project's rail does not have (its kinds changed) falls back to the Overview.
    private var current: ProjectModule {
        let m = model.module
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
        // Like every app: the pane draws Settings › Appearance (blur, transparency), or the Projects own Look.
        .paneLook(AppLookPrefs.shared("projects").look)
        .appLookTheme(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
    }
}
