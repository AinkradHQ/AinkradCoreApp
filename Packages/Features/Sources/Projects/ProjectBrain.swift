import Brain
import CoreUI
import SwiftUI

/// The Brain page: the project's room as a summary, the state of its instructions for AI sessions, and its rules by group.
/// It only reads the Brain app's own overview (`RoomOverview`) and opens the Brain for anything else; no Brain logic here.
///
/// TODO(P1-03): the project's `room` id. The synced client has none, so a real project has no room to read (`live` is nil)
/// and the page says so; Rewrite and Edit… need that id to call the Brain's write and instructions routes, so they stay off.
struct BrainPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var settled = false

    private var room: ProjectLive.Room? { project.live?.room }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            if let room {
                summary(room).coreRise(settled, 0).frame(width: Space.s8 * 18)
                rules(room).coreRise(settled, 1)
            } else {
                Island("\(project.name) room") {
                    Text(
                        "New room, nothing in it yet. It fills from the repos’ instruction files, AI sessions and docs you add."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { settled = true }
        .accessibilityIdentifier("project-page-Brain")
    }

    private func summary(_ room: ProjectLive.Room) -> some View {
        Island(
            title: "Summary", sub: "\(project.name) room · updated \(room.updated)",
            accessory: {
                Button("Open Room") { model.host.shell.launcher.entry("brain")?.run() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Rewrite") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(true)
                    .help("Rewriting from here arrives with the project’s room link")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(room.summary).fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
                    if let stack = room.overview.overview?.facts.stack {
                        GridRow {
                            Text("Stack").foregroundStyle(GlassInk.secondary)
                            Text(stack)
                        }
                    }
                    GridRow {
                        Text("Items").foregroundStyle(GlassInk.secondary)
                        Text(room.items.formatted())
                    }
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Instructions for AI sessions").coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary)
                    HStack(spacing: Space.s2) {
                        if room.instructionsInUse {
                            StateBadge("In use · approved \(room.approved)", tone: .done, symbol: "checkmark.circle")
                        } else {
                            StateBadge("Not approved yet", tone: .warn, symbol: "clock")
                        }
                        Spacer(minLength: 0)
                        Button("Edit…") {}.buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(true)
                            .help("Editing from here arrives with the project’s room link")
                    }
                }
            }
        }
    }

    private func rules(_ room: ProjectLive.Room) -> some View {
        let r = room.overview.overview?.rules ?? OverviewRules()
        let groups = [("Workflow", r.workflow), ("Code", r.code), ("Design", r.design), ("Never do", r.never)]
            .filter { !$0.1.isEmpty }
        return Island("Rules", sub: "\(room.rules) · from \(room.items.formatted()) items") {
            VStack(alignment: .leading, spacing: Space.s4) {
                if groups.isEmpty {
                    Text("No rules yet.").foregroundStyle(GlassInk.secondary)
                }
                ForEach(groups, id: \.0) { g in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(g.0).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(
                            GlassInk.secondary)
                        ForEach(g.1) { rule in
                            Text(rule.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
