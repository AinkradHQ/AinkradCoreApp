import Admin
import AppKit
import CoreUI
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// Add Host: Server (paste a whole `ssh` line into Host and the rest fills in) → Sign in (a saved key, an imported one, or
/// a password typed in the terminal) → Name (and a project) → Check (reach it, then save, then trust its host key). The
/// look of the Connections dialog: a step path, a stage that slides, a checklist, a done picture.
struct AddHostWizard: View {
    let model: LeylineModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    @MainActor static func open(_ m: LeylineModel) {
        m.wizard = AddHostFlow()
        m.clearWriteError()
        m.host.shell.present(
            ShellDialog(id: "host-add", onClose: { [weak m] in m?.wizard = nil }) { AddHostWizard(model: m) })
    }

    private var f: AddHostFlow { model.wizard ?? AddHostFlow() }
    private func set(_ change: (inout AddHostFlow) -> Void) {
        guard var w = model.wizard else { return }
        change(&w)
        model.wizard = w
    }
    private func close() { model.host.shell.closeDialog() }

    var body: some View {
        CoreDialogPanel("", width: 620) {
            VStack(spacing: Space.s5) {
                StepPath(at: f.step)
                stage.id(f.step).transition(reduce ? .opacity : .opacity.combined(with: .offset(x: Space.s6)))
                if let e = model.writeError { CoreFieldError(e).frame(maxWidth: .infinity, alignment: .leading) }
                footer
            }
        }
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: f.step)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: f)
        .accessibilityIdentifier("host-add-wizard")
    }

    private func head(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var stage: some View {
        switch f.step {
        case .server: server
        case .signIn: signIn
        case .name: naming
        case .check: check
        }
    }

    // MARK: 1. Server

    private var server: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("Which server?", "Paste a whole ssh user@host -p 22 into Host and the rest fills in.")
                .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: Space.s2 + 2) {
                CoreTextField("User", placeholder: "deploy", text: bind(\.user)).frame(maxWidth: .infinity)
                CoreTextField(
                    "Host or IP", placeholder: "203.0.113.10",
                    text: Binding(get: { f.host }, set: { v in set { $0.setHost(v) } }), autofocus: true,
                    onSubmit: next
                )
                .frame(maxWidth: .infinity).layoutPriority(1).frame(minWidth: Space.s8 * 8)
                .accessibilityIdentifier("add-host-field")
                CoreTextField("Port", placeholder: "22", text: bind(\.port)).frame(width: Space.s8 * 3)
            }
            CoreSelect(
                "Reach it",
                selection: Binding(get: { f.jump ?? "" }, set: { v in set { $0.jump = v.isEmpty ? nil : v } }),
                options: [CoreSelectOption("", "Directly")]
                    + model.hosts.map { CoreSelectOption($0.id, "Through \($0.name)") })
        }
    }

    // MARK: 2. Sign in

    private var signIn: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("How does \(f.user) sign in?", "Fill what this server uses. Keys are kept sealed on your Core.")
                .frame(maxWidth: .infinity)
            if model.previewGaps {
                CoreSecureField(
                    "Password · if it has one", placeholder: "Leave empty if it signs in with a key",
                    text: bind(\.password))
            }
            CoreFieldLabel("Key · if it needs one")
            VStack(spacing: Space.s1 + 2) {
                KeyOption(
                    symbol: "lock", title: "No key",
                    line: model.previewGaps ? "Password only" : "Type the password in the terminal",
                    on: f.key == .none
                ) { set { $0.key = .none } }
                ForEach(model.keys) { k in
                    let n = model.usedBy(k).count
                    KeyOption(
                        symbol: "key", title: k.name, line: "\(k.typeWord) · used on \(Words.count(n, "host"))",
                        on: f.key == .saved(k.id)
                    ) { set { $0.key = .saved(k.id) } }
                }
                KeyOption(
                    symbol: "square.and.arrow.down", title: "Import a key", line: "From a file or pasted text",
                    on: f.key == .importing
                ) { set { $0.key = .importing } }
            }
            if f.key == .importing { importer }
        }
    }

    @ViewBuilder private var importer: some View {
        CoreSegmented(
            "Import from",
            segments: [CoreSegment(AddHostFlow.ImportFrom.file, "From a file"), CoreSegment(.text, "Paste text")],
            selection: bind(\.importFrom)
        )
        .fixedSize()
        if f.importFrom == .text {
            CoreTextArea(
                nil, placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", text: bind(\.keyText), size: MacTextSize.meta,
                minHeight: Space.s8 * 3, design: .monospaced)
        } else {
            DropZone(
                file: f.keyFile,
                read: { name, text in
                    set {
                        $0.keyFile = name
                        $0.keyText = text
                    }
                })
        }
        if AddHostFlow.needsPassphrase(f.keyText) {
            CoreSecureField("Passphrase", placeholder: "The key’s passphrase, asked once", text: bind(\.passphrase))
        }
        Label("If the key has a passphrase, Leyline asks for it once.", systemImage: "checkmark.shield")
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
    }

    // MARK: 3. Name

    private var naming: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("Name it", "How it shows on the map and in the list.").frame(maxWidth: .infinity)
            CoreTextField(
                "Name", placeholder: "web-1",
                text: Binding(
                    get: { f.name },
                    set: { v in
                        set {
                            $0.name = v
                            $0.nameTouched = true
                        }
                    }),
                autofocus: true, onSubmit: next)
            CoreSelect(
                "Project · if it belongs to one",
                selection: Binding(get: { f.project ?? "" }, set: { v in set { $0.project = v.isEmpty ? nil : v } }),
                options: [CoreSelectOption("", "None")] + projects.map { CoreSelectOption($0, $0) })
        }
    }

    /// The Core's projects and the groups hosts already use, A to Z.
    private var projects: [String] {
        Array(Set((model.projectNames?() ?? []) + model.hosts.compactMap(\.group))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    // MARK: 4. Check

    private var check: some View {
        VStack(spacing: Space.s3) {
            if f.finished {
                DonePicture()
                head(
                    "\(f.made?.name ?? f.name) is added",
                    "\(f.project ?? "No project") · AI asks you before running anything.")
            } else {
                head("Checking it works", "Nothing is saved until it answers.")
            }
            VStack(spacing: Space.s1 + 2) {
                CheckLine(
                    index: 1, title: "Reach \(f.host):\(f.port)",
                    line: f.jump.flatMap { model.hostItem($0)?.name }.map { "through \($0)" } ?? "from your Core",
                    mark: f.reach)
                if model.previewGaps || f.key == .importing {
                    CheckLine(
                        index: 2, title: model.previewGaps ? "Sign in as \(f.user)" : "Seal the key in your Core",
                        line: keyLine, mark: f.signIn)
                }
                if let fp = fingerprint {
                    CheckLine(
                        index: model.previewGaps || f.key == .importing ? 3 : 2, title: "Trust the host key",
                        line: "ED25519 · \(FingerprintPattern.short(fp))", mark: f.hostKey,
                        trust: { Task { await model.trustNewHostKey() } }
                    ) {
                        if case .asks = f.hostKey {
                            HStack(spacing: Space.s3) {
                                FingerprintPattern(fingerprint: fp, cell: 9)
                                Text("First time we meet it. If you know its fingerprint, compare it.")
                                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, Space.s2)
                        }
                    }
                }
            }
            if running { CoreBusyBar().frame(width: Space.s8 * 6) }
        }
        .task(id: f.step) { if f.step == .check, f.reach == .waiting { await model.runAddCheck() } }
    }

    private var running: Bool { f.reach == .running || f.signIn == .running || f.hostKey == .running }

    private var fingerprint: String? {
        if case .asks(let fp) = f.hostKey { return fp }
        return f.trusted
    }

    private var keyLine: String {
        switch f.key {
        case .none: "with the password"
        case .saved(let id): "with \(model.key(id)?.name ?? "the key")"
        case .importing: "with the imported key"
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: Space.s2) {
            if f.finished {
                Button("Add Another") { set { $0 = AddHostFlow() } }.buttonStyle(CoreButtonStyle(.secondary))
            } else {
                Button("Cancel", action: close).buttonStyle(CoreButtonStyle(.plain)).coreShortcut(.cancel)
                if f.step != .server, f.made == nil {
                    Button("Back") { set { $0.back() } }.buttonStyle(CoreButtonStyle(.plain))
                }
            }
            Spacer(minLength: Space.s3)
            if f.finished {
                Button("Open Terminal") {
                    guard let id = f.made?.id else { return }
                    close()
                    model.openHost(id)
                }
                .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.primary)
                .accessibilityIdentifier("add-host-open-terminal")
            } else if case .failed = f.reach, f.step == .check {
                Button("Try Again") { set { $0.reach = .waiting } }.buttonStyle(CoreButtonStyle(.secondary))
                    .coreShortcut(.primary)
            } else if case .asks = f.hostKey {
                Button("Trust It") { Task { await model.trustNewHostKey() } }.buttonStyle(CoreButtonStyle(.secondary))
                    .coreShortcut(.primary)
            } else if f.step != .check {
                Button(f.step == .name ? "Add and Check" : "Continue", action: next)
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.primary).disabled(!f.canContinue)
                    .accessibilityIdentifier("add-host-continue")
            }
        }
    }

    private func next() {
        model.clearWriteError()
        set { $0.next() }
    }

    private func bind<T>(_ path: WritableKeyPath<AddHostFlow, T>) -> Binding<T> {
        Binding(get: { f[keyPath: path] }, set: { v in set { $0[keyPath: path] = v } })
    }
}

