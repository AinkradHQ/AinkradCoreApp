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

struct SecretFormDialog: View {
    let admin: AdminModel
    @Bindable var form: SecretForm
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.secrets!
        let title = form.existing.map { "New value for \($0.name)" } ?? "New secret"
        CoreDialogPanel(title, width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if form.existing == nil {
                    CoreTextField(
                        "Name", placeholder: "e.g. github-token-test", text: $form.name, mono: false, autofocus: true)
                }
                CoreSecureField(
                    "Value", placeholder: "Paste a test value",
                    text: Binding(get: { form.value }, set: { form.setValue($0) }), autofocus: form.existing != nil
                ) { go(model) }
                if form.existing == nil {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("How a runner gets it")
                        CoreSegmented(
                            "Delivery",
                            segments: Delivery.all.map {
                                CoreSegment($0, Delivery.look($0).title, symbol: Delivery.look($0).symbol)
                            },
                            selection: $form.delivery, fill: true)
                        Text(Delivery.look(form.delivery).line).font(.system(size: MacTextSize.meta))
                            .foregroundStyle(GlassInk.secondary)
                    }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("Runners it may be lent to")
                        if model.runners.isEmpty {
                            Text("No runners yet. A secret no runner may use can't be lent.").foregroundStyle(
                                palette.text2)
                        }
                        ForEach(model.runners) { r in
                            GlassToggleTile(
                                r.name, sub: r.online ? "Online" : "Offline right now", symbol: "server.rack",
                                onSymbol: "checkmark.square.fill",
                                isOn: Binding(
                                    get: { form.runners.contains(r.id) },
                                    set: { if $0 { form.runners.insert(r.id) } else { form.runners.remove(r.id) } }),
                                fill: true
                            )
                            .help(r.id)
                        }
                    }
                }
                Label("Once stored, nobody can show or copy it again. Asks for Touch ID.", systemImage: "lock.fill")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                if let i = form.issue { IssueLine(code: nil, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                CoreDialogFooter(
                    confirm: form.existing == nil ? "Store" : "Replace value", busy: form.busy, cancel: close
                ) {
                    go(model)
                }
            }
        }
        .accessibilityIdentifier("secret-form")
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
        CoreDialogPanel("Lend \(form.secret.name)", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("To which runner")
                    if form.secret.runners.isEmpty {
                        Text("No runner may be lent this secret yet.").foregroundStyle(
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
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                GlassToggleTile(
                    "An agent on that runner can read it", sub: "Lend it only to a runner whose agents you trust.",
                    symbol: "exclamationmark.triangle", onSymbol: "checkmark.shield.fill", isOn: $form.understood,
                    fill: true)
                if let i = form.issue { IssueLine(code: nil, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                CoreDialogFooter(confirm: "Lend", busy: form.busy, cancel: close) { go(model) }
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

    var body: some View {
        CoreDialogPanel("Delete \(secret.name)?", width: Space.s8 * 13) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Runners can no longer be lent it. This can't be undone.")
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                CoreDialogFooter(confirm: "Delete", danger: true, busy: busy, cancel: close) {
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
