import CoreUI
import SwiftUI

/// Copy, read, draft, room: where a new project stands. The Core copies the repos; drafting arrives with the run engine,
/// so while it is the step in progress the project stays here.
struct SettingUp: View {
    let project: ProjectItem
    private enum Step { case done, active, failed, waiting }

    private var steps: [(String, Step)] {
        let failed = project.repos.contains { $0.fetchError != nil }
        let copied = project.repos.allSatisfy { $0.fetchedAt != nil }
        let copy: Step = failed ? .failed : copied ? .done : .active
        return [
            ("Copy \(ProjectItem.count(project.repos.count, "repo")) to the Core", copy),
            ("Read the repos", copy == .done ? .done : .waiting),
            ("Draft the run from the repos", copy == .done ? .active : .waiting),
            ("Create the Brain room “\(project.name)”", .waiting),
        ]
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            Text("Setting up \(project.name)").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.0) { badge(s.1) }
                        .coreCard(s.1 == .active ? GlassInk.wellHover : .clear, radius: Radius.row)
                }
            }
            .frame(width: Space.s8 * 13)
            if let e = project.repos.compactMap(\.fetchError).first {
                Text(e).foregroundStyle(GlassInk.redInk).multilineTextAlignment(.center)
                    .frame(maxWidth: Space.s8 * 13)
            }
        }
    }

    private func badge(_ s: Step) -> StateBadge {
        switch s {
        case .done: StateBadge("Done", tone: .done, symbol: "checkmark.circle")
        case .active: StateBadge("In progress", tone: .warn, symbol: "gearshape")
        case .failed: StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
        case .waiting: StateBadge("Waiting", tone: .queue, symbol: "clock")
        }
    }
}

/// The copies are ready and the Core has no run setup: draft one from the repo, or write it by hand.
struct NeedsSetup: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var run: RunPageModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _run = State(initialValue: RunPageModel(model: model, projectID: project.id))
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            Text("\(project.name) has no setup yet").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text(
                "The Core can draft how to run it from a compose file, run.sh, Makefile or package.json in the primary repo. Nothing is run to do it."
            )
            .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 14)
            Button {
                RunDialogs.openSetup(run, project: project)
            } label: {
                Label("Set Up…", systemImage: "wand.and.stars")
            }
            .buttonStyle(CoreButtonStyle(.prominent)).disabled(model.readOnly)
            .help("Draft the setup from the repo, or write it by hand")
        }
        .task { await run.load() }
    }
}

/// "Ready to start": the setup the Core holds in one line (See Changes, Undo) and what is still missing. Start waits for the secrets.
struct ReadyToStart: View {
    let model: ProjectsModel
    let project: ProjectItem
    let draft: RunDraft
    @State private var run: RunPageModel

    init(model: ProjectsModel, project: ProjectItem, draft: RunDraft) {
        self.model = model
        self.project = project
        self.draft = draft
        _run = State(initialValue: RunPageModel(model: model, projectID: project.id))
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            Text("\(project.name) is ready to start").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "sparkle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(summary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s1) {
                        Button("See Changes") { RunDialogs.openChanges(run) }
                            .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(run.spec == nil)
                        if !draft.manual {
                            Button("Undo") { Task { await run.undoDraft(project.name) } }
                                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                                .disabled(run.previous == nil || run.busy || model.readOnly)
                                .help(
                                    run.previous.map { "Go back to version \($0.version), the setup before this draft" }
                                        ?? "This is the first version, so nothing came before it. Edit the setup in Runs."
                                )
                        }
                    }
                }
            }
            .padding(Space.s3).frame(maxWidth: Space.s8 * 14, alignment: .leading)
            .coreCard(GlassInk.well, radius: Radius.cardMac)
            if !draft.secrets.isEmpty {
                Text(secretsLine).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.s8 * 14)
            }
            HStack(spacing: Space.s2) {
                if !draft.secrets.isEmpty {
                    Button {
                        RunDialogs.openSecret(run, project: project, name: draft.secrets.first, replacing: false)
                    } label: {
                        Label("Set Secrets…", systemImage: "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary)).disabled(model.readOnly)
                    .help("Set \(draft.secrets.first ?? "") first; the others follow")
                }
                Button {
                    model.control(.start, project)
                } label: {
                    Label("Start", systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .disabled(!model.canControl(project) || project.startBlock != nil)
                .help(project.startBlock ?? "Start \(project.name)")
            }
        }
        .task { await run.load() }
    }

    private var summary: AttributedString {
        var a = AttributedString(draft.manual ? "Run set up by hand: " : "Run drafted from ")
        if !draft.manual {
            var f = AttributedString(draft.source)
            f.font = .system(size: MacTextSize.body, design: .monospaced)
            a += f
            a += AttributedString(": ")
        }
        a += AttributedString(
            "\(ProjectItem.count(draft.services.count, "service")) (\(draft.services.joined(separator: ", "))).")
        return a
    }

    private var secretsLine: AttributedString {
        var a = AttributedString(
            "\(ProjectItem.count(draft.secrets.count, "secret")) still to set before the first start: ")
        for (i, s) in draft.secrets.enumerated() {
            var n = AttributedString(s)
            n.font = .system(size: MacTextSize.body, design: .monospaced)
            a += n
            a += AttributedString(i < draft.secrets.count - 1 ? ", " : ".")
        }
        return a
    }
}
