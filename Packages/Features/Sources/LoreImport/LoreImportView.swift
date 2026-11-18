import CoreKit
import CoreUI
import SwiftUI

/// One dialog for the whole import: the chooser, the repo form, the review, the progress, the result and the history. The
/// model's phase decides which one shows; the panel stays, so nothing flashes between steps.
struct LoreImportView: View {
    @Bindable var model: LoreImportModel
    @Environment(\.corePalette) private var palette

    static let width = Space.s8 * 18
    static let listHeight = Space.s8 * 8

    var body: some View {
        CoreDialogPanel(title, width: Self.width) {
            switch model.phase {
            case .chooser: chooser
            case .repoSetup: repoSetup
            case .working(let text, let progress): working(text, progress)
            case .review: LoreImportReview(model: model)
            case .done: done
            case .undone: undone
            case .failed(let why): failed(why)
            case .history: history
            case .needsPermission: needsPermission
            }
        }
        .accessibilityIdentifier("lore-import")
    }

    private var title: String {
        switch model.phase {
        case .chooser: "Import Notes"
        case .repoSetup: "Import from Repo"
        case .working: "Importing"
        case .review: "Review Import"
        case .done: "Imported"
        case .undone: "Import Undone"
        case .failed: "Unable to Import"
        case .history: "Earlier Imports"
        case .needsPermission: "Apple Notes"
        }
    }

    // MARK: chooser

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreRow(
                "Import from Repo…", subtitle: "Read the Docs folder of a project's repo",
                symbol: "arrow.triangle.branch",
                action: { model.phase = .repoSetup }
            )
            .help("Bring in the Markdown files under Docs/ of a project's repo")
            CoreRow(
                "Import Files…", subtitle: "Markdown files, or a zip of them", symbol: "doc.badge.plus",
                action: { model.chooseFiles() }
            )
            .help("Choose .md files or a .zip on this Mac")
            CoreRow(
                "Import Apple Notes…", subtitle: "Read your notes on this Mac", symbol: "note.text",
                action: { model.importAppleNotes() }
            )
            .help("Asks macOS to let Ainkrad read Notes the first time. Nothing becomes a note until you review it")
            CoreRow(
                "Earlier Imports", subtitle: "Continue or undo an import", symbol: "clock.arrow.circlepath",
                action: { model.openHistory() }
            )
            .help("See imports you started before")
            HStack {
                Spacer(minLength: 0)
                Button("Close") { model.close() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            }
        }
    }

    // MARK: repo

    @ViewBuilder private var repoSetup: some View {
        if model.projectOptions.isEmpty {
            CoreStateCard(
                symbol: "folder.badge.questionmark", title: "No Projects Yet",
                line: "A repo import reads the docs of a project's repo. Add a project with a repo first.",
                secondary: CoreAction("Back") { model.phase = .chooser })
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreSelect("Project", selection: $model.project, options: model.projectOptions)
                Text(
                    "Reads the Markdown files under Docs/ in the project's repo copy on your Core. Nothing becomes a note until you review it."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Back", key: .cancel) { model.phase = .chooser },
                    primary: CoreAction("Read Docs", key: .primary) { model.readRepo() },
                    enabled: !model.project.isEmpty)
            }
        }
    }

    // MARK: progress, result, failure

    private func working(_ text: String, _ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(text).coreFont(size: MacTextSize.headline, weight: .semibold)
            if let progress {
                CoreMeter(progress, label: text)
            } else {
                CoreSkeleton(coreShape(Space.s1 / 2)).frame(height: Space.s1)
            }
            Text("You can close this. The import goes on, and Earlier Imports shows where it is.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            HStack {
                Spacer(minLength: 0)
                Button("Close") { model.close() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let run = model.run {
                Text(
                    "Imported \(LoreImportWords.notes(run.results["created"] ?? run.handled)) into \(LoreImportWords.place(run.project, model.projectNames))"
                )
                .coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(LoreImportWords.result(run)).foregroundStyle(palette.text2)
            }
            Text(
                "Wrong import? Undo Import puts every note back as it was. Notes you edit after this stay as you left them."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            CoreDialogFooter(
                cancel: CoreAction("Done", key: .cancel) { model.close() }, primary: nil,
                alternate: CoreAction("Undo Import") { model.undo() })
        }
    }

    private var undone: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let run = model.run {
                Text(LoreImportWords.undone(run)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CoreDialogFooter(cancel: CoreAction("Done", key: .cancel) { model.close() }, primary: nil)
        }
    }

    private var needsPermission: some View {
        CoreStateCard(
            symbol: "lock", title: "Allow Ainkrad to Read Notes",
            line:
                "macOS did not let Ainkrad control Notes. Turn on Notes under Ainkrad in System Settings, Privacy & Security, Automation, then try again.",
            secondary: CoreAction("Close") { model.close() },
            primary: CoreAction("Open Settings", key: .primary) { model.openAutomationSettings() })
    }

    private func failed(_ why: String) -> some View {
        CoreStateCard(
            symbol: "exclamationmark.triangle", title: "Unable to Import", line: why,
            secondary: CoreAction("Close") { model.close() },
            primary: model.canTryAgain ? CoreAction("Try Again", key: .primary) { model.tryAgain() } : nil)
    }

    // MARK: history

    @ViewBuilder private var history: some View {
        if !model.historyLoaded {
            Text("Loading…").foregroundStyle(palette.text2)
        } else if model.runs.isEmpty {
            CoreStateCard(
                symbol: "tray", title: "No Imports Yet",
                line: "Imports you start show up here, so you can continue or undo them.",
                secondary: CoreAction("Back") { model.phase = .chooser })
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                ScrollView {
                    LazyVStack(spacing: Space.s1) {
                        ForEach(model.runs) { run in LoreImportRunRow(model: model, run: run) }
                    }
                }
                .frame(height: Self.listHeight)
                HStack {
                    Spacer(minLength: 0)
                    Button("Back") { model.phase = .chooser }.buttonStyle(CoreButtonStyle(.secondary))
                        .coreShortcut(.cancel)
                }
            }
        }
    }
}

