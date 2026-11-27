import AppKit
import CoreUI
import SwiftUI

/// The big island of the Overview: the live app's address with Copy and Open, and the stage under it. The stage is the
/// running app once the Core can serve it, and until then the words for where the project stands: stopped, starting,
/// failed, no repos, setting up, ready to start.
struct LiveApp: View {
    let model: ProjectsModel
    let project: ProjectItem

    private var running: Bool { project.tag == .running }
    @State private var web = LiveWebModel()
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// A project with a run has a picture behind its words: the live app, or its last snapshot greyed.
    private var hasPicture: Bool { !project.repos.isEmpty && project.run != nil }
    private var previewURL: URL? { model.previewURL(for: project) }
    private var isDemo: Bool {
        #if DEBUG
        model.demoPage
        #else
        false
        #endif
    }
    /// Why the live view cannot be shown, in the Core's words or the web view's.
    private var problem: String? {
        #if DEBUG
        if let d = model.demoPreviewProblem { return d }
        #endif
        if case .failed(let why) = web.state { return why }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if project.kind != .web {
                KindHeader(project: project)
            } else {
                HStack(spacing: Space.s2) {
                    Text(project.link).lineLimit(1)
                    Text(note).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Public link").foregroundStyle(GlassInk.secondary)
                    CoreSwitch(
                        "",
                        isOn: Binding(
                            get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                    )
                    .disabled(model.readOnly).accessibilityLabel("Public link")
                    .help("While this project runs, anyone with \(project.link) can open it")
                    if project.expose { CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { copyLink() } }
                    CoreIconButton(symbol: "arrow.up.forward.square", label: "Open in the browser") { openLink() }
                        .disabled(!running || !project.expose)
                        .help(
                            project.expose
                                ? "Open the public link" : "Turn the public link on to open it in the browser")
                }
                .padding(.leading, Space.s2)
            }
            if project.stale {
                CoreNotice(
                    symbol: "wifi.exclamationmark", title: "The Core is not answering.",
                    text: "This is how \(project.name) looked when it last did. It will update once the Core is back.",
                    tone: .warn)
            }
            // The picture and the words are overlays of a plain well, so neither can change the size of the stage: the
            // bottom row of the page stays where it is in every state.
            Color.clear.coreCard(GlassInk.well, radius: Radius.cardMac)
                .overlay {
                    if hasPicture, project.kind == .web {
                        picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Not running: the picture is only a hint of the page, so the words over it read clean.
                            .opacity(running ? 1 : 0.65).blur(radius: running ? 0 : Space.s2).clipped()
                    }
                }
                .overlay { stageLayer }
                .clipShape(coreShape(Radius.cardMac))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    /// The words of the state; a change of state crossfades (and scales 0.98, but not with Reduce Motion).
    private var stageLayer: some View {
        ZStack {
            overlay.id(stageKey)
                .transition(.opacity.combined(with: reduce ? .identity : .scale(scale: 0.98)))
        }
        .animation(Motion.out(Motion.ui), value: stageKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageKey: String {
        let setup: String =
            switch project.setup {
            case .noRepos: "none"
            case .copying, .checking, .copyFailed: "setting"
            case .needsSetup: "needs"
            case .ready: "ready"
            case .ran: "ran"
            }
        return "\(setup) \(project.run?.state ?? .stopped) \(web.state == .live) \(problem != nil) \(previewURL == nil)"
    }

    /// "· public · idle 4 min of 30", "· public while running", "· only your devices".
    private var note: String {
        guard project.expose else { return "· only your devices" }
        guard running else { return "· public while running" }
        if project.stale { return "· last seen running" }
        return ["· public", project.live?.idle].compactMap { $0 }.joined(separator: " · ")
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://\(project.link)", forType: .string)
        model.host.shell.showToast("Link copied")
    }

    private func openLink() {
        if let url = URL(string: "https://\(project.link)") { NSWorkspace.shared.open(url) }
    }

    @ViewBuilder private var stage: some View {
        switch project.setup {
        case .noRepos: noRepos
        case .ran:
            switch project.run?.state ?? .stopped {
            case .running: EmptyView()
            case .starting: startingStage
            case .stopped: stoppedStage
            case .failed: failedStage
            }
        case .copying, .checking, .copyFailed: SettingUp(project: project)
        case .needsSetup: NeedsSetup(model: model, project: project)
        case .ready(let draft): ReadyToStart(model: model, project: project, draft: draft)
        }
    }

    private var can: Bool { model.canControl(project) && project.startBlock == nil }

    private func start() -> some View {
        let title = project.mainAction().title
        Button {
            model.control(.start, project)
        } label: {
            Label(title, systemImage: "play")
        }
        .buttonStyle(CoreButtonStyle(.secondary)).disabled(!can)
        .help(
            can
                ? "Start \(project.name)"
                : project.startBlock
                    ?? "Not available while this device cannot change projects or the Core is unreachable")
    }

    private var noRepos: some View {
        VStack(spacing: Space.s2) {
            Text("Add a repo to \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .multilineTextAlignment(.center)
            line("Pick repos from GitHub. The Core keeps a copy and drafts how to run them.")
            Button {
                NewProjectDialogs.openAddRepos(model, project)
            } label: {
                Label("Add Repos…", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly)
            .padding(.top, Space.s1).accessibilityIdentifier("project-add-repos-button")
        }
    }

    /// The picture behind the stage: the running app in a web view, or the last snapshot of it (greyed unless running).
    @ViewBuilder private var picture: some View {
        #if DEBUG
        if running, model.demoPage { DemoSitePage(name: project.name, colour: model.colour(project)) } else { live }
        #else
        live
        #endif
    }

    @ViewBuilder private var live: some View {
        ZStack {
            ProjectPicture(project: project, colour: model.colour(project), illustrate: false)
            if let url = previewURL {
                LiveWebView(
                    url: url, model: web, preview: model.previewFetch.map { (project.id, model.previewCoreHost, $0) }
                ).opacity(web.state == .live ? 1 : 0)
                    .animation(Motion.out(Motion.ui), value: web.state)
                    .task(id: url) { await keepSnapshot() }
            }
        }
    }

    /// A picture of the live view a little after it loads, then every minute while the space is open.
    private func keepSnapshot() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(web.state == .live ? 60 : 3))
            if web.state == .live { web.snapshot(into: project.id) }
        }
    }

    /// Is there a picture behind the words (the live page, its last snapshot, or the demo page)?
    private var pictured: Bool {
        guard hasPicture, project.kind == .web else { return false }
        return isDemo || PreviewStore.shared.image(project.id) != nil || previewURL != nil
    }

    /// What sits over the picture: the state in words. A running app needs none, unless it cannot be opened from here.
    @ViewBuilder private var overlay: some View {
        if running, project.kind != .web {
            KindRunningStage(model: model, project: project).padding(Space.s5)
        } else if running {
            if previewURL == nil {
                notice(
                    symbol: "eye.slash", title: "\(project.name) is running",
                    line: "Turn on the public link to see it live here.",
                    button: model.readOnly ? nil : "Turn On Public Link"
                ) { Task { await model.setExpose(project, true) } }
            } else if let why = problem {
                notice(
                    symbol: "exclamationmark.triangle", title: "Could not open \(project.name)", line: why,
                    button: "Try Again"
                ) {
                    web.state = .loading
                    web.web?.reload()
                }
            } else if web.state == .loading, !isDemo {
                corner(Text("Opening \(project.link)…").foregroundStyle(GlassInk.secondary))
            }
        } else if hasPicture, project.kind == .web {
            stageCard
        } else {
            stage.padding(Space.s5)
        }
    }

    /// One state card over the dimmed picture: a plain well, no material.
    private var stageCard: some View {
        ZStack {
            Rectangle().fill(GlassInk.shade(0.4))
            // A failed start is already one card (the notice); a second one around it would be a card in a card.
            if project.run?.state == .failed {
                stage.padding(Space.s5)
            } else {
                stage.padding(Space.s5).coreWell(radius: Radius.cardMac).padding(Space.s5)
            }
        }
    }

    /// With a picture behind it, a note is small and sits in the corner; the page stays visible. Without one it is the card.
    @ViewBuilder
    private func notice(symbol: String, title: String, line text: String, button: String?, action: @escaping () -> Void)
        -> some View
    {
        if pictured {
            corner(
                HStack(spacing: Space.s2) {
                    Image(systemName: symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    Text(text).foregroundStyle(GlassInk.secondary).lineLimit(2)
                    if let button {
                        Button(button, action: action).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    }
                })
        } else {
            note(symbol: symbol, title: title, line: text, button: button, action: action)
        }
    }

    private func corner<V: View>(_ content: V) -> some View {
        content.padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlMd)
            .background(coreShape(Radius.control).fill(.background)).coreWell(radius: Radius.control)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(Space.s2)
    }

    private func note(
        symbol: String, title: String, line text: String, button: String?, action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large, weight: .semibold)
                .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
            line(text)
            if let button {
                Button(button, action: action).buttonStyle(CoreButtonStyle(.secondary)).padding(.top, Space.s1)
            }
        }
        .padding(Space.s5).coreWell(radius: Radius.cardMac)
    }

    /// Honest progress: a bar only when the Core reports services up of the setup's; else a moving bar with the words and how long.
    private var startingStage: some View {
        VStack(spacing: Space.s3) {
            Text("Starting \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            if let p = project.live?.progress {
                CoreMeter(p, label: "Starting \(project.name)").frame(width: Space.s8 * 13)
            } else {
                CoreWorkingBar(width: Space.s8 * 13)
            }
            Text(project.live?.progressLine ?? "Starting…").foregroundStyle(GlassInk.secondary)
            StartStepsList(steps: project.live?.steps ?? [])
        }
    }

    private var stoppedStage: some View {
        let n = project.draft?.services.count ?? 0
        let where_ = project.live?.runner ?? model.coreName
        let kind = project.kind
        return VStack(spacing: Space.s2) {
            Text("\(project.name) is stopped").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            if let why = project.live?.stopWords { line(why) }
            if let at = project.live?.lastActivity {
                line("Last visited \(runsAgo(at, now: model.now())).")
            }
            line(
                kind == .app
                    ? "Build and run it on \(where_)."
                    : kind == .infra
                        ? "Start it to bring up \(n > 0 ? ProjectItem.count(n, "service") : "its services") on \(where_)."
                        : n > 0
                            ? "Start it to run \(ProjectItem.count(n, "service")) on \(where_) and open it at \(project.link)."
                            : "Start it to run it on \(where_) and open it at \(project.link).")
            start().padding(.top, Space.s1)
        }
    }

    private var failedStage: some View {
        VStack(spacing: Space.s4) {
            CoreNotice(
                symbol: "exclamationmark.triangle", title: project.live?.failure ?? "The last start failed.",
                text: project.live?.failureFix ?? "", tone: .fail
            )
            .frame(maxWidth: Space.s8 * 14)
            StartStepsList(steps: project.live?.steps ?? [])
            // Each fix is a button: read why, set what is missing, then try again.
            HStack(spacing: Space.s2) {
                Button {
                    model.section = .run
                } label: {
                    Label("Show Log", systemImage: "text.alignleft")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Open the log of the last run")
                if let secret = project.failedSecret {
                    Button {
                        model.section = .run
                    } label: {
                        Label("Set \(secret)…", systemImage: "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary)).help("Set the secret the setup is missing")
                }
                start()
            }
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 11)
    }
}

/// The Core's start steps in order: done, the one under way, those waiting, and the one that failed with its reason.
struct StartStepsList: View {
    let steps: [StartStep]
    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Image(systemName: symbol(s)).foregroundStyle(tint(s)).frame(width: Space.s4)
                            .breathing(s.state == .active).accessibilityHidden(true)
                        Text(s.title).foregroundStyle(s.state == .pending ? GlassInk.secondary : GlassInk.primary)
                        if let d = s.detail { Text(d).foregroundStyle(GlassInk.secondary).lineLimit(2) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(s.title), \(s.state.rawValue)\(s.detail.map { ", \($0)" } ?? "")")
                }
            }
        }
    }

    private func symbol(_ s: StartStep) -> String {
        switch s.state {
        case .done: "checkmark.square"
        case .active: "square.dotted"
        case .pending: "square"
        case .failed: "xmark.square"
        }
    }

    private func tint(_ s: StartStep) -> Color {
        switch s.state {
        case .done: GlassInk.green
        case .active: GlassInk.primary
        case .pending: GlassInk.secondary
        case .failed: GlassInk.red
        }
    }
}
