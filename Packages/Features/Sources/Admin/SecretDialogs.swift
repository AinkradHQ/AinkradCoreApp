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
            Spacer(minLength: 0)
            Button("Cancel", action: cancel).buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            if danger {
                Button(confirm, action: run).buttonStyle(AdminDangerStyle()).disabled(!enabled || busy)
            } else {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                    .keyboardShortcut(.defaultAction).disabled(!enabled || busy)
            }
        }
    }
}

struct AdminDangerStyle: ButtonStyle {
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let t = palette.tone(.fail)
        configuration.label
            .font(.system(size: MacTextSize.body, weight: .medium)).foregroundStyle(t.ink)
            .frame(minHeight: MacSize.controlMd).padding(.horizontal, Space.s3)
            .background(configuration.isPressed ? t.fill.opacity(2) : t.fill, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(t.ink.opacity(0.5), lineWidth: 1) }
            .coreDimWhenDisabled(enabled)
    }
}

struct SecretFormDialog: View {
    let admin: AdminModel
    @Bindable var form: SecretForm
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.secrets!
        let title = form.existing.map { "Replace value of \($0.name)" } ?? "New secret"
        AdminDialog(title: title, width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if form.existing == nil {
                    CoreTextField(
                        "Name", placeholder: "e.g. e5-07-test", text: $form.name, mono: false, autofocus: true)
                }
                CoreSecureField(
                    "Value (write-only)", placeholder: "Paste a throwaway value",
                    text: Binding(get: { form.value }, set: { form.setValue($0) }), autofocus: form.existing != nil
                ) { go(model) }
                if form.existing == nil {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("Delivery")
                        CoreSegmented(
                            "Delivery", segments: ["env", "file", "askpass"].map { CoreSegment($0, $0) },
                            selection: $form.delivery)
                    }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        CoreFieldLabel("Runners allowed")
                        if model.runners.isEmpty {
                            Text("No runners yet. A secret with no runners cannot be leased.").foregroundStyle(
                                palette.text2)
                        }
                        ForEach(model.runners) { r in
                            CoreCheckbox(
                                r.name, detail: "\(r.id)\(r.online ? "" : " · offline")",
                                isOn: Binding(
                                    get: { form.runners.contains(r.id) },
                                    set: { if $0 { form.runners.insert(r.id) } else { form.runners.remove(r.id) } }))
                        }
                    }
                }
                Text("The value is stored and never shown again. There is no way to read or copy it back.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                if let i = form.issue { IssueLine(code: i.code, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: form.existing == nil ? "Store" : "Replace", busy: form.busy, cancel: close) {
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
        AdminDialog(title: "Lease \(form.secret.name)", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Runner")
                    if form.secret.runners.isEmpty {
                        Text("This secret has no runners. Replace its scope before leasing it.").foregroundStyle(
                            palette.text2)
                    } else {
                        CoreSegmented(
                            "Runner", segments: form.secret.runners.map { CoreSegment($0, model.runnerName($0)) },
                            selection: $form.runner)
                    }
                }
                CoreTextField(
                    "Lease length", placeholder: "Default \(model.leaseLimit)", text: $form.ttl, suffix: "s",
                    autofocus: true
                ) { go(model) }
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(palette.tone(.warn).ink)
                        .accessibilityHidden(true)
                    Text(
                        "Any secret leased to a session can be read by that session's agent. An agent on that runner would be able to read the value."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3).background(palette.tone(.warn).fill, in: coreShape(Radius.cardMac))
                CoreCheckbox("I understand an agent on that runner can read it", isOn: $form.understood)
                if let i = form.issue { IssueLine(code: i.code, text: i.message) }
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Lease", busy: form.busy, cancel: close) { go(model) }
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
        AdminDialog(title: "Delete \(secret.name)?", width: Space.s8 * 13) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Runners can no longer be leased this secret. This cannot be undone.")
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                DialogButtons(confirm: "Delete", danger: true, busy: busy, cancel: close) {
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
