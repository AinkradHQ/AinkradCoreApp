import CoreUI
import SwiftUI

/// The buttons on a card's thumbnail while it is hovered: Start or Stop (Unarchive on an archived one, Open Brain on a project
/// that is not software, the fix on one whose copy failed), and Open.
struct CardHoverActions: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        HStack(spacing: Space.s2) {
            main
            Button {
                model.openProject(project.id)
            } label: {
                Label("Open", systemImage: "arrow.right")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
    }

    @ViewBuilder private var main: some View {
        if project.archived {
            Button {
                Task { await model.unarchive(project) }
            } label: {
                Label("Unarchive", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
            .help(
                model.readOnly ? "This device can look at projects but not change them." : "Bring it back to the list")
        } else if !project.kind.runs {
            Button {
                model.openProject(project.id, section: .brain)
            } label: {
                Label("Open Brain", systemImage: "brain")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .help("Its notes and AI sessions live in the Brain")
        } else if project.copyFailed {
            let connect = model.copyNeedsConnection(project)
            Button {
                if connect { model.connectGithub() } else { model.retryCopies(project) }
            } label: {
                Label(
                    connect ? "Connect GitHub" : "Try copying again",
                    systemImage: connect ? "link" : "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly && !connect)
            .help(connect ? "GitHub has to be connected before the repos can be copied" : "Copy every repo again")
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
    }
}

/// A card's context menu: Open (also in a pane of its own), Start or Stop, Brain, Rename, kind, Copy link, Settings, Archive.
struct CardMenu: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        Button("Open") { model.openProject(project.id) }
        Button("Open in New Pane") { model.openInOwnPane(project) }
        if project.archived {
            Button("Unarchive") { Task { await model.unarchive(project) } }.disabled(model.readOnly)
        } else {
            if project.kind.runs {
                let running = model.isRunningOrStarting(project)
                Button(running ? "Stop" : "Start") { model.toggleRun(project) }
                    .disabled(running ? model.readOnly : model.startBlock(project) != nil)
            }
            if project.copyFailed {
                if model.copyNeedsConnection(project) {
                    Button("Connect GitHub") { model.connectGithub() }
                }
                Button("Try copying again") { model.retryCopies(project) }.disabled(model.readOnly)
            }
        }
        Button("Show in Brain") { model.openProject(project.id, section: .brain) }
        Divider()
        // The name is edited in the project's Settings.
        Button("Rename…") { model.openProject(project.id, section: .settings) }.disabled(model.readOnly)
        Menu("Change kind") {
            ForEach(ProjectKind.allCases) { k in
                Button {
                    model.setKind(k, for: project)
                } label: {
                    Label(k.short, systemImage: k == project.kind ? "checkmark" : k.symbol)
                }
            }
        }
        .disabled(model.readOnly || project.archived)
        if model.canCopyLink(project) { Button("Copy link") { model.copyLink(project) } }
        Button("Settings") { model.openProject(project.id, section: .settings) }
        if !project.archived {
            Divider()
            Button("Archive…", role: .destructive) { model.requestArchive(project) }.disabled(model.readOnly)
        }
    }
}
