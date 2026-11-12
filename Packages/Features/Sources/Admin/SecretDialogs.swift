import AppKit
import CoreUI
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// The dialogs of the Secrets section, shown over the shell like the Devices dialogs.
@MainActor
enum SecretDialogs {
    static func openNew(_ admin: AdminModel) { openForm(admin, SecretForm()) }
    static func openReplace(_ admin: AdminModel, _ s: SecretItem) { openForm(admin, SecretForm(existing: s)) }

    private static func openForm(_ admin: AdminModel, _ form: SecretForm) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        shell.present(
            ShellDialog(
                id: "secret-form",
                onClose: { [weak admin] in
                    form.wipe()
                    admin?.host.clearElevationNotice()
                }
            ) {
                SecretFormDialog(admin: admin, form: form) { shell.closeDialog() }
            })
    }

    static func openLease(_ admin: AdminModel, _ s: SecretItem) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        let form = LeaseForm(secret: s)
        shell.present(
            ShellDialog(id: "secret-lease", onClose: { [weak admin] in admin?.host.clearElevationNotice() }) {
                LeaseDialog(admin: admin, form: form) { shell.closeDialog() }
            })
    }

    static func openGroup(_ admin: AdminModel, _ g: SecretGroupItem?) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        shell.present(
            ShellDialog(id: "secret-group", onClose: { [weak admin] in admin?.host.clearElevationNotice() }) {
                GroupDialog(admin: admin, existing: g) { shell.closeDialog() }
            })
    }

    static func openGroupLease(_ admin: AdminModel, _ g: SecretGroupItem) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        let form = LeaseForm(group: g)
        shell.present(
            ShellDialog(id: "secret-lease", onClose: { [weak admin] in admin?.host.clearElevationNotice() }) {
                LeaseDialog(admin: admin, form: form) { shell.closeDialog() }
            })
    }

    static func openDeleteGroup(_ admin: AdminModel, _ g: SecretGroupItem) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        shell.present(
            ShellDialog(id: "secret-group-delete", onClose: { [weak admin] in admin?.host.clearElevationNotice() }) {
                DeleteGroupDialog(admin: admin, group: g) { shell.closeDialog() }
            })
    }

    static func openDelete(_ admin: AdminModel, _ s: SecretItem) {
        admin.host.clearElevationNotice()
        let shell = admin.host.shell
        shell.present(
            ShellDialog(id: "secret-delete", onClose: { [weak admin] in admin?.host.clearElevationNotice() }) {
                DeleteDialog(admin: admin, secret: s) { shell.closeDialog() }
            })
    }
}

private struct DialogButtons: View {
    let confirm: String
    var danger = false
    var busy: Bool
    var enabled = true
    let cancel: () -> Void
    let run: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            Button("Cancel", action: cancel).buttonStyle(.coreSecondary).coreShortcut(.cancel)
            Spacer(minLength: 0)
            if danger {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.danger)).disabled(!enabled || busy)
            } else {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                    .coreShortcut(.primary).disabled(!enabled || busy)
            }
        }
    }
}

struct SecretFormDialog: View {
    let admin: AdminModel
    @Bindable var form: SecretForm
    let close: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var fileError: String?

    var body: some View {
        let model = admin.secrets!
        if let old = form.existing {
            replaceBody(model, old)
        } else {
            wizardBody(model)
        }
    }

    // MARK: new value

