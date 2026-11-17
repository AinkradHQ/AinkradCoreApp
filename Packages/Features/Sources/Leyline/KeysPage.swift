import AppKit
import CoreUI
import Projects
import Shell
import SwiftUI

/// The Keys page: the keys the Core keeps sealed, each with the hosts it logs in to, beside the host keys the Core has pinned.
struct KeysPage: View {
    let model: LeylineModel
    @State private var settled = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            keys.coreRise(settled, 0)
            knownHosts.coreRise(settled, 1).frame(width: Space.s8 * 14)
        }
        .padding(.horizontal, Space.s2).padding(.bottom, Space.s2)
        .onAppear { settled = true }
        .accessibilityIdentifier("leyline-keys")
    }

    // MARK: keys

    private var keys: some View {
        Island(
            title: "Keys", sub: "sealed in the Core · never shown again",
            accessory: {
                Button("Import…") { KeyDialogs.openImport(model) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!canWrite)
                    .help("Import an OpenSSH private key into the Core · needs Touch ID")
                    .accessibilityIdentifier("leyline-import-key")
                Button {
                    KeyDialogs.openGenerate(model)
                } label: {
                    Label("Generate Key", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small)).disabled(!canWrite)
                .help("Make a key in the Core · needs Touch ID")
                .accessibilityIdentifier("leyline-generate-key")
            }
        ) {
            if model.keys.isEmpty {
                CoreStateCard(
                    symbol: "key", title: "No keys yet",
                    line:
                        "Generate one and the Core keeps it sealed. Hosts that log in with a key use it without ever seeing it.",
                    primary: canWrite ? CoreAction("Generate Key") { KeyDialogs.openGenerate(model) } : nil
                )
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Space.s2) {
                        ForEach(model.keys) { k in KeyCard(model: model, key: k) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .accessibilityIdentifier("leyline-keys-island")
    }

    private var canWrite: Bool { !model.readOnly && model.load == .ready }

    // MARK: known hosts

    private var knownHosts: some View {
        Island("Known hosts", sub: "pinned on first connect") {
            if model.knownHosts.isEmpty {
                // TODO(Y2-02): the Core pins a host key on the first connect and serves the list; until then it is empty.
                Text(
                    "Nothing is pinned yet. The first time Leyline connects to a host it keeps the host’s key, and stops before signing in if it ever changes."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(model.knownHosts) { k in KnownHostRow(known: k) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .accessibilityIdentifier("leyline-known-hosts")
    }
}

/// One key: its name and how it was made, "Install on Host…", a menu, and the hosts that log in with it.
struct KeyCard: View {
    let model: LeylineModel
    let key: KeyItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "key").coreFont(size: MacTextSize.body, weight: .medium).accessibilityHidden(true)
                Text(key.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(key.line).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: Space.s2)
                // TODO(Y1-04): installing a public key on a host over SSH arrives with the SSH driver (Y2-02).
                Soon(prominent: false, help: "Installing a key on a host arrives with the SSH update") {
                    Text("Install on Host…")
                }
                CoreDropdown(
                    items: [
                        CoreDropdownItem("Copy Public Key", symbol: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key.publicKey, forType: .string)
                            model.host.shell.showToast("Public key copied")
                        }
                    ]
                ) {
                    Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .medium)
                        .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                }
                .help("More")
                .accessibilityLabel("More for \(key.name)")
            }
            let used = model.usedBy(key)
            if used.isEmpty {
                Text("Not used by any host yet.").foregroundStyle(GlassInk.secondary)
            } else {
                HStack(spacing: Space.s2) {
                    ForEach(used) { h in CoreChip(h.name, symbol: "server.rack", minWidth: 0) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Used by \(used.map(\.name).joined(separator: ", "))")
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(radius: Radius.cardMac)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("key-card-\(key.name)")
    }
}

/// A pinned host key: its pattern, the host, its short fingerprint and whether it is still the one that was pinned.
struct KnownHostRow: View {
    let known: KnownHostItem

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            FingerprintPattern(fingerprint: known.fingerprint)
            VStack(alignment: .leading, spacing: 0) {
                Text(known.host).lineLimit(1)
                Text(FingerprintPattern.short(known.fingerprint))
                    .coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            switch known.state {
            case .trusted: StateBadge("Trusted", tone: .done, symbol: "checkmark.circle")
            case .changed: StateBadge("Changed · review", tone: .warn, symbol: "exclamationmark.triangle")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

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

    static func openImport(_ m: LeylineModel) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "key-import", onClose: { [weak m] in m?.clearWriteError() }) {
                ImportKeySheet(model: m) { shell.closeDialog() }
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

/// Import…: an OpenSSH private key, and its passphrase when it has one. It is sent once, sealed by the Core and never shown
/// again; this sheet drops it the moment it closes. Touch ID first.
struct ImportKeySheet: View {
    let model: LeylineModel
    let close: () -> Void
    @State private var name = ""
    @State private var pem = ""
    @State private var passphrase = ""
    @Environment(\.corePalette) private var palette

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Import Key", line: "Needs Touch ID.")
                CoreTextField("Name", placeholder: "ops-personal", text: $name, autofocus: true)
                CoreTextArea(
                    "Private key", placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", text: $pem,
                    error: model.writeError, size: MacTextSize.meta, minHeight: Space.s8 * 3, design: .monospaced
                )
                CoreSecureField("Passphrase", placeholder: "Only for an encrypted key", text: $passphrase)
                Text(
                    "The key is sent once and sealed in the Core. It cannot be shown again. RSA keys are not accepted."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Import", key: .primary, run: bring), busy: model.busy,
                    enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !pem.isEmpty)
            }
        }
        .onChange(of: pem) { _, _ in model.clearWriteError() }
        .onDisappear {
            pem = ""
            passphrase = ""
        }
        .accessibilityIdentifier("key-import")
    }

    private func bring() {
        guard !model.busy else { return }
        Task { await model.importKey(name: name, privateKey: pem, passphrase: passphrase) }
    }
}
