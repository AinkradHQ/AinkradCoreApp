import CoreUI
import Shell
import SwiftUI

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
                Text("Replace what is sealed. Name and settings stay.").foregroundStyle(palette.text2)
                CoreSecureField(
                    "New value", placeholder: "Paste the new value",
                    text: Binding(get: { form.value }, set: { form.setValue($0) }), autofocus: true
                ) { go(model) }
                Label(
                    "The old value is removed. Running sessions keep the old value until they end.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.tone(.warn).ink)
                .fixedSize(horizontal: false, vertical: true)
                if let i = form.issue { IssueLine(code: nil, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Seal new value", busy: form.busy, cancel: close) { go(model) }
            }
        }
        .accessibilityIdentifier("secret-form")
    }

    // MARK: new secret, three steps

    private func wizardBody(_ model: SecretsModel) -> some View {
        CoreDialogPanel("New secret", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s3) {
                StepTrack(["Type", "Value", "Details"], at: form.step, hue: GlassInk.orange)
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
            .animation(.smooth(duration: 0.25), value: form.step)
        }
        .accessibilityIdentifier("secret-form")
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What kind of value is it?").foregroundStyle(palette.text2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2) {
                ForEach(SecretWords.Kind.allCases, id: \.self) { k in
                    Button {
                        form.kind = k
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            IconTile(k.symbol, hue: k.available ? GlassInk.orange : GlassInk.slate, size: 36)
                            Text(k.title).fontWeight(.semibold)
                            Text(k.blurb).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                            if !k.available {
                                Text(SecretWords.comingNext).coreFont(size: MacTextSize.meta).foregroundStyle(
                                    palette.tone(.warn).ink)
                            }
                        }
                        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(GlassInk.well, in: coreShape(Radius.cardMac))
                        .overlay {
                            coreShape(Radius.cardMac).strokeBorder(
                                form.kind == k ? GlassInk.orange : GlassInk.wellEdge,
                                lineWidth: form.kind == k ? 1.5 : 1)
                        }
                        .contentShape(coreShape(Radius.cardMac))
                    }
                    .buttonStyle(.plain).disabled(!k.available).opacity(k.available ? 1 : 0.55)
                    .help(k.available ? k.blurb : "\(k.title): \(SecretWords.comingNext)")
                    .accessibilityAddTraits(form.kind == k ? .isSelected : [])
                }
            }
        }
    }

    private var valueStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Add the value. Ainkrad seals it. You will never see it again, only its name and size.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            CoreSecureField(
                "Value", placeholder: "Paste a test value",
                text: Binding(get: { form.value }, set: { form.setValue($0) }), autofocus: true
            ) { next() }
            HStack(spacing: Space.s3) {
                IconTile("arrow.down.doc", hue: GlassInk.slate, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Drop a file here, or choose").fontWeight(.semibold)
                    Text(SecretWords.comingNext).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac)).opacity(0.55)
            .help("Files: \(SecretWords.comingNext)")
            if form.value.isEmpty == false {
                Label("Ready to seal · \(SecretWords.size(Int64(form.value.utf8.count)))", systemImage: "lock.fill")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.tone(.done).ink)
            }
        }
    }

    private func detailsStep(_ model: SecretsModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField(
                    "Name", placeholder: "e.g. github-token-test", text: $form.name, mono: false, autofocus: true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Group")
                    Text("No group · \(SecretWords.comingNext)").foregroundStyle(palette.text2).opacity(0.7)
                        .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("What is it for?")
                Text("A description: \(SecretWords.comingNext)").foregroundStyle(palette.text2).opacity(0.7)
                    .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassInk.well, in: coreShape(Radius.control))
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("Runners that may use it")
                if model.runners.isEmpty {
                    Text("No runners yet. A secret no runner may use can't be given to an agent.").foregroundStyle(
                        palette.text2)
                }
                HStack(spacing: Space.s2) {
                    ForEach(model.runners) { r in
                        let on = form.runners.contains(r.id)
                        Button {
                            if on { form.runners.remove(r.id) } else { form.runners.insert(r.id) }
                        } label: {
                            Label(r.name, systemImage: on ? "checkmark" : "server.rack")
                                .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                                .background(on ? GlassInk.orange.opacity(0.2) : GlassInk.wellHover, in: coreShape(7))
                        }
                        .buttonStyle(.plain).help(r.online ? "\(r.name) is online" : "\(r.name) is offline right now")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("How the agent gets it")
                ForEach(Delivery.all, id: \.self) { d in
                    let on = form.delivery == d
                    Button {
                        form.delivery = d
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .foregroundStyle(on ? GlassInk.orange : palette.text2)
                            Text(SecretWords.delivery(d).line)
                            Spacer(minLength: 0)
                        }
                        .padding(Space.s2)
                        .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
                        .overlay {
                            coreShape(Radius.control).strokeBorder(on ? GlassInk.orange : .clear, lineWidth: 1.5)
                        }
                        .contentShape(coreShape(Radius.control))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Label(
                SecretWords.preview(
                    delivery: form.delivery, runners: form.runners.sorted().map(model.runnerName)),
                systemImage: "info.circle"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("secret-preview")
            Label("Once stored, nobody can show or copy it again. Asks for Touch ID.", systemImage: "lock.fill")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
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
                    .disabled((form.step == 0 && !form.kind.available) || (form.step == 1 && form.value.isEmpty))
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
        CoreDialogPanel("Let a runner use \(form.secret.name)", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Which runner")
                    if form.secret.runners.isEmpty {
                        Text("No runner may borrow this secret yet.").foregroundStyle(
                            palette.text2)
                    } else {
                        CoreSegmented(
                            "Runner", segments: form.secret.runners.map { CoreSegment($0, model.runnerName($0)) },
                            selection: $form.runner, fill: true)
                    }
                }
                CoreTextField(
                    "For how long", placeholder: "\(model.leaseLimit)", text: $form.ttl, suffix: "seconds",
                    autofocus: true
                ) { go(model) }
                Text(
                    "Up to \(SettingWords.duration(model.leaseLimit)). It comes back by itself when the time runs out."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                GlassToggleTile(
                    "An agent on that runner can read it", sub: "Allow it only on a runner whose agents you trust.",
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
                        IconTile("key.fill", hue: GlassInk.orange, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(secret.name).fontWeight(.semibold)
                            Text("\(SecretWords.versions(secret)) · \(SecretWords.changed(secret))")
                                .foregroundStyle(palette.text2)
                        }
                    }
                    Text(SecretWords.usage(secret, runnerNames: secret.runners.map(model.runnerName)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac))
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