// MARK: running the check

extension LeylineModel {
    /// Reach → (seal the imported key) → save → the host key. Nothing is saved until the host answers; a host behind a jump
    /// host is not reachable from the Core alone, so its reach is taken on trust and the first terminal proves it.
    func runAddCheck() async {
        guard let service, let f = wizard, f.made == nil else { return }
        clearWriteError()
        wizard?.reach = .running
        if f.jump == nil, let port = f.portNumber {
            do {
                let c = try await service.checkHost(address: f.host, port: port)
                guard c.ok else {
                    let why = c.reason ?? "it did not answer"
                    wizard?.reach = .failed(why.prefix(1).uppercased() + why.dropFirst())
                    return
                }
                wizard?.reach = .done(c.ms.map { "\($0) ms" })
            } catch let e as LeylineFailure where e.isMissing {
                wizard?.reach = .done(nil)  // an older Core cannot check before saving
            } catch {
                wizard?.reach = .failed(words(error))
                return
            }
        } else {
            wizard?.reach = .done(nil)
        }
        var keyID: String?
        switch f.key {
        case .none: break
        case .saved(let id): keyID = id
        case .importing:
            wizard?.signIn = .running
            do {
                let k = try await host.elevated(
                    "Import the key \(f.importName) into the Core.", done: "imported", keepsEdit: true
                ) {
                    try await service.importKey(
                        name: f.importName, privateKey: f.keyText, passphrase: f.passphrase.isEmpty ? nil : f.passphrase
                    )
                }
                keyID = k.id
            } catch is AdminDeclined {
                wizard?.signIn = .failed("The key needs Touch ID to be sealed in the Core.")
                return
            } catch {
                wizard?.signIn = .failed(words(error))
                return
            }
        }
        guard let made = await createHost(f.draft(keyID: keyID)) else {
            wizard?.reach = .failed(writeError ?? "The Core did not save it.")
            clearWriteError()
            return
        }
        wizard?.signIn = .done(previewGaps ? "Signed in" : nil)
        wizard?.made = made
        wizard?.hostKey = .running
        let keys = (try? await service.hostKeys(host: made.id)) ?? []
        if let seen = keys.first(where: { $0.state == "seen" }), !keys.contains(where: { $0.state == "trusted" }) {
            wizard?.hostKey = .asks(seen.fingerprint)
        } else {
            wizard?.hostKey = .done(nil)
        }
    }

    /// Trust It: a person trusts the key the host offered.
    func trustNewHostKey() async {
        guard let service, let f = wizard, let made = f.made, case .asks(let fp) = f.hostKey else { return }
        do {
            try await service.trustHostKey(host: made.id, fingerprint: fp)
            wizard?.trusted = fp
            wizard?.hostKey = .done(nil)
        } catch { setWriteError(words(error)) }
    }
}
