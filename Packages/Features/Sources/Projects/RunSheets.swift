import CoreUI
import Shell
import SwiftUI

/// The dialogs of the Run page, shown over the shell like the other Projects dialogs.
@MainActor
enum RunDialogs {
    /// Set… (a new name or a name the spec asks for) and Replace… (`name` given, so it cannot be renamed).
    static func openSecret(_ run: RunPageModel, project: ProjectItem, name: String?, replacing: Bool) {
        run.clearWriteError()
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-secret", onClose: { [weak run] in run?.clearWriteError() }) {
                SecretSheet(run: run, project: project, name: name, replacing: replacing) { shell.closeDialog() }
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
        let shell = run.model.host.shell
        shell.present(
            ShellDialog(id: "project-changes") {
                ChangesSheet(spec: spec, previous: run.previous) { shell.closeDialog() }
            })
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
    @Environment(\.corePalette) private var palette

    init(run: RunPageModel, project: ProjectItem, name: String?, replacing: Bool, close: @escaping () -> Void) {
        self.run = run
        self.project = project
        self.replacing = replacing
        nameFixed = name != nil
        self.close = close
        _name = State(initialValue: name ?? "")
    }

    private var nameProblem: String? { name.isEmpty || nameFixed ? nil : SecretRules.nameProblem(name) }
    private var ready: Bool { SecretRules.nameProblem(name) == nil && !value.isEmpty }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: replacing ? "Replace Secret" : "Set Secret",
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
                CoreSecureField(
                    "Value", placeholder: replacing ? "New value" : "Value", text: $value,
                    error: run.writeError, autofocus: nameFixed, onSubmit: save)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(replacing ? "Replace" : "Set", key: .primary, run: save), busy: run.busy,
                    enabled: ready)
            }
        }
        .onChange(of: value) { _, _ in run.clearWriteError() }
        .accessibilityIdentifier("project-secret")
    }

    private func save() {
        guard ready, !run.busy else { return }
        let (n, v) = (name, value)
        Task {
            if await run.setSecret(name: n, value: v, replacing: replacing, projectName: project.name) { close() }
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
                            // The sign carries the meaning; the colour only backs it.
                            Text("\(l.added ? "+" : "−") \(l.text)")
                                .font(.system(size: MacTextSize.body, design: .monospaced))
                                .foregroundStyle(palette.tone(l.added ? .done : .fail).ink)
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
