import AppKit
import CoreUI
import Shell
import SwiftUI

/// The dialogs of the Run page, shown over the shell like the other Projects dialogs.
@MainActor
enum RunDialogs {
    /// Set… (a new name or a name the spec asks for) and Replace… (`name` given, so it cannot be renamed).
    static func openSecret(
        _ run: RunPageModel, project: ProjectItem, name: String?, replacing: Bool, kind: String = "text"
    ) {
        run.clearWriteError()
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-secret", onClose: { [weak run] in run?.clearWriteError() }) {
                SecretSheet(run: run, project: project, name: name, replacing: replacing, kind: kind) {
                    shell.closeDialog()
                }
            })
    }

    /// The setup's saved versions, each with See Changes and Go back to it.
    static func openHistory(_ run: RunPageModel, project: ProjectItem) {
        run.clearWriteError()
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-history", onClose: { [weak run] in run?.clearWriteError() }) {
                SetupHistorySheet(run: run, project: project) { shell.closeDialog() }
            })
    }

    static func openChanges(_ spec: SpecVersionItem, previous: SpecVersionItem?, model: ProjectsModel) {
        let shell = model.host.shell
        shell.present(
            ShellDialog(id: "project-changes") { ChangesSheet(spec: spec, previous: previous) { shell.closeDialog() } })
    }

    /// Delete…: asks once; when the setup still uses the secret the Core says so and a second ask offers to delete anyway.
    static func confirmDelete(_ run: RunPageModel, project: ProjectItem, name: String) {
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-secret-delete") {
                CoreConfirmDialog(
                    "Delete \(name)?",
                    message: "It is removed from the Core for good. A setup that asks for it will not start.",
                    confirmTitle: "Delete", destructive: true,
                    onConfirm: {
                        shell.closeDialog()
                        Task {
                            let r = await run.deleteSecret(name, force: false, projectName: project.name)
                            if case .usedBy(let why) = r { forceDelete(run, project: project, name: name, why: why) }
                        }
                    }, onCancel: { shell.closeDialog() })
            })
    }

    private static func forceDelete(_ run: RunPageModel, project: ProjectItem, name: String, why: String) {
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-secret-force") {
                CoreConfirmDialog(
                    "\(name) is still used", message: "\(why) Delete it anyway?", confirmTitle: "Delete Anyway",
                    destructive: true,
                    onConfirm: {
                        shell.closeDialog()
                        Task { _ = await run.deleteSecret(name, force: true, projectName: project.name) }
                    }, onCancel: { shell.closeDialog() })
            })
    }

    static func openSetup(_ run: RunPageModel, project: ProjectItem) {
        run.clearWriteError()
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-setup", onClose: { [weak run] in run?.clearWriteError() }) {
                SetupSheet(run: run, project: project) { shell.closeDialog() }
            })
    }

    static func openChanges(_ run: RunPageModel) {
        guard let spec = run.spec else { return }
        openChanges(spec, previous: run.previous, model: run.model)
    }
}

/// Set a secret or replace one. The value field is write-only: dots while typing, nothing is shown back, and the text leaves
/// this view with the dialog.
struct SecretSheet: View {
    let run: RunPageModel
    let project: ProjectItem
    let replacing: Bool
    /// Fixed when the name came with the row (Set… or Replace… on one); only Add… asks for one.
    let nameFixed: Bool
    let close: () -> Void
    @State private var name: String
    @State private var value = ""
    @State private var kind: String
    @State private var note = ""
    @State private var fileName: String?
    @State private var fileProblem: String?
    @Environment(\.corePalette) private var palette

    /// What a secret can be stored as, in the Core's words.
    static let kinds = [
        CoreSelectOption("text", "Text", note: "One value, such as a key or a password"),
        CoreSelectOption("multiline", "Several lines", note: "A certificate or a private key"),
        CoreSelectOption("file", "A file", note: "Given to the run as a file"),
        CoreSelectOption("env_bundle", "Environment bundle", note: "NAME=value lines, all given to the run"),
    ]

    /// The largest file the Core takes, decoded.
    static let fileLimit = 1_048_576

    init(
        run: RunPageModel, project: ProjectItem, name: String?, replacing: Bool, kind: String = "text",
        close: @escaping () -> Void
    ) {
        self.run = run
        self.project = project
        self.replacing = replacing
        nameFixed = name != nil
        self.close = close
        _name = State(initialValue: name ?? "")
        _kind = State(initialValue: kind)
    }

