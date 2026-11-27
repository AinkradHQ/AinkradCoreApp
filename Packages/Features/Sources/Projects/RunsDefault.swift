import CoreUI
import SwiftUI

/// The Default of the Runs page: the project's own setup (the run spec) as the first configuration. The header Start runs the
/// same thing; here it has its services, its history of versions and Edit Setup. The Core lays no environment over it (only a
/// configuration gets variables), which the note says in one line.
struct DefaultDetail: View {
    let runs: RunConfigsModel
    let project: ProjectItem

    private var setup: RunPageModel { runs.setup }
    private var live: RunRecord? { runs.defaultRun }

    var body: some View {
        Island(
            title: RunConfigsModel.defaultName, sub: "this project's setup",
            accessory: {
                Button("History…") { RunDialogs.openHistory(setup, project: project) }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .disabled(setup.versions.count < 2)
                    .help(
                        setup.versions.count < 2
                            ? "There is one version of the setup so far" : "Every saved version of the setup")
                Button("Edit Setup…") { RunDialogs.openSetup(setup, project: project) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(runs.model.readOnly || !setup.loaded || setup.loadError != nil)
                    .help("Change what this project runs")
                    .accessibilityIdentifier("project-edit-setup")
                if let live {
                    Button {
                        Task { await runs.startDefault(project) }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!enabled)
                    Button {
                        Task { await runs.stop(live, project: project) }
                    } label: {
                        Label("Stop", systemImage: "power")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!enabled)
                } else {
                    Button {
                        Task { await runs.startDefault(project) }
                    } label: {
                        Label("Start", systemImage: "play")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small, busy: runs.model.controlling.contains(project.id)))
                    .disabled(!enabled || setup.spec == nil)
                    .help(setup.spec == nil ? "There is no setup to run yet. Add repos first." : "Start \(project.name)")
                    .accessibilityIdentifier("project-start-default")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let s = setup.status, s.state == "failed" {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: "The last start failed.",
                        text: s.error ?? ProjectsModel.reason(s.stopReason), tone: .fail)
                }
                if setup.drafted, let spec = setup.spec { DraftLine(project: project, run: setup, spec: spec) }
                SetupContent(project: project, run: setup, showLogs: { _ in runs.tab = .live })
                note
            }
        }
    }

    private var enabled: Bool { !runs.model.readOnly && runs.model.canControl(project) }

    private var note: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Image(systemName: "info.circle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            Text("Starts the setup as saved. Variables belong to configurations; the secrets it uses are in Environment.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Secrets") { runs.tab = .environment }.buttonStyle(CoreButtonStyle(.plain, size: .small))
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
    }
}