    private func replaceBody(_ model: SecretsModel, _ old: SecretItem) -> some View {
        CoreDialogPanel("New value for \(old.name)", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                valueInput(label: "New value", placeholder: "Paste the new value") { go(model) }
                Text("Running AI sessions keep the old value until they end.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let i = form.issue { IssueLine(code: nil, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Seal new value", busy: form.busy, cancel: close) { go(model) }
            }
        }
        .accessibilityIdentifier("secret-form")
    }

    // MARK: the value, for every kind

    /// A secure line for text, a text box for many lines, and a file chooser or drop zone for a file. A file or text file can
    /// also be picked for the multi-line kinds.
    @ViewBuilder private func valueInput(label: String, placeholder: String, submit: @escaping () -> Void) -> some View
    {
        switch form.kind {
        case .text:
            CoreSecureField(
                label, placeholder: placeholder, text: Binding(get: { form.value }, set: { form.setValue($0) }),
                autofocus: true, onSubmit: submit)
        case .multiline, .env:
            CoreTextArea(
                label, placeholder: placeholder, text: Binding(get: { form.value }, set: { form.setValue($0) }),
                minHeight: Space.s8 * 4, autofocus: true
            )
            .accessibilityIdentifier("secret-multiline")
            FileDrop(form: form, prompt: "Or drop a text file here, or choose", error: $fileError)
        case .file:
            FileDrop(form: form, prompt: "Drop a file here, or choose", error: $fileError)
        }
        if let e = fileError { IssueLine(code: nil, text: e) }
        if let n = form.shownSize {
            Label(
                (form.fileName.map { "\($0) · " } ?? "") + "Ready to seal · \(SecretWords.size(n))",
                systemImage: "lock.fill"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
    }

    // MARK: new secret, three steps

    private func wizardBody(_ model: SecretsModel) -> some View {
        CoreDialogPanel("New secret", width: Space.s8 * 17) {
            VStack(alignment: .leading, spacing: Space.s4) {
                CoreStepper(["Type", "Value", "Details"], at: form.step)
                switch form.step {
                case 0: typeStep
                case 1: valueStep
                default: detailsStep(model)
                }
                if form.step == 2 {
                    if let i = form.issue { IssueLine(code: nil, text: i.message) }
                    AdminNoticeBanner(notice: admin.host.elevationNotice)
                }
                footer(model)
            }
            .animation(reduce ? nil : Motion.out(Motion.ui), value: form.step)
        }
        .accessibilityIdentifier("secret-form")
    }

    /// The four kinds as choice rows, two by two, each with its one-line blurb.
    private var typeStep: some View {
        let kinds = SecretWords.Kind.allCases
        return Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
            ForEach([0, 2], id: \.self) { i in
                GridRow {
                    ForEach(kinds[i..<i + 2], id: \.self) { k in
                        RadioRow(k.title, subtitle: k.blurb, symbol: k.symbol, selected: form.kind == k) { pick(k) }
                            .help(k.blurb)
                    }
                }
            }
        }
    }

    private func pick(_ k: SecretWords.Kind) {
        form.kind = k
        form.delivery = k.delivery
        form.wipe()
        form.fileName = nil
        fileError = nil
    }

    private var valueStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Ainkrad seals it. Only its name and size come back.").foregroundStyle(palette.text2)
            valueInput(label: "Value", placeholder: "Paste a test value") { next() }
        }
    }

    private func detailsStep(_ model: SecretsModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField(
                    "Name", placeholder: "e.g. github-token-test", text: $form.name, mono: false, autofocus: true)
                CoreSelect(
                    "Group",
                    selection: Binding(get: { form.group ?? "" }, set: { form.group = $0.isEmpty ? nil : $0 }),
                    options: [CoreSelectOption("", "No group")]
                        + model.groups.map { CoreSelectOption($0.name, $0.name, symbol: "folder") })
            }
            CoreTextField(
                "What is it for?", placeholder: "e.g. Pushes to the website repository", text: $form.description)
            if form.kind.isFile {
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "File name on the runner", placeholder: "aws.json",
                        text: Binding(get: { form.fileName ?? "" }, set: { form.fileName = $0 }))
                    CoreTextField("File mode", placeholder: "0600", text: $form.fileMode, mono: true)
                        .frame(width: Space.s8 * 3)
                }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("Runners that may use it")
                if let g = model.groups.first(where: { $0.name == form.group }), form.runners.isEmpty {
                    Text(
                        "Left empty, it uses the runners of \(g.name): \(SecretWords.usedBy(g.runners.map(model.runnerName)))."
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
                RunnerPicks(runners: model.runners, picked: $form.runners)
            }
            if !form.kind.isFile {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("How an AI session gets it")
                    VStack(spacing: 2) {
                        ForEach(Delivery.all, id: \.self) { d in
                            RadioRow(SecretWords.delivery(d).line, selected: form.delivery == d) { form.delivery = d }
                        }
                    }
                }
            }
            Label(
                SecretWords.preview(
                    delivery: form.kind.isFile ? "file" : form.delivery,
                    runners: form.runners.sorted().map(model.runnerName)),
                systemImage: "info.circle"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("secret-preview")
        }
    }

    private func footer(_ model: SecretsModel) -> some View {
        HStack(spacing: Space.s2) {
            if form.step == 0 {
                Button("Cancel", action: close).buttonStyle(.coreSecondary).coreShortcut(.cancel)
            } else {
                Button("Back") { form.step -= 1 }.buttonStyle(.coreSecondary)
            }
            Spacer(minLength: 0)
            if form.step < 2 {
                Button("Next", action: next).buttonStyle(.coreProminent).coreShortcut(.primary)
                    .disabled(form.step == 1 && form.value.isEmpty)
            } else {
                Button("Seal secret") { go(model) }.buttonStyle(CoreButtonStyle(.prominent, busy: form.busy))
                    .coreShortcut(.primary).disabled(form.busy)
            }
        }
    }

    private func next() {
        if form.step == 1 && form.value.isEmpty { return }
        if form.step < 2 { form.step += 1 }
    }

    private func go(_ model: SecretsModel) {
        Task {
            let done = form.existing == nil ? await model.store(form) : await model.replace(form)
            if done { close() }
        }
    }
}

