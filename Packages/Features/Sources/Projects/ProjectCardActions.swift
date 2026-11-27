import CoreUI
import SwiftUI

/// The buttons on a card's thumbnail while it is hovered: Start or Stop (or Unarchive), and Open.
struct CardHoverActions: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        HStack(spacing: Space.s2) {
            if project.archived {
                Button {
                    Task { await model.unarchive(project) }
                } label: {
                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
                .help(
                    model.readOnly
                        ? "This device can look at projects but not change them." : "Bring it back to the list")
            } else {
                let running = model.isRunningOrStarting(project)
                let block =
                    running
                    ? (model.readOnly ? "This device can look at projects but not change them." : nil)
                    : model.startBlock(project)
                Button {
                    model.toggleRun(project)
                } label: {
                    Label(running ? "Stop" : "Start", systemImage: running ? "stop" : "play")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(
                    block != nil || model.controlling.contains(project.id)
                )
                .help(block ?? (running ? "Stop \(project.name)" : "Start \(project.name)"))
            }
            Button {
                model.openProject(project.id)
            } label: {
                Label("Open", systemImage: "arrow.right")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
    }
}

/// A card's context menu: Open, Start or Stop, Copy link, Settings, Archive or Unarchive.
struct CardMenu: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        Button("Open") { model.openProject(project.id) }
        if project.archived {
            Button("Unarchive") { Task { await model.unarchive(project) } }.disabled(model.readOnly)
        } else {
            let running = model.isRunningOrStarting(project)
            Button(running ? "Stop" : "Start") { model.toggleRun(project) }
                .disabled(running ? model.readOnly : model.startBlock(project) != nil)
            if project.copyFailed, let r = project.repos.first(where: { $0.copy.isFailed }) {
                Button("Try copying again") { model.fetchRepo(project, r) }.disabled(model.readOnly)
            }
        }
        Divider()
        Button("Copy link") { model.copyLink(project) }
        Button("Settings") { model.openProject(project.id, section: .settings) }
        if !project.archived {
            Divider()
            Button("Archive…", role: .destructive) { model.requestArchive(project) }.disabled(model.readOnly)
        }
    }
}
