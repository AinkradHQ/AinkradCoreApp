import BrainImport
import CoreUI
import Shell
import SwiftUI

extension BrainModel {
    /// Opens the Import wizard over the shell. A run already under way is picked up where it stands.
    /// A run waiting for review (from a sync) opens the wizard on its review step.
    public func openReview(_ run: String) async {
        guard let routes = service?.importRoutes else { return }
        if importer == nil || importer?.step == .done {
            importer = ImportModel(
                host: host, routes: routes, sources: importSources(),
                resume: service?.isSample == true ? nil : .standard())
            importer?.service = service
        }
        guard let importer, await importer.reviewExisting(run) else {
            sync?.notice = "Finish the import in progress first."
            return
        }
        openImport()
    }

    /// `brain.inbox`: one notice, then the lists refresh.
    public func inboxNotice(unsorted: Int, newRooms: Int) {
        var parts: [String] = []
        if newRooms > 0 { parts.append(BrainWords.plural(newRooms, "new room", "new rooms")) }
        if unsorted > 0 { parts.append("\(unsorted) unsorted") }
        host.shell.showToast(
            "New AI sessions are waiting for review" + (parts.isEmpty ? "." : ": \(parts.joined(separator: ", "))."))
        Task { await sync?.reload() }
    }

    public func openImport() {
        guard let routes = service?.importRoutes, setup == .ready || setup == .notSetUp else { return }
        if importer == nil || importer?.step == .done {
            importer = ImportModel(
                host: host, routes: routes, sources: importSources(),
                resume: service?.isSample == true ? nil : .standard())
            importer?.service = service
        }
        guard let importer else { return }
        let shell = host.shell
        shell.present(
            ShellDialog(id: "brain-import", onClose: { [weak self] in self?.host.clearElevationNotice() }) {
                ImportWizard(brain: self, model: importer) { shell.closeDialog() }
            })
    }
}

/// The five steps in one sheet: sources, collect, review rooms, import, done. Closing the sheet leaves the work running in
/// the model; the pane says "Import in progress" until it is done.
struct ImportWizard: View {
    let brain: BrainModel
    let model: ImportModel
    let close: () -> Void

    static let steps = ["Sources", "Collect", "Review", "Import", "Done"]

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .center, spacing: Space.s4) {
                    Text("Import into the Brain").coreFont(size: MacTextSize.title + 2, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.s3)
                    StepTrack(Self.steps, at: model.step.rawValue, hue: GlassInk.blue)
                        .accessibilityIdentifier("brain-import-step")
                }
                Group {
                    switch model.step {
                    case .sources: SourcesStep(model: model, close: close)
                    case .collecting: CollectStep(model: model, close: close)
                    case .review: ReviewStep(model: model, close: close)
                    case .importing: ImportingStep(model: model)
                    case .done: DoneStep(brain: brain, model: model, close: close)
                    }
                }
                .transition(.opacity)
            }
            .animation(Motion.out(Motion.ui), value: model.step)
        }
        .accessibilityIdentifier("brain-import")
    }
}

/// A footer with a quiet summary just left of the main action. Esc runs the way back, Return the main action.
struct WizardFooter: View {
    var back: (title: String, run: () -> Void)?
    var note = ""
    let primary: (title: String, run: () -> Void)
    var enabled = true