/// One earlier import. A click goes on from where it stopped; a finished or discarded one has nothing left to do.
private struct LoreImportRunRow: View {
    let model: LoreImportModel
    let run: LoreImportRun

    var body: some View {
        let state = LoreImportWords.state(run.state)
        let help = LoreImportWords.resumeHelp(run.state)
        let sub = [
            run.source == "mirror" ? "From repo" : run.source == "apple_notes" ? "From Apple Notes" : "From files",
            LoreImportWords.age(run.createdAt),
        ].compactMap { $0 }.joined(separator: " · ")
        let act: (() -> Void)? = help == nil ? nil : { model.resume(run) }
        CoreRow(
            "\(LoreImportWords.notes(run.include > 0 ? run.include : run.items)) into \(LoreImportWords.place(run.project, model.projectNames))",
            subtitle: sub, symbol: run.source == "mirror" ? "arrow.triangle.branch" : "doc.on.doc",
            action: act
        ) {
            StateBadge(state.label, tone: state.tone, symbol: state.symbol)
        }
        .help(help ?? "Nothing more to do with this import")
    }
}

/// The review: one summary line, then See Them… for the notes, their include and skip marks and the project.
struct LoreImportReview: View {
    @Bindable var model: LoreImportModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let run = model.run {
            VStack(alignment: .leading, spacing: Space.s3) {
                if run.items == 0 {
                    CoreNotice(
                        symbol: "doc.questionmark", title: "No Markdown Files Found",
                        text: run.source == "mirror"
                            ? "The repo has no .md files under Docs/ or docs/."
                            : run.source == "apple_notes"
                                ? "No notes could be read from Apple Notes."
                                : "None of the chosen files can be imported.",
                        tone: .warn)
                } else {
                    Text(LoreImportWords.summary(run, into: model.place))
                        .coreFont(size: MacTextSize.headline, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(LoreImportWords.plan(run)).foregroundStyle(palette.text2)
                    if let line = LoreImportWords.notTaken(
                        refused: run.refused, ignored: run.ignored, onThisMac: model.leftOut.values.reduce(0, +))
                    {
                        Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                    if run.source == "apple_notes" {
                        Text("Attachments are uploaded before this review. If you discard the import, they are removed after a day.")
                            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                    if (run.flags["conflict"] ?? 0) > 0 {
                        CoreNotice(
                            symbol: "exclamationmark.triangle", title: "Some notes were edited here",
                            text: "They stay as you wrote them. The new text is saved as a version you can restore.",
                            tone: .warn)
                    }
                    Button(model.seeThem ? "Hide Them" : "See Them…") { model.seeThem.toggle() }
                        .buttonStyle(CoreButtonStyle(.secondary))
                        .help("Choose which notes to import, and where they go")
                    if model.seeThem { list(run) }
                }
                if let n = model.notice { Text(n).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
                CoreDialogFooter(
                    cancel: CoreAction("Not Now", key: .cancel) { model.close() },
                    primary: CoreAction("Import \(LoreImportWords.notes(run.include))", key: .primary) {
                        model.commit()
                    },
                    alternate: CoreAction("Discard") { model.discard() }, enabled: run.include > 0)
            }
        }
    }

    private func list(_ run: LoreImportRun) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreSelect(
                "Project for new notes",
                selection: Binding(get: { model.project }, set: { model.moveAll(to: $0) }),
                options: model.projectOptionsWithPersonal)
            HStack(spacing: Space.s2) {
                Button("Include All") { model.setAll(include: true) }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Skip All") { model.setAll(include: false) }.buttonStyle(CoreButtonStyle(.secondary))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(model.items) { item in
                        CoreCheckbox(
                            item.title.isEmpty ? item.path : item.title,
                            detail: "\(item.path) · \(LoreImportWords.item(item))",
                            isOn: Binding(
                                get: { item.mark == "include" && !item.locked }, set: { model.set(item, include: $0) })
                        )
                        .disabled(item.locked)
                    }
                }
            }
            .frame(height: LoreImportView.listHeight)
        }
    }
}
