import AppKit
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
    @State private var settled = false

    var body: some View {
        VStack(spacing: Space.s2) {
            TopBar(model: model, project: project, onBack: onBack).coreRise(settled, 0)
            HStack(alignment: .top, spacing: Space.s2) {
                Rail(model: model, kind: project.kind).coreRise(settled, 1)
                // Switching pages cross-fades; each page's islands then settle in one after another.
                // Pages fade; their islands do not rise again (they rise once, with the space).
                ZStack {
                    page.id(model.section).transition(
                        .asymmetric(
                            insertion: .opacity.animation(Motion.out(Motion.ui)),
                            removal: .opacity.animation(Motion.exit(0.12))))
                }
                .animation(Motion.out(Motion.ui), value: model.section)
            }
        }
        .onAppear { settled = true }
        .environment(\.spaceSettled, settled)
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
        case .run where project.kind == .other:
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
    @State private var run: RunPageModel?

    var body: some View {
        let can = model.canControl(project)
        let block = project.controlBlock(canControl: can)
        let main = project.mainAction(starting: model.controlling.contains(project.id))
        AppHeader {
            BackButton("Projects") {
                if let onBack { onBack() } else { model.closeProject() }
            }
            ProjectMark(name: project.name, colour: model.colour(project), size: MacSize.controlMd)
            Text(project.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
            SpaceStateBadge(project: project, now: model.now())
        } actions: {
            // Stop and Restart sit quietly beside the one main action; they ask the Core's run routes behind Touch ID.
            if !project.archived, project.kind.runs {
                if project.tag == .running {
                    secondary("Restart", "arrow.clockwise", .restart, block: block)
                }
                if project.tag == .running || project.tag == .starting {
                    secondary("Stop", "stop", .stop, block: block)
                }
            }
            Button {
                model.newSession(in: project)
            } label: {
                Label("New AI Session", systemImage: "sparkles")
            }
            .buttonStyle(CoreButtonStyle(.secondary)).disabled(!model.canStartSession(project))
            .help(model.sessionBlock(project)).accessibilityIdentifier("project-new-session")
            Button {
                perform(main)
            } label: {
                Label(main.title, systemImage: main.symbol)
            }
            .buttonStyle(CoreButtonStyle(.prominent)).breathing(main.busy)
            .disabled(main.busy || !enabled(main, can: can))
            .help(why(main, can: can)).accessibilityIdentifier("project-main-action")
        }
        .frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    static let cannot = "Not available while this device cannot change projects or the Core is unreachable"

    private func enabled(_ a: MainAction, can: Bool) -> Bool {
        switch a.kind {
        case .start: can && project.startBlock == nil
        case .addRepos, .setUp, .setSecrets, .unarchive: can
        case .newDoc: !model.readOnly && model.lore != nil
        case .reviewRepos, .open, .starting, .waiting: true
        }
    }

    private func why(_ a: MainAction, can: Bool) -> String {
        if !enabled(a, can: can) { return project.startBlock ?? Self.cannot }
        switch a.kind {
        case .start: return "\(a.title) \(project.name)"
        case .addRepos: return "Pick the repos \(project.name) is made of"
        case .setUp: return "Draft the setup from the repo, or write it by hand"
        case .setSecrets: return "Set the secrets the setup needs before the first start"
        case .newDoc: return "Write a new doc in \(project.name)"
        case .open:
            return project.kind == .web ? "Open \(project.link) in the browser" : "Open the runs of \(project.name)"
        case .unarchive: return "Bring \(project.name) back to the Projects list"
        case .reviewRepos: return "A repo could not be copied. See why in Repos."
        case .starting, .waiting: return a.title
        }
    }

    private func perform(_ a: MainAction) {
        switch a.kind {
        case .start: model.control(.start, project)
        case .addRepos: NewProjectDialogs.openAddRepos(model, project)
        case .reviewRepos: model.section = .repos
        case .unarchive: Task { await model.unarchive(project) }
        case .newDoc:
            Task {
                guard let n = try? await model.lore?.create(text: "", project: String(project.id)) else {
                    model.host.shell.showToast("Could not create the doc. Try again.", kind: .warn)
                    return
                }
                model.openNote?(n.id)
            }
        case .open:
            if project.kind == .web, let url = URL(string: "https://\(project.link)") {
                NSWorkspace.shared.open(url)
            } else {
                model.section = .run
            }
        case .setUp, .setSecrets:
            let r = run ?? RunPageModel(model: model, projectID: project.id)
            run = r
            Task {
                await r.load()
                if a.kind == .setUp {
                    RunDialogs.openSetup(r, project: project)
                } else {
                    RunDialogs.openSecret(
                        r, project: project, name: project.draft?.secrets.first, replacing: false)
                }
            }
        case .starting, .waiting: break
        }
    }

    private func secondary(_ title: String, _ symbol: String, _ action: RunAction, block: String?) -> some View {
        Button {
            model.control(action, project)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(CoreButtonStyle(.secondary)).disabled(block != nil)
        .help(block ?? "\(title) \(project.name)")
    }
}

/// The thin rail of the space: one icon per page, its name and key on hover, ⌘1 to ⌘7 from anywhere in the space.
private struct Rail: View {
    let model: ProjectsModel
    let kind: ProjectKind
    var body: some View {
        VStack(spacing: Space.s1) {
            // Docs (R6-06) is the last case, so it follows Brain; Project Settings stays at the bottom.
            ForEach(ProjectSection.allCases.filter { $0 != .settings && ($0 != .run || kind.runs) }) { tile($0) }
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
        // Like every app: the pane draws Settings › Appearance (blur, transparency), or the Projects own Look.
        .paneLook(AppLookPrefs.shared("projects").look)
        .appLookTheme(AppLookPrefs.shared("projects"))
        .clipShape(coreShape(Radius.cardMac))
    }
}