    private var nameProblem: String? { name.isEmpty || nameFixed ? nil : SecretRules.nameProblem(name) }
    private var ready: Bool {
        SecretRules.nameProblem(name) == nil && !value.isEmpty && fileProblem == nil
            && (kind != "file" || fileName != nil)
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: replacing ? "Replace secret" : "Set secret",
                    line: "Sealed in the Core and given to the run at start. Never shown again.")
                if nameFixed {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("Name")
                        Text(name).font(.system(size: MacTextSize.body, design: .monospaced))
                    }
                } else {
                    CoreTextField(
                        "Name", placeholder: "stripe_secret", text: $name, error: nameProblem, mono: true,
                        autofocus: true)
                }
                CoreSelect("Kind", selection: $kind, options: Self.kinds)
                valueField
                CoreTextField("Note (optional)", placeholder: "What it is for", text: $note)
                if !ready, nameProblem == nil, fileProblem == nil {
                    Text(kind == "file" ? "Choose a file first." : value.isEmpty ? "Enter a value first." : "Give it a name first.")
                        .foregroundStyle(GlassInk.secondary)
                }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(replacing ? "Replace" : "Set", key: .primary, run: save), busy: run.busy,
                    enabled: ready)
            }
        }
        .onChange(of: value) { _, _ in run.clearWriteError() }
        .onChange(of: kind) { _, _ in
            value = ""
            fileName = nil
            fileProblem = nil
        }
        .accessibilityIdentifier("project-secret")
    }

    @ViewBuilder private var valueField: some View {
        switch kind {
        case "multiline", "env_bundle":
            CoreTextArea(
                "Value", placeholder: kind == "env_bundle" ? "NAME=value" : "Paste it here", text: $value,
                error: run.writeError, minHeight: Space.s8 * 4, maxHeight: Space.s8 * 8, autofocus: nameFixed,
                design: .monospaced)
        case "file":
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("File")
                HStack(spacing: Space.s2) {
                    Button(fileName == nil ? "Choose File…" : "Choose Another…") { chooseFile() }
                        .buttonStyle(CoreButtonStyle(.secondary))
                    if let fileName { Text(fileName).font(.system(size: MacTextSize.body, design: .monospaced)) }
                }
                if let e = fileProblem ?? run.writeError { CoreFieldError(e) }
            }
        default:
            CoreSecureField(
                "Value", placeholder: replacing ? "New value" : "Value", text: $value, error: run.writeError,
                autofocus: nameFixed, onSubmit: save)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            fileProblem = "That file could not be read."
            return
        }
        if data.count > Self.fileLimit {
            fileProblem = "That file is over 1 MB, which is the most a secret can hold."
            return
        }
        fileProblem = nil
        fileName = url.lastPathComponent
        value = data.base64EncodedString()
    }

    private func save() {
        guard ready, !run.busy else { return }
        let n = name
        let input = SecretInput(value: value, kind: kind, description: note, fileName: kind == "file" ? fileName : nil)
        Task {
            if await run.setSecret(name: n, input: input, replacing: replacing, projectName: project.name) { close() }
        }
    }
}

/// Edit Setup…: the run spec as JSON. Saving makes a new version; an old one is never changed.
struct SetupSheet: View {
    let run: RunPageModel
    let project: ProjectItem
    let close: () -> Void
    @State private var text: String
    @State private var image = SetupSheet.images[0].value

    /// What a Makefile or script drafted from the repo runs in (all carry `make`): the smallest picker that works.
    static let images = [
        CoreSelectOption("node:22", "Node 22"), CoreSelectOption("python:3.13", "Python 3.13"),
        CoreSelectOption("golang:1.24", "Go 1.24"), CoreSelectOption("buildpack-deps:stable", "Plain Linux"),
    ]

    /// What a project with no setup starts from: one public web service to edit.
    static let starter = """
        {
          "services": {
            "web": {
              "image": "nginx:alpine",
              "ports": [{ "port": 80, "expose": true }]
            }
          }
        }
        """

    init(run: RunPageModel, project: ProjectItem, close: @escaping () -> Void) {
        self.run = run
        self.project = project
        self.close = close
        _text = State(initialValue: run.spec?.json ?? Self.starter)
    }

