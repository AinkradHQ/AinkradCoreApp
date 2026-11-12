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
        CoreDialogPanel("Rename \(runner.name)", width: Space.s8 * 12) {
            CoreTextField(
                "Name", placeholder: "1 to 64 characters", text: $name, error: error, autofocus: true, onSubmit: save)
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.shell.closeDialog() },
                primary: CoreAction("Rename", key: .primary, run: save),
                busy: busy, enabled: valid && clean != runner.name)
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

/// Revoke a runner (n18-n19 revoke): what stops, that it must pair again, the runner in a well, and Touch ID on the
/// button. The red button has no Return key, so Return is never a trap.
struct RevokeRunnerDialog: View {
    let model: TerminalsModel
    let runner: RunnerItem
    let agents: Int
    let terminals: Int
    @State private var error: String?
    @State private var busy = false
    @Environment(\.corePalette) private var palette

    private var lead: AttributedString {
        var stops = AttributedString(RunnerFacts.stops(agents: agents, terminals: terminals))
        stops.inlinePresentationIntent = .stronglyEmphasized
        stops.foregroundColor = palette.text
        return AttributedString("Work running on \(runner.name) stops: ") + stops
            + AttributedString(". The runner must pair again to come back.")
    }

    var body: some View {
        CoreDialogPanel("Revoke \(runner.name)?", width: Space.s8 * 15) {
            Text(lead).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s3) {
                IconTile(
                    model.host.thisMacRunnerID == runner.id ? "laptopcomputer" : "server.rack", hue: GlassInk.slate,
                    size: Space.s8 - Space.s1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(runner.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(TerminalsModel.spec(runner)).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).coreWell(radius: Radius.control)
            if let n = model.host.elevationNotice { ElevationBanner(notice: n) }
            if let error { CoreFieldError(error) }
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.shell.closeDialog() },
                primary: CoreAction("Revoke with Touch ID", run: revoke), danger: true, busy: busy)
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