    var body: some View {
        HStack(spacing: Space.s3) {
            if let back {
                Button(back.title, action: back.run).buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            }
            Spacer(minLength: Space.s3)
            if !note.isEmpty {
                Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
            Button(primary.title, action: primary.run).buttonStyle(CoreButtonStyle(.prominent))
                .coreShortcut(.primary).disabled(!enabled)
        }
    }
}

private struct SourcesStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach([SyncWords.sessionsGroup, SyncWords.notesGroup], id: \.self) { g in
                    Text(g).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                        .padding(.horizontal, Space.s3).padding(.top, Space.s2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach($m.choices) { $c in
                        if SyncWords.group(c.id) == g { row($c) }
                    }
                }
            }
            Text("Passwords, keys and contracts are never read, and refused projects are skipped.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s3)
            WizardFooter(
                back: ("Cancel", close), note: summary, primary: ("Start", { model.start() }), enabled: model.canStart)
        }
        .task { await model.scan() }
    }

    private func row(_ c: Binding<ImportModel.Choice>) -> some View {
        let v = c.wrappedValue
        return HStack(spacing: Space.s3) {
            CoreCheckbox(v.title, isOn: c.on).disabled(v.notReadable != nil)
            Spacer(minLength: Space.s3)
            trailing(v)
        }
        .padding(.horizontal, Space.s3)
        .frame(minHeight: Space.s8 + Space.s2)
        .help(v.notReadable ?? "")
    }

    @ViewBuilder private func trailing(_ c: ImportModel.Choice) -> some View {
        if c.notReadable != nil {
            if c.absent {
                Text("Nothing on this Mac").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else {
                StateBadge("Not readable", tone: .queue, symbol: "eye.slash")
            }
        } else if let found = c.found {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(found.formatted()) found").monospacedDigit()
                let skipped = c.skipped.values.reduce(0, +)
                if skipped > 0 {
                    Text("\(skipped.formatted()) skipped by rule").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).help(ImportWords.skips(c.skipped))
                }
            }
        } else {
            Text("Looking…").foregroundStyle(GlassInk.secondary)
        }
    }

    private var summary: String {
        let chosen = model.chosen
        guard !chosen.isEmpty else { return "" }
        let items = chosen.compactMap(\.found).reduce(0, +)
        return "\(BrainWords.plural(chosen.count, "source", "sources")) · \(BrainWords.plural(items, "item", "items"))"
    }
}

private struct CollectStep: View {
    let model: ImportModel
    let close: () -> Void

    var body: some View {
        let total = model.itemsDone
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreMeter(
                model.phase == .discovering ? 1 : total.total == 0 ? 0 : Double(total.done) / Double(total.total),
                label: "Import progress")
            HStack(alignment: .firstTextBaseline) {
                Text(model.phase == .discovering ? "Sorting into rooms" : "Reading your sessions")
                    .coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: Space.s3)
                Text("\(total.done.formatted()) of \(total.total.formatted())").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
            .help(model.statusLine)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("brain-import-status")
            Grid(alignment: .leading, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
                ForEach(model.sourceRows) { r in
                    GridRow {
                        Text(r.title).lineLimit(2).frame(width: Space.s8 * 5, alignment: .leading)
                        CoreMeter(r.fraction, label: "\(r.title) progress")
                        Text(status(r)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                            .monospacedDigit().frame(width: Space.s8 * 3, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            if let why = model.failure {
                CoreNotice(symbol: "exclamationmark.triangle", title: why, tone: .fail) {
                    Button("Try again") { model.retry() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
            HStack(spacing: Space.s3) {
                Text("You can close this. The Brain pane shows the import.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s3)
                Button("Run in background", action: close).buttonStyle(CoreButtonStyle(.secondary))
                    .coreShortcut(.cancel)
            }
        }
    }

    private func status(_ r: ImportModel.SourceRow) -> String {
        switch r.state {
        case .done: "Done · \(r.total.formatted())"
        case .reading: "\(r.done.formatted()) of \(r.total.formatted())"
        case .waiting: "\(r.total.formatted()) waiting"
        }
    }
}

private struct ImportingStep: View {
    let model: ImportModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Touch ID confirms the import.").foregroundStyle(GlassInk.secondary)
            VStack(spacing: 2) {
                ForEach(model.review.accepted) { c in
                    CoreRow(c.name, subtitle: BrainWords.plural(c.itemCount, "item", "items"), symbol: "folder") {
                        CoreBusyBar().frame(width: Space.s8 * 2).accessibilityHidden(true)
                    }
                }
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
            Text(summary(r)).coreFont(size: MacTextSize.headline, weight: .semibold)
            VStack(spacing: 2) {
                ForEach(r?.rooms ?? []) { room in
                    CoreRow(
                        room.name,
                        subtitle:
                            "\(ReviewWords.kind(room.kind)) · \(BrainWords.plural(room.sources, "item", "items"))",
                        symbol: "folder")
                }
                ForEach(model.heldCards()) { c in
                    CoreRow(c.name, subtitle: ReviewWords.held, symbol: "folder") {
                        StateBadge("Held", tone: .queue, symbol: "clock")
                    }
                }
            }
            WizardFooter(
                primary: (
                    "Open the Brain",
                    {
                        brain.retry()
                        brain.show(.rooms)
                        close()
                    }
                ))
        }
        .accessibilityIdentifier("brain-import-done")
    }

    private func summary(_ r: CommitResult?) -> String {
        guard let r else { return "Done" }
        var s = BrainWords.plural(r.rooms.count, "room", "rooms") + " imported"
        if !r.held.isEmpty { s += ", \(r.held.count) held for the room backup" }
        return s
    }
}
