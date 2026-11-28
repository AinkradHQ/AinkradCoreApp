import CoreUI
import SwiftUI

/// What covers the stage when the project is not running: over a blurred, dimmed stage, the words of the state and what to do.
/// Starting shows progress and the step words; stopped one start button; failed the real reason and a typed fix per cause.
struct StageCover: View {
    let model: ProjectsModel
    let project: ProjectItem
    let kind: ProjectKind
    @State private var run: RunPageModel?

    private var can: Bool { model.canControl(project) && project.startBlock == nil }
    private var steps: [StartStep] { project.live?.steps ?? [] }
    private var app: Bool { kind == .app }

    var body: some View {
        VStack(spacing: Space.s3) {
            switch project.setup {
            case .noRepos: noRepos
            case .copying, .checking, .copyFailed: SettingUp(project: project)
            case .needsSetup: NeedsSetup(model: model, project: project)
            case .ready(let draft): ReadyToStart(model: model, project: project, draft: draft)
            case .ran:
                switch project.run?.state ?? .stopped {
                case .running: if project.crash != nil, !project.stale { failed } else { EmptyView() }
                case .starting: starting
                case .stopped: stopped
                case .failed: failed
                }
            }
        }
        .multilineTextAlignment(.center).padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A scrim under the words: whatever the stage shows behind them (a bright window, a pale site) never fights the text.
        .background(.ultraThinMaterial)
        .background(GlassInk.shade(0.55))
    }

    private func title(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.title + 2, weight: .semibold).accessibilityAddTraits(.isHeader)
    }

    private func line(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Space.s8 * 13)
    }

    private var noRepos: some View {
        VStack(spacing: Space.s2) {
            title("Add a repo to \(project.name)")
            line("Pick repos from GitHub. The Core keeps a copy and drafts how to run them.")
            Button {
                NewProjectDialogs.openAddRepos(model, project)
            } label: {
                Label("Add Repos…", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.readOnly)
            .accessibilityIdentifier("project-add-repos-button")
        }
    }

    private var starting: some View {
        VStack(spacing: Space.s3) {
            title(app ? "Building \(project.name)" : "Starting \(project.name)")
            line(startLine)
            if let p = project.live?.progress {
                CoreMeter(p, label: "Starting \(project.name)").frame(width: 280)
            } else {
                CoreWorkingBar(width: 280)
            }
            if !steps.isEmpty { StartStepsList(steps: steps) }
        }
    }

    private var startLine: String {
        if let i = steps.firstIndex(where: { $0.state == .active }) {
            return "\(steps[i].title) · step \(i + 1) of \(steps.count)"
        }
        return project.live?.progressLine ?? "Starting…"
    }

    private var stopped: some View {
        let n = project.draft?.services.count ?? 0
        let where_ = project.live?.runner ?? model.coreName
        return VStack(spacing: Space.s3) {
            title(
                app
                    ? "Ready to build" : kind == .infra ? "The stack is stopped" : "\(project.name) is stopped")
            if let why = project.live?.stopWords { line(why) }
            if let at = project.live?.lastActivity { line("Last visited \(runsAgo(at, now: model.now())).") }
            line(
                app
                    ? "Build and run it on \(where_)."
                    : kind == .infra
                        ? "Start the stack to bring \(n > 0 ? "all \(n) services" : "its services") up on \(where_)."
                        : "Start it to see the live site here. \(ProjectRules.idleSentence(minutes: project.idleMinutes, never: project.idleNever))"
            )
            startButton(prominent: true)
        }
    }

    private var failed: some View {
        let step = steps.first { $0.state == .failed }
        let why =
            step.map { "The build failed at “\($0.title)”" }
            ?? project.crash.map { $0.restarts > 0 ? "\($0.service) kept crashing and was stopped" : $0.words }
            ?? project.live?.failure ?? "The last start failed."
        let detail = step?.detail ?? project.live?.failureFix ?? ""
        return VStack(spacing: Space.s4) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(GlassInk.red).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(why).coreFont(size: MacTextSize.body, weight: .semibold)
                    if !detail.isEmpty { Text(detail).foregroundStyle(GlassInk.secondary) }
                }
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, Space.s3 + 2).padding(.vertical, Space.s3).frame(
                maxWidth: Space.s8 * 15, alignment: .leading
            )
            .coreCard(GlassInk.card, radius: Radius.cardMac)
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.s2) {
                Button {
                    model.go(.logs, in: project.id)
                } label: {
                    Label("Show Log", systemImage: "text.alignleft")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Open the log of the last run")
                if let secret = project.failedSecret {
                    Button {
                        setSecret(secret)
                    } label: {
                        Label("Set \(secret)…", systemImage: "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly)
                    .help("Set the secret the setup is missing")
                } else if model.canStartSession(project) {
                    Button {
                        model.newSession(
                            in: project,
                            prompt: ProjectsModel.fixPrompt(
                                project: project.name, what: "The last start", details: [why, detail]))
                    } label: {
                        Label("Ask AI to Fix", systemImage: "sparkles")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, busy: model.startingSession.contains(project.id)))
                    .help("Start an AI session that begins with this failure")
                }
                startButton(prominent: true)
            }
        }
    }

    private func startButton(prominent: Bool) -> some View {
        Button {
            model.control(.start, project)
        } label: {
            Label(
                project.mainAction(view: kind).title, systemImage: project.tag == .failed ? "arrow.clockwise" : "play")
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary)).disabled(!can)
        .help(
            can
                ? "\(project.mainAction(view: kind).title) \(project.name)"
                : project.startBlock ?? ProjectHeader.cannot)
    }

    private func setSecret(_ name: String) {
        let r = run ?? RunPageModel(model: model, projectID: project.id)
        run = r
        Task {
            await r.load()
            RunDialogs.openSecret(r, project: project, name: name, replacing: false)
        }
    }
}
