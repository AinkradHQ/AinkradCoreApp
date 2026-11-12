import BrainImport
import CoreUI
import Shell
import SwiftUI

extension BrainModel {
    /// Opens the Import wizard over the shell. A run already under way is picked up where it stands.
    public func openImport() {
        guard let routes = service?.importRoutes, setup == .ready || setup == .notSetUp else { return }
        if importer == nil || importer?.step == .done {
            importer = ImportModel(host: host, routes: routes, sources: importSources(), resume: .standard())
        }
        guard let importer else { return }
        let shell = host.shell
        shell.present(
            ShellDialog(id: "brain-import", onClose: { [weak self] in self?.host.clearElevationNotice() }) {
                ImportWizard(brain: self, model: importer) { shell.closeDialog() }
            })
    }
}

/// The five steps in one sheet: sources, collect and clean, review rooms, import, done. Closing the sheet leaves the work
/// running in the model; the pane says "Import in progress" until it is done.
struct ImportWizard: View {
    let brain: BrainModel
    let model: ImportModel
    let close: () -> Void

    private static let titles = ["Choose sources", "Collect and clean", "Review rooms", "Import", "Done"]

    var body: some View {
        CoreDialogPanel("Import into the Brain", width: Space.s8 * 26) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Step \(model.step.rawValue + 1) of 5 · \(Self.titles[model.step.rawValue])")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .accessibilityIdentifier("brain-import-step")
                switch model.step {
                case .sources: SourcesStep(model: model, close: close)
                case .collecting: CollectStep(model: model, close: close)
                case .review: ReviewStep(model: model, close: close)
                case .importing: ImportingStep(model: model)
                case .done: DoneStep(brain: brain, model: model, close: close)
                }
            }
        }
        .accessibilityIdentifier("brain-import")
    }
}

private struct SourcesStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Choose what to collect. Nothing is kept in the Brain until you press Import accepted rooms.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach($m.choices) { $c in
                    CoreCheckbox(c.title, detail: detail(c), isOn: $c.on)
                }
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            Text(
                "Coming later: Codex, OpenCode, Antigravity, Cursor, Kimi, project docs and your vault. "
                    + "Passwords, keys, certificates and contracts are never read, and refused projects are skipped."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel, run: close),
                primary: CoreAction("Start", key: .primary) { model.start() }, enabled: model.canStart)
        }
        .task { await model.scan() }
    }

    private func detail(_ c: ImportModel.Choice) -> String {
        guard let found = c.found else { return "Looking…" }
        let skipped = ImportWords.skips(c.skipped)
        return "\(found) found" + (skipped.isEmpty ? "" : ", skipped by rule: \(skipped)")
    }
}

private struct CollectStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreMeter(model.fraction, label: "Import progress")
            Text(model.statusLine).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("brain-import-status")
            if let why = model.failure {
                CoreNotice(symbol: "exclamationmark.circle", title: why, tone: .fail) {
                    Button("Try again") { model.retry() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            Text("You can close this and keep working. The Brain pane shows the import is in progress.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            CoreDialogFooter(
                cancel: CoreAction("Run in background", key: .cancel, run: close), primary: nil)
        }
    }
}

private struct ImportingStep: View {
    let model: ImportModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Writing the accepted rooms. Touch ID confirms it first.").foregroundStyle(GlassInk.secondary)
            ForEach(model.review.accepted) { c in
                HStack {
                    Text(c.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    Spacer()
                    Text("\(c.itemCount) items").foregroundStyle(GlassInk.secondary)
                }
                .padding(Space.s3).coreWell()
            }
        }
    }
}

private struct DoneStep: View {
    let brain: BrainModel
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let r = model.result
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(summary(r)).fixedSize(horizontal: false, vertical: true)
            ForEach(r?.rooms ?? []) { room in
                HStack {
                    Text(room.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    BrainChip(ReviewWords.kind(room.kind), GlassInk.slate)
                    Spacer()
                    Text("\(room.sources) sources stored").foregroundStyle(GlassInk.secondary)
                }
                .padding(Space.s3).coreWell()
            }
            ForEach(model.heldCards()) { c in
                HStack {
                    Text(c.name).coreFont(size: MacTextSize.body, weight: .semibold)
                    Spacer()
                    Text(ReviewWords.held).foregroundStyle(GlassInk.secondary)
                }
                .padding(Space.s3).coreWell()
            }
            Text("The Inbox, where distilled memories wait for you, comes later.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            CoreDialogFooter(
                cancel: nil,
                primary: CoreAction("Open the Brain", key: .primary) {
                    brain.retry()
                    brain.show(.rooms)
                    close()
                })
        }
        .accessibilityIdentifier("brain-import-done")
    }

    private func summary(_ r: CommitResult?) -> String {
        guard let r else { return "Done." }
        let made = r.rooms.count
        var s = made == 1 ? "1 room was imported." : "\(made) rooms were imported."
        if !r.held.isEmpty { s += " \(r.held.count) wait for the room backup." }
        return s
    }
}
