import AppKit
import CoreUI
import SwiftUI

/// Generate, inline in the Keys panel: a name already filled ("key-1"), the type, and Generate. Return makes it, Esc closes
/// the form. The Core makes the key and keeps the private half; Touch ID first.
struct GenerateKeyForm: View {
    @Bindable var model: LeylineModel

    private var rsa: Bool { model.keyDraft.type == "rsa" }
    private var ready: Bool { !rsa && !model.keyDraft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreTextField(
                "Name", placeholder: "key-1", text: $model.keyDraft.name, error: model.writeError, autofocus: true,
                onSubmit: make
            )
            .accessibilityIdentifier("key-generate-name")
            CoreSegmented(
                "Type",
                segments: [
                    CoreSegment("ed25519", "ed25519", symbol: "checkmark.shield"),
                    CoreSegment("rsa", "RSA 4096", symbol: "key"),
                ], selection: $model.keyDraft.type, fill: true
            )
            .accessibilityIdentifier("key-generate-type")
            if rsa {
                // The Core makes ed25519 keys only (no RSA generator in it); an RSA key comes in through Import.
                CoreNotice(
                    symbol: "info.circle", title: "The Core makes ed25519 keys",
                    text: "To use an RSA key, import one you already have."
                ) {
                    Button("Import Instead") { model.openKeyForm(.importing) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            } else {
                Text("Recommended: short, fast and strong. Made in your Core; the private half never leaves it.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.closeKeyForm() },
                primary: CoreAction("Generate", key: .primary, run: make), busy: model.busy, enabled: ready)
        }
        .onChange(of: model.keyDraft.name) { _, _ in model.clearWriteError() }
        .onExitCommand { model.closeKeyForm() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generate Key")
        .accessibilityIdentifier("key-generate")
    }

    private func make() {
        guard ready, !model.busy else { return }
        Task { await model.generateKey(name: model.keyDraft.name) }
    }
}

/// Import, inline in the Keys panel: drop a key file (anywhere on the panel), choose one, or paste its text. Once there is
/// a key it shows what it is (type and pattern), a name from the file, and the passphrase field only for an encrypted key.
/// The key text is sent once and sealed by the Core; the form drops it the moment it closes.
struct ImportKeyForm: View {
    @Bindable var model: LeylineModel
    /// A file is being dragged over the panel.
    let dropping: Bool
    @Environment(\.corePalette) private var palette

    private var draft: KeyDraft { model.keyDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if draft.text.isEmpty && !draft.pasting {
                dropArea
            } else if draft.pasting && draft.file == nil {
                CoreTextArea(
                    nil, placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", text: $model.keyDraft.text,
                    size: MacTextSize.meta, minHeight: Space.s8 * 3, maxHeight: Space.s8 * 4, autofocus: true,
                    design: .monospaced
                )
                .accessibilityIdentifier("key-import-text")
                Button("Choose a File Instead") { model.keyDraft.pasting = false }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
            }
            if let kind = draft.detected { found(kind) }
            if case .privateKey(_, let encrypted, _)? = draft.detected {
                CoreTextField(
                    "Name", placeholder: "ops-personal", text: $model.keyDraft.name,
                    error: encrypted ? nil : model.writeError, autofocus: !encrypted, onSubmit: bring)
                if encrypted {
                    CoreSecureField(
                        "Passphrase", placeholder: "The key’s passphrase", text: $model.keyDraft.passphrase,
                        error: model.writeError, autofocus: true, onSubmit: bring
                    )
                    .accessibilityIdentifier("key-import-passphrase")
                }
            }
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.closeKeyForm() },
                primary: model.keyTooWeak
                    ? CoreAction("Make a New Key for Me", key: .primary, run: makeNew)
                    : CoreAction("Import", key: .primary, run: bring),
                busy: model.busy, enabled: ready || model.keyTooWeak)
        }
        .onChange(of: model.keyDraft.text) { _, _ in model.clearWriteError() }
        .onChange(of: model.keyDraft.passphrase) { _, _ in model.clearWriteError() }
        .onExitCommand { model.closeKeyForm() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import Key")
        .accessibilityIdentifier("key-import")
    }

    private var ready: Bool {
        guard case .privateKey? = draft.detected else { return false }
        return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var dropArea: some View {
        VStack(spacing: Space.s2) {
            IconTile("square.and.arrow.down", hue: palette.btnPrimary, size: Space.s8 + Space.s2, bounce: dropping)
            Text(dropping ? "Drop to Import" : "Drop a key file here").coreFont(
                size: MacTextSize.body, weight: .semibold)
            Text("id_ed25519, id_rsa, *.pem · from ~/.ssh").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
            HStack(spacing: Space.s2) {
                Button("Choose File…", action: choose).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .accessibilityIdentifier("key-import-choose")
                Button("Paste Text Instead") { model.keyDraft.pasting = true }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
            }
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .background(dropping ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .animation(Motion.out(Motion.hover), value: dropping)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("key-import-drop")
    }

    /// What the text is: a key's pattern, where it came from, its type and whether it is locked; or why it is not one.
    @ViewBuilder private func found(_ kind: KeyText.Kind) -> some View {
        switch kind {
        case .privateKey(let type, let encrypted, let fp):
            HStack(spacing: Space.s3) {
                if let fp {
                    KeyIdenticon(fingerprint: fp, big: true)
                } else {
                    IconTile("key", hue: palette.btnPrimary, size: Space.s8 + Space.s2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.file ?? "Pasted key").coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        .truncationMode(.middle)
                    Text(
                        [type ?? "Private key", encrypted ? "locked" : nil].compactMap { $0 }
                            .joined(separator: " · ")
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    if let fp {
                        Text(FingerprintPattern.short(fp)).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(GlassInk.secondary).help(fp)
                    }
                }
                Spacer(minLength: Space.s2)
                Button("Change") { model.keyDraft = KeyDraft(name: draft.name) }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Use another key")
            }
            .padding(Space.s3)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("key-import-found")
        case .publicKey:
            CoreFieldError("That is the public half (.pub). Choose the private key, the file next to it without .pub.")
        case .notAKey:
            CoreFieldError("That is not a private key. It starts with -----BEGIN … PRIVATE KEY-----.")
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.message = "Choose a private key: id_ed25519, id_rsa or a .pem file."
        let ssh = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh")
        if FileManager.default.fileExists(atPath: ssh.path) { panel.directoryURL = ssh }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importKeyFile(url)
    }

    private func bring() {
        guard ready, !model.busy else { return }
        Task { await model.importKey(name: draft.name, privateKey: draft.text, passphrase: draft.passphrase) }
    }

    /// The "too weak" way out: a fresh ed25519 key under the same name; the weak one was never stored.
    private func makeNew() {
        guard !model.busy else { return }
        let name = draft.name
        model.keyDraft = KeyDraft(name: name)
        Task { await model.generateKey(name: name) }
    }
}