struct LeaseDialog: View {
    let admin: AdminModel
    @Bindable var form: LeaseForm
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.secrets!
        CoreDialogPanel(
            form.isGroup
                ? "Let a runner use all of \(SecretWords.unbroken(form.name))"
                : "Let a runner use \(SecretWords.unbroken(form.name))",
            width: Space.s8 * 15
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Which runner")
                    if form.runnerIDs.isEmpty {
                        Text("No runner may borrow this yet.").foregroundStyle(
                            palette.text2)
                    } else {
                        CoreSegmented(
                            "Runner", segments: form.runnerIDs.map { CoreSegment($0, model.runnerName($0)) },
                            selection: $form.runner, fill: true)
                    }
                }
                CoreTextField(
                    "For how long", placeholder: "\(model.leaseLimit)", text: $form.ttl, suffix: "seconds"
                ) { go(model) }
                Text(
                    "Up to \(SettingWords.duration(model.leaseLimit)). It comes back by itself when the time runs out."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                GlassToggleTile(
                    "An AI session on that runner can read it",
                    sub: "Allow it only on a runner whose AI sessions you trust.",
                    symbol: "exclamationmark.triangle", onSymbol: "checkmark.shield.fill", isOn: $form.understood,
                    fill: true)
                if let i = form.issue { IssueLine(code: nil, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Allow", busy: form.busy, cancel: close) { go(model) }
            }
        }
        .accessibilityIdentifier("secret-lease")
    }

    private func go(_ model: SecretsModel) {
        Task { if await model.lease(form) { close() } }
    }
}

struct DeleteDialog: View {
    let admin: AdminModel
    let secret: SecretItem
    let close: () -> Void
    @State private var busy = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.secrets!
        CoreDialogPanel("Delete \(secret.name)?", width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("This cannot be undone.").foregroundStyle(palette.text2)
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s3) {
                        IconTile("key.fill", hue: GlassInk.blue, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(secret.name).fontWeight(.semibold)
                            Text("\(SecretWords.versions(secret)) · \(SecretWords.lastUsed(secret))")
                                .foregroundStyle(palette.text2)
                        }
                    }
                    Text(SecretWords.usage(secret, runnerNames: secret.runnersUsing.map(model.runnerName)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).coreWell()
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Delete with Touch ID", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let done = await admin.secrets.delete(secret)
                        busy = false
                        if done { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("secret-delete")
    }
}
