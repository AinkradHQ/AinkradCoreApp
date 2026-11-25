import AppKit
import CoreUI
import Projects
import Shell
import SwiftUI

// MARK: dialogs

@MainActor
enum KeyDialogs {
    static func openGenerate(_ m: LeylineModel) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "key-generate", onClose: { [weak m] in m?.clearWriteError() }) {
                GenerateKeySheet(model: m) { shell.closeDialog() }
            })
    }

    /// Import…, filled with a dropped key file's name and text when there is one.
    static func openImport(_ m: LeylineModel, name: String = "", pem: String = "") {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "key-import", onClose: { [weak m] in m?.clearWriteError() }) {
                ImportKeySheet(model: m, name: name, pem: pem) { shell.closeDialog() }
            })
    }
}

/// Generate Key: a name. The Core makes an ed25519 key and keeps it; Touch ID first.
struct GenerateKeySheet: View {
    let model: LeylineModel
    let close: () -> Void
    @State private var name = ""
    @Environment(\.corePalette) private var palette

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Generate Key", line: "Needs Touch ID.")
                CoreTextField(
                    "Name", placeholder: "lanterna-deploy", text: $name, error: model.writeError, autofocus: true,
                    onSubmit: make
                )
                .accessibilityIdentifier("key-generate-name")
                Text(
                    "The Core makes an ed25519 key and keeps the private half sealed. You can copy the public half to a host; the private half is never shown."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Generate", key: .primary, run: make), busy: model.busy,
                    enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: name) { _, _ in model.clearWriteError() }
        .accessibilityIdentifier("key-generate")
    }

    private func make() {
        guard !model.busy else { return }
        Task { await model.generateKey(name: name) }
    }
}

/// Import…: an OpenSSH or PEM private key (ed25519, ECDSA, RSA 2048+), and its passphrase when it has one. It is sent once, sealed by the Core and never shown
/// again; this sheet drops it the moment it closes. Touch ID first.
struct ImportKeySheet: View {
    let model: LeylineModel
    let close: () -> Void
    @State private var name: String
    @State private var pem: String
    @State private var passphrase = ""
    @Environment(\.corePalette) private var palette

    init(model: LeylineModel, name: String = "", pem: String = "", close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _name = State(initialValue: name)
        _pem = State(initialValue: pem)
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Add a key you already have", line: "Needs Touch ID.")
                CoreTextField("Name", placeholder: "ops-personal", text: $name, autofocus: true)
                CoreTextArea(
                    "Private key",
                    placeholder: "-----BEGIN OPENSSH PRIVATE KEY----- or -----BEGIN RSA PRIVATE KEY-----", text: $pem,
                    error: model.writeError, size: MacTextSize.meta, minHeight: Space.s8 * 3, design: .monospaced
                )
                CoreSecureField("Passphrase", placeholder: "Only for an encrypted key", text: $passphrase)
                Text(
                    "OpenSSH or PEM keys: ed25519, ECDSA P-256/P-384, or RSA 2048 bits or larger. The key is sent once and sealed in the Core. It cannot be shown again."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: model.keyTooWeak
                        ? CoreAction("Make a new key for me", key: .primary, run: makeNew)
                        : CoreAction("Import", key: .primary, run: bring),
                    busy: model.busy,
                    enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && (!pem.isEmpty || model.keyTooWeak))
            }
        }
        .onChange(of: pem) { _, _ in model.clearWriteError() }
        .onDisappear {
            pem = ""
            passphrase = ""
        }
        .accessibilityIdentifier("key-import")
    }

    /// The "too weak" way out: a fresh ed25519 key under the same name; the weak one was never stored.
    private func makeNew() {
        guard !model.busy else { return }
        pem = ""
        passphrase = ""
        Task { await model.generateKey(name: name) }
    }

    private func bring() {
        guard !model.busy else { return }
        Task { await model.importKey(name: name, privateKey: pem, passphrase: passphrase) }
    }
}
