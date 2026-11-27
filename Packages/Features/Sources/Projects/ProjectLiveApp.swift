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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(project.link).lineLimit(1)
                Text(note).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: 0)
                CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") { copyLink() }
                CoreIconButton(symbol: "arrow.up.forward.square", label: "Open in the browser") { openLink() }
                    .disabled(!running)
            }
            .padding(.leading, Space.s2)
            if project.stale {
                CoreNotice(
                    symbol: "wifi.exclamationmark", title: "The Core is not answering.",
                    text: "This is how \(project.name) looked when it last did. It will update once the Core is back.",
                    tone: .warn)
            }
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
            case .running: runningStage
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

    private func start(_ title: String) -> some View {
        Button {
            model.control(.start, project)
        } label: {
            Label(title, systemImage: "play")
        }
        .buttonStyle(CoreButtonStyle(.prominent)).disabled(!can)
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
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.readOnly)
            .padding(.top, Space.s1).accessibilityIdentifier("project-add-repos-button")
        }
    }

    /// TODO(P6-02): the running app itself (a web view on the project's address) replaces this card.
    private var runningStage: some View {
        CoreStateCard(
            symbol: "display", title: "\(project.name) is running",
            line: "Its live view opens here once the Core serves \(project.link).")
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
            ForEach(Array((project.live?.steps ?? []).enumerated()), id: \.offset) { _, s in
                Label(s.title, systemImage: s.done ? "checkmark.circle" : "circle").foregroundStyle(
                    s.done ? GlassInk.primary : GlassInk.secondary)
            }
        }
    }

    private var stoppedStage: some View {
        let n = project.draft?.services.count ?? 0
        let where_ = project.live?.runner ?? model.coreName
        return VStack(spacing: Space.s2) {
            Text("\(project.name) is stopped").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            if let why = project.live?.stopWords { line(why) }
            if let at = project.live?.lastActivity {
                line("Last visited \(runsAgo(at, now: model.now())).")
            }
            line(
                n > 0
                    ? "Start it to run \(ProjectItem.count(n, "service")) on \(where_) and open it at \(project.link)."
                    : "Start it to run it on \(where_) and open it at \(project.link).")
            start("Start").padding(.top, Space.s1)
        }
    }

    private var failedStage: some View {
        VStack(spacing: Space.s4) {
            CoreNotice(
                symbol: "exclamationmark.triangle", title: project.live?.failure ?? "The last start failed.",
                text: project.live?.failureFix ?? "", tone: .fail
            )
            .frame(maxWidth: Space.s8 * 14)
            start("Start Again")
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 11)
    }
}
