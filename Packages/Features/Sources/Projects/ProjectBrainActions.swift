import Admin
import CoreUI
import Shell
import SwiftUI

/// Rewrite and Edit… on the Brain page: the Brain's own routes (`/rooms/{room}/overview/write`, `…/instructions`), reached with
/// the room the project is linked to.
extension ProjectsModel {
    /// Asks the Brain to write the room's overview again. The page shows the new one when it is ready.
    func rewriteRoom(_ project: ProjectItem) async {
        guard let room = liveParts[project.id]?.roomID ?? project.live?.roomID, let ins = insightsService else {
            host.shell.showToast("The Brain is not reachable from here.", kind: .warn)
            return
        }
        guard mayWrite() else { return }
        do {
            try await host.elevated("Rewrite the summary of the \(project.name) room.", done: "asked", keepsEdit: false)
            {
                try await ins.writeOverview(room: room)
            }
            host.shell.showToast("Rewriting the summary. It appears here when it is ready.")
            await refreshLive(project.id)
        } catch is AdminDeclined {
        } catch {
            host.shell.showToast(runWords(error), kind: .warn)
        }
    }

    /// Saves the instructions AI sessions read, approved or not.
    func saveInstructions(_ project: ProjectItem, text: String, approved: Bool) async -> String? {
        guard let room = liveParts[project.id]?.roomID ?? project.live?.roomID, let ins = insightsService else {
            return "The Brain is not reachable from here."
        }
        guard mayWrite() else { return "Not now." }
        do {
            try await host.elevated(
                "Save the instructions of the \(project.name) room.", done: "saved", keepsEdit: true
            ) { try await ins.setInstructions(room: room, text: text, approved: approved) }
        } catch is AdminDeclined {
            return ""
        } catch {
            return (error as? RunFailure)?.sentence ?? runWords(error)
        }
        host.shell.showToast(approved ? "Instructions saved and approved" : "Instructions saved")
        await refreshLive(project.id)
        return nil
    }

    func openInstructions(_ project: ProjectItem) {
        guard let room = project.live?.room else { return }
        let shell = host.shell
        shell.present(
            ShellDialog(id: "project-instructions") {
                InstructionsSheet(model: self, project: project, room: room) { shell.closeDialog() }
            })
    }
}

/// Edit…: the instructions AI sessions read in this project, and whether they are approved to be used.
struct InstructionsSheet: View {
    let model: ProjectsModel
    let project: ProjectItem
    let close: () -> Void
    @State private var text: String
    @State private var approved: Bool
    @State private var error: String?
    @State private var busy = false

    init(model: ProjectsModel, project: ProjectItem, room: ProjectLive.Room, close: @escaping () -> Void) {
        self.model = model
        self.project = project
        self.close = close
        _text = State(initialValue: room.overview.instructions ?? room.overview.overview?.instructions ?? "")
        _approved = State(initialValue: room.instructionsInUse)
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Instructions for AI Sessions",
                    line: "AI sessions in \(project.name) read these once they are approved.")
                CoreTextArea(
                    nil, placeholder: "How AI sessions should work in this project", text: $text, error: error,
                    minHeight: Space.s8 * 6, maxHeight: Space.s8 * 12, autofocus: true)
                CoreCheckbox("Approved: AI sessions use these", isOn: $approved)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Save", key: .command, run: save), busy: busy, enabled: !busy)
            }
        }
        .onChange(of: text) { _, _ in error = nil }
        .accessibilityIdentifier("project-instructions")
    }

    private func save() {
        guard !busy else { return }
        busy = true
        Task {
            let why = await model.saveInstructions(project, text: text, approved: approved)
            busy = false
            if why == nil { close() } else if let why, !why.isEmpty { error = why }
        }
    }
}
