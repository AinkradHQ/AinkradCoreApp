import CoreUI
import SwiftUI

/// Rename a runner: one field, Return saves. The Core keeps the name on the runner's device.
struct RenameRunnerDialog: View {
    let model: TerminalsModel
    let runner: RunnerItem
    @State private var name: String
    @State private var error: String?
    @State private var busy = false

    init(model: TerminalsModel, runner: RunnerItem) {
        self.model = model
        self.runner = runner
        _name = State(initialValue: runner.name)
    }

    private var clean: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !clean.isEmpty && clean.count <= 64 }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 11) {
            Text("Rename \(runner.name)").coreFont(size: MacTextSize.large + 2, weight: .bold)
                .accessibilityAddTraits(.isHeader)
            Text("A name of 1 to 64 characters. It shows in the Runners list and where you pick a machine.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(GlassInk.amberInk)
                    .coreFont(size: MacTextSize.meta)
            }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                Button("Rename", action: save)
                    .buttonStyle(CoreButtonStyle(.prominent)).disabled(!valid || busy || clean == runner.name)
            }
        }
    }

    private func save() {
        guard valid, !busy, clean != runner.name else { return }
        busy = true
        Task {
            let why = await model.renameRunner(runner.id, to: clean)
            busy = false
            if let why { error = why } else { model.shell.closeDialog() }
        }
    }
}

/// Revoke a runner: what stops, that it must pair again, and Touch ID on the button.
struct RevokeRunnerDialog: View {
    let model: TerminalsModel
    let runner: RunnerItem
    let agents: Int
    let terminals: Int
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 13) {
            Text("Revoke \(runner.name)?").coreFont(size: MacTextSize.large + 2, weight: .bold)
                .accessibilityAddTraits(.isHeader)
            Text(
                "Work running on \(runner.name) stops: \(RunnerFacts.stops(agents: agents, terminals: terminals)). The runner must pair again to come back. Revoking cannot be undone."
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s3) {
                Image(systemName: "server.rack").foregroundStyle(GlassInk.blue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(runner.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(TerminalsModel.spec(runner)).coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.control + 2))
            if let n = model.host.elevationNotice { ElevationBanner(notice: n) }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(GlassInk.amberInk)
                    .coreFont(size: MacTextSize.meta)
            }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.shell.closeDialog() }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                Spacer(minLength: Space.s2)
                // Destructive confirms are secondary, never prominent, so Return is not a trap.
                Button {
                    revoke()
                } label: {
                    Label("Revoke with Touch ID", systemImage: "touchid")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(busy)
            }
        }
    }

    private func revoke() {
        busy = true
        Task {
            let why = await model.revokeRunner(runner.id)
            busy = false
            if let why { error = why } else { model.shell.closeDialog() }
        }
    }
}