    private var changed: Bool { text != (run.spec?.json ?? "") }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Edit Setup",
                    line:
                        "The services this project runs, as JSON. Saving makes a new version; the run uses it at its next start. Secrets are written ${secret:NAME}."
                )
                CoreTextArea(
                    nil, placeholder: "{ \"services\": { … } }", text: $text, error: run.writeError,
                    minHeight: Space.s8 * 8, maxHeight: Space.s8 * 14, autofocus: true, design: .monospaced)
                HStack(alignment: .bottom, spacing: Space.s3) {
                    CoreSelect("Image for a Makefile or script", selection: $image, options: Self.images)
                    Button("History…") { RunDialogs.openHistory(run, project: project) }
                        .buttonStyle(CoreButtonStyle(.plain))
                        .disabled(run.versions.count < 2)
                        .help(
                            run.versions.count < 2 ? "There is one version so far" : "Every saved version of the setup")
                    Button("Draft from Repo") {
                        let i = image
                        Task { if await run.draftFromRepo(image: i, projectName: project.name) { close() } }
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .disabled(run.busy)
                    .help(
                        "Read the primary repo's compose file, run.sh, Makefile or package.json and draft the setup. Nothing is run."
                    )
                }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Save Setup", key: .command, run: save), busy: run.busy, enabled: changed)
            }
        }
        .onChange(of: text) { _, _ in run.clearWriteError() }
        .accessibilityIdentifier("project-setup")
    }

    private func save() {
        guard changed, !run.busy else { return }
        let t = text
        Task {
            if await run.saveSpec(
                t, reason: "Save a new setup for \(project.name).", done: "Setup saved")
            {
                close()
            }
        }
    }
}

/// See Changes: the lines this version added or removed, against the version before it (all of it for the first).
struct ChangesSheet: View {
    let spec: SpecVersionItem
    let previous: SpecVersionItem?
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    private var lines: [SpecDiff.Line] { SpecDiff.lines(from: previous?.json, to: spec.json) }

    private func sign(_ k: SpecDiff.Kind) -> String {
        switch k {
        case .added: "+"
        case .removed: "−"
        case .context, .gap: " "
        }
    }

    private func ink(_ k: SpecDiff.Kind) -> Color {
        switch k {
        case .added: palette.tone(.done).ink
        case .removed: palette.tone(.fail).ink
        case .context, .gap: palette.text2
        }
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Changes in Version \(spec.version)",
                    line: previous.map { "Compared with version \($0.version)." }
                        ?? "This is the first version, so everything in it is new.")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            // The sign carries the meaning; the colour only backs it. Unchanged lines give the context.
                            Text("\(sign(l.kind)) \(l.text)")
                                .font(.system(size: MacTextSize.body, design: .monospaced))
                                .foregroundStyle(ink(l.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if lines.isEmpty { Text("Nothing changed.").foregroundStyle(palette.text2) }
                    }
                    .padding(Space.s3)
                }
                .frame(height: Space.s8 * 10)
                .coreCard(GlassInk.well, radius: Radius.cardMac)
                CoreDialogFooter(cancel: CoreAction("Close", key: .cancel, run: close), primary: nil)
            }
        }
        .accessibilityIdentifier("project-changes")
    }
}

/// Every saved version of the setup, newest first. See Changes compares one with the one before it; Go Back saves an older one
/// again as the newest (nothing is lost or rewritten).
struct SetupHistorySheet: View {
    let run: RunPageModel
    let project: ProjectItem
    let close: () -> Void

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Setup History",
                    line: "Each save is a new version. Going back saves the older one again, so nothing is lost.")
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(run.versions) { v in
                            CoreRow(
                                "Version \(v.version)\(v.version == run.versions.first?.version ? " · current" : "")",
                                subtitle: [
                                    Self.origin(v.origin), v.createdAt.map { runsAgo($0, now: run.model.now()) },
                                ]
                                .compactMap { $0 }.joined(separator: " · "),
                                symbol: "clock.arrow.circlepath"
                            ) {
                                Button("See Changes") {
                                    Task {
                                        if let (cur, before) = await run.changes(of: v) {
                                            RunDialogs.openChanges(cur, previous: before, model: run.model)
                                        }
                                    }
                                }
                                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                                if v.version != run.versions.first?.version {
                                    Button("Go Back") {
                                        Task { if await run.rollBack(to: v, projectName: project.name) { close() } }
                                    }
                                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                                    .disabled(run.busy || run.model.readOnly)
                                }
                            }
                        }
                    }
                }
                .frame(height: Space.s8 * 9)
                if let e = run.writeError { CoreFieldError(e) }
                CoreDialogFooter(cancel: CoreAction("Close", key: .cancel, run: close), primary: nil)
            }
        }
        .accessibilityIdentifier("project-history")
    }

    static func origin(_ o: String) -> String {
        switch o {
        case "manual": "Written by hand"
        case "compose": "Drafted from docker-compose.yml"
        case "package_json": "Drafted from package.json"
        case "makefile": "Drafted from the Makefile"
        case "run_sh": "Drafted from run.sh"
        default: o
        }
    }
}
