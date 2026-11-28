import AppKit
import CoreUI
import SwiftUI

/// The header of a project's space (details v2): back, the project's mark, its name with one chip per kind and the state word,
/// one line of facts, quiet Restart, Stop and New AI Session, and the one prominent action that follows the state and the kind
/// the stage shows.
struct ProjectHeader: View {
    let model: ProjectsModel
    let project: ProjectItem
    /// The kind the stage shows (several kinds switch on the stage); nil is the project's first.
    let stageKind: ProjectKind?
    let onBack: (() -> Void)?
    @State private var run: RunPageModel?

    private var view: ProjectKind {
        stageKind.flatMap { project.allKinds.contains($0) ? $0 : nil } ?? project.allKinds[0]
    }

    var body: some View {
        let can = model.canControl(project)
        let block = project.controlBlock(canControl: can)
        let main = project.mainAction(starting: model.controlling.contains(project.id), view: view)
        ViewThatFits(in: .horizontal) {
            row(compact: false, can: can, block: block, main: main)
            row(compact: true, can: can, block: block, main: main)
        }
        .padding(.horizontal, Space.s3).frame(height: Space.s8 * 2).frame(maxWidth: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    private func row(compact: Bool, can: Bool, block: String?, main: MainAction) -> some View {
        HStack(spacing: Space.s3) {
            BackButton("Projects") {
                if let onBack { onBack() } else { model.closeProject() }
            }
            ProjectMark(name: project.name, colour: model.colour(project), size: Space.s8 + Space.s1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(project.name).coreFont(size: MacTextSize.title + 2, weight: .semibold).lineLimit(1)
                    ForEach(project.allKinds) { KindChip(kind: $0) }
                    SpaceStateBadge(project: project, now: model.now())
                }
                Text(facts).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if !project.archived, project.kind.runs, project.tag == .running {
                quiet("Restart", "arrow.clockwise", .restart, block: block, compact: compact)
            }
            if !project.archived, project.kind.runs, project.tag == .running || project.tag == .starting {
                quiet("Stop", "stop", .stop, block: block, compact: compact)
            }
            Button {
                model.newSession(in: project)
            } label: {
                if compact { Image(systemName: "sparkles") } else { Label("New AI Session", systemImage: "sparkles") }
            }
            .buttonStyle(CoreButtonStyle(.secondary)).disabled(!model.canStartSession(project))
            .help(
                model.canStartSession(project) ? "Start an AI session in \(project.name)" : model.sessionBlock(project)
            )
            .accessibilityLabel("New AI Session").accessibilityIdentifier("project-new-session")
            Button {
                perform(main)
            } label: {
                Label(main.title, systemImage: main.symbol)
            }
            .buttonStyle(CoreButtonStyle(.prominent, busy: main.busy))
            .disabled(!enabled(main, can: can))
            .help(why(main, can: can)).accessibilityIdentifier("project-main-action")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One line: where it lives, what it is built for, what it runs; and, while it runs, when it stops by itself.
    private var facts: String {
        var out: [String] = []
        for k in project.allKinds {
            switch k {
            case .web: out.append(project.link)
            case .app:
                let p = ProjectKind.platforms(project.repos)
                out.append(p.isEmpty ? "Platform not known yet" : p.joined(separator: " · "))
            case .infra:
                let n = project.live?.services.count ?? project.draft?.services.count ?? 0
                out.append(
                    n > 0
                        ? "\(ProjectItem.count(n, "service")) · \(project.live?.runner ?? model.coreName)"
                        : model.coreName)
            case .other: out.append(project.description.isEmpty ? "Notes and documents" : project.description)
            }
        }
        if project.tag == .running, let idle = project.live?.idle { out.append(idle) }
        return out.joined(separator: " · ")
    }

    private func enabled(_ a: MainAction, can: Bool) -> Bool {
        switch a.kind {
        case .start, .runAgain: can && (a.kind == .runAgain || project.startBlock == nil)
        case .addRepos, .setUp, .setSecrets, .unarchive: can
        case .newDoc: !model.readOnly && model.lore != nil
        case .reviewRepos, .open, .openServices, .starting, .waiting: true
        }
    }

    private func why(_ a: MainAction, can: Bool) -> String {
        if !enabled(a, can: can) { return project.startBlock ?? Self.cannot }
        switch a.kind {
        case .start: return "\(a.title) \(project.name)"
        case .runAgain: return "Build and run \(project.name) again"
        case .openServices: return "See each service, its health and its use"
        case .addRepos: return "Pick the repos \(project.name) is made of"
        case .setUp: return "Draft the setup from the repo, or write it by hand"
        case .setSecrets: return "Set the secrets the setup needs before the first start"
        case .newDoc: return "Write a new doc in \(project.name)"
        case .open: return "Open \(project.link) in the browser"
        case .unarchive: return "Bring \(project.name) back to the Projects list"
        case .reviewRepos: return "A repo could not be copied. See why in Repos."
        case .starting, .waiting: return a.title
        }
    }

    static let cannot = "Not available while this device cannot change projects or the Core is unreachable"

    private func perform(_ a: MainAction) {
        switch a.kind {
        case .start: model.control(.start, project)
        case .runAgain: model.control(.restart, project)
        case .openServices: model.module = .services
        case .addRepos: NewProjectDialogs.openAddRepos(model, project)
        case .reviewRepos: model.module = .repos
        case .unarchive: Task { await model.unarchive(project) }
        case .newDoc: model.newDoc(in: project)
        case .open:
            if let url = URL(string: "https://\(project.link)") { NSWorkspace.shared.open(url) }
        case .setUp, .setSecrets:
            let r = run ?? RunPageModel(model: model, projectID: project.id)
            run = r
            Task {
                await r.load()
                if a.kind == .setUp {
                    RunDialogs.openSetup(r, project: project)
                } else {
                    RunDialogs.openSecret(r, project: project, name: project.draft?.secrets.first, replacing: false)
                }
            }
        case .starting, .waiting: break
        }
    }

    private func quiet(_ title: String, _ symbol: String, _ action: RunAction, block: String?, compact: Bool)
        -> some View
    {
        Button {
            model.control(action, project)
        } label: {
            if compact { Image(systemName: symbol) } else { Label(title, systemImage: symbol) }
        }
        .buttonStyle(CoreButtonStyle(.secondary)).disabled(block != nil)
        .help(block ?? "\(title) \(project.name)").accessibilityLabel(title)
    }
}

/// A kind as a small chip: its symbol and short name on a quiet well.
struct KindChip: View {
    let kind: ProjectKind
    var body: some View {
        HStack(spacing: Space.s1 + 1) {
            Image(systemName: kind.symbol).coreFont(size: MacTextSize.meta, weight: .medium).accessibilityHidden(true)
            Text(kind.chipName).coreFont(size: MacTextSize.meta + 1, weight: .medium)
        }
        .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm)
        .coreCard(GlassInk.well, radius: Radius.chip).fixedSize()
        .accessibilityElement(children: .combine)
    }
}

extension ProjectKind {
    /// The chip and the stage switch: "Web", "App", "Infra", "Docs".
    var chipName: String {
        switch self {
        case .web: "Web"
        case .app: "App"
        case .infra: "Infra"
        case .other: "Docs"
        }
    }
}
