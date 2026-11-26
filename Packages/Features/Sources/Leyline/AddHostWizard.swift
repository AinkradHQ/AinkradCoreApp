import Admin
import AppKit
import CoreUI
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// Add Host: Server → Sign in → Name → Check, in the Connections dialog's look. A route at the top builds as you type (the
/// Core, the jump host, `user@host:port`), lights a key on the link at Sign in, and carries the three checks along it.
/// Keyboard first: each step focuses its first field, Return goes on, ⌘[ goes back, Esc cancels; on Sign in ↑ ↓ pick a key,
/// ⌘I imports one and ⌘V pastes one. A failed check says what to fix and "Change …" jumps to that field; nothing typed is
/// lost. Reduce Motion: every move becomes a crossfade.
struct AddHostWizard: View {
    let model: LeylineModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var forward = true

    static let lastKeyDefault = "leyline.lastKey"

    @MainActor static func open(_ m: LeylineModel) {
        var f = AddHostFlow()
        var usage: [String: Int] = [:]
        for k in m.hosts.compactMap(\.keyID) { usage[k, default: 0] += 1 }
        f.key = AddHostFlow.defaultKey(
            keyIDs: m.keys.map(\.id), usage: usage, last: UserDefaults.standard.string(forKey: lastKeyDefault))
        m.wizard = f
        m.clearWriteError()
        m.host.shell.present(
            ShellDialog(id: "host-add", onClose: { [weak m] in m?.wizard = nil }) { AddHostWizard(model: m) })
    }

    var f: AddHostFlow { model.wizard ?? AddHostFlow() }
    func set(_ change: (inout AddHostFlow) -> Void) {
        guard var w = model.wizard else { return }
        change(&w)
        model.wizard = w
    }
    private func close() { model.host.shell.closeDialog() }

    var body: some View {
        CoreDialogPanel("", width: 620) {
            VStack(spacing: Space.s4) {
                StepPath(at: f.step)
                RouteBuild(model: model, flow: f)
                stage.id(f.step)
                    .transition(
                        reduce
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: forward ? Space.s6 : -Space.s6)),
                                removal: .opacity))
                footer
            }
        }
        // The height eases with the step, one timing family for the slide and the size (a fade under Reduce Motion).
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: f.step)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: f.key)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: f.importFrom)
        .onChange(of: f.step) { old, new in forward = new > old }
        .background { shortcuts }
        .accessibilityIdentifier("host-add-wizard")
    }

    /// ⌘I (Import a key) on Sign in. A hidden button carries the shortcut so it works wherever focus is in the dialog.
    @ViewBuilder private var shortcuts: some View {
        if f.step == .signIn {
            Button("Import a Key") { set { $0.key = .importing } }
                .keyboardShortcut("i", modifiers: .command).opacity(0).accessibilityHidden(true)
        }
    }

    func head(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
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

    private func serverField(_ field: AddHostFlow.Field, _ label: String, _ placeholder: String, _ value: String)
        -> some View
    {
        CoreTextField(
            label, placeholder: placeholder,
            text: Binding(get: { value }, set: { v in set { $0.setServer(field, v) } }), error: f.problems[field],
            mono: true, autofocus: f.focus == field, onSubmit: next)
    }

    private var server: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("Which server?", "Paste a whole ssh user@host -p 22 into any field and the rest fills in.")
            HStack(alignment: .top, spacing: Space.s3) {
                // Fixed User and Port, Host takes the rest: a layout priority on Host squeezed User to a sliver.
                serverField(.user, "User", "deploy", f.user).frame(width: Space.s8 * 5)
                serverField(.host, "Host or IP", "203.0.113.10", f.host).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("add-host-field")
                serverField(.port, "Port", "22", f.port).frame(width: Space.s8 * 3)
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
            head("How does \(f.user) sign in?", "Pick what this server takes. Keys stay sealed on your Core.")
            if model.previewGaps {
                CoreSecureField(
                    "Password · if it has one", placeholder: "Leave empty if it signs in with a key",
                    text: bind(\.password))
            }
            KeyList(wizard: self)
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
                nil, placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", text: bind(\.keyText),
                error: f.problems[.keys],
                size: MacTextSize.meta, minHeight: Space.s8 * 3, autofocus: true, design: .monospaced)
        } else {
            DropZone(file: f.keyFile, read: readKey)
            if let e = f.problems[.keys] { CoreFieldError(e) }
        }
        if AddHostFlow.needsPassphrase(f.keyText) {
            CoreSecureField(
                "Passphrase", placeholder: "The key’s passphrase, asked once", text: bind(\.passphrase),
                autofocus: true, onSubmit: next)
        }
    }

    func readKey(_ name: String, _ text: String) {
        set {
            $0.key = .importing
            $0.keyFile = name
            $0.keyText = text
        }
    }

    // MARK: 3. Name

    private var naming: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            head("Name it", "How it shows on the map and in the list.")
            CoreTextField(
                "Name", placeholder: "web-1",
                text: Binding(
                    get: { f.name },
                    set: { v in
                        set {
                            $0.name = v
                            $0.nameTouched = true
                        }
                    }), error: f.problems[.name], autofocus: true, onSubmit: next)
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
                head(
                    "\(f.made?.name ?? f.name) is added",
                    "On the map in \(f.project ?? HostGroup.shared) · AI asks you before running anything.")
            } else if f.failure != nil {
                head("It needs a change", "Nothing was saved. Fix it and the check runs again.")
            } else {
                head("Checking it works", "Nothing is saved until it answers.")
            }
            VStack(spacing: Space.s1 + 2) {
                CheckLine(
                    index: 1, title: "Reach \(f.host):\(f.port)",
                    line: f.reach == .running
                        ? "Knocking from your Core…"
                        : f.jump.flatMap { model.hostItem($0)?.name }.map { "through \($0)" } ?? "from your Core",
                    mark: f.reach)
                if model.previewGaps || f.key == .importing {
                    CheckLine(
                        index: 2, title: model.previewGaps ? "Sign in as \(f.user)" : "Seal the key in your Core",
                        line: f.signIn == .running ? "Signing in…" : keyLine, mark: f.signIn)
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
                if case .save(let why) = f.failure {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: "The Core did not save it", text: why, tone: .warn)
                }
            }
        }
        .task(id: f.step) { if f.step == .check, f.reach == .waiting { await model.runAddCheck() } }
    }

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
                    .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            } else {
                Button("Cancel", action: close).buttonStyle(CoreButtonStyle(.plain)).coreShortcut(.cancel)
                if f.step != .server, f.made == nil {
                    Button("Back") { set { $0.back() } }.buttonStyle(CoreButtonStyle(.plain))
                        .keyboardShortcut("[", modifiers: .command).environment(\.coreKeycap, "⌘[")
                        .accessibilityIdentifier("add-host-back")
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
            } else if let failure = f.failure {
                Button("Try Again") {
                    set { $0.resetCheck() }
                    Task { await model.runAddCheck() }
                }.buttonStyle(CoreButtonStyle(.plain))
                    .keyboardShortcut("r", modifiers: .command).environment(\.coreKeycap, "⌘R")
                Button(AddHostFlow.fix(for: failure).title) { set { $0.applyFix() } }
                    .buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.primary)
                    .accessibilityIdentifier("add-host-fix")
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

    func next() {
        guard f.canContinue else { return }
        model.clearWriteError()
        set { $0.next() }
    }

    func bind<T>(_ path: WritableKeyPath<AddHostFlow, T>) -> Binding<T> {
        Binding(get: { f[keyPath: path] }, set: { v in set { $0[keyPath: path] = v } })
    }
}

// MARK: running the check

extension LeylineModel {
    /// Reach → (seal the imported key) → save → the host key. Nothing is saved until the host answers; a host behind a jump
    /// host is not reachable from the Core alone, so its reach is taken on trust and the first terminal proves it.
    func runAddCheck() async {
        // Once per Check / Try Again, never while typing: the Core takes a few checks a minute, each behind Touch ID.
        guard let service, let f = wizard, f.made == nil, f.reach != .running else { return }
        clearWriteError()
        wizard?.failure = nil
        wizard?.reach = .running
        if f.jump == nil, let port = f.portNumber {
            do {
                // Through the Touch ID helper like every other Leyline action: the Core asks for proof here.
                let c = try await host.elevated("Check and add \(f.host).", done: "checked", keepsEdit: true) {
                    try await service.checkHost(address: f.host, port: port)
                }
                guard c.ok else {
                    let why = c.reason ?? "it did not answer"
                    wizard?.reach = .failed(why.prefix(1).uppercased() + why.dropFirst())
                    wizard?.failure = .reach
                    return
                }
                wizard?.reach = .done(c.ms.map { "\($0) ms" })
            } catch let e as LeylineFailure where e.isMissing {
                wizard?.reach = .done(nil)  // an older Core cannot check before saving
            } catch is AdminDeclined {
                wizard?.reach = .failed("Adding a server needs Touch ID. Try again and confirm it.")
                wizard?.failure = .reach
                return
            } catch {
                wizard?.reach = .failed(words(error))
                wizard?.failure = .reach
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
            // A name another key already has gets a free one ("deploy-2"): the Core refuses a taken name.
            let name = AddHostFlow.freeName(f.importName, taken: Set(keys.map(\.name)))
            do {
                let k = try await host.elevated(
                    "Import the key \(name) into the Core.", done: "imported", keepsEdit: true
                ) {
                    try await service.importKey(
                        name: name, privateKey: f.keyText, passphrase: f.passphrase.isEmpty ? nil : f.passphrase
                    )
                }
                keyID = k.id
                // The key is in the Core's list now, for this and later hosts: a retry uses it, never imports it twice.
                wizard?.key = .saved(k.id)
            } catch is AdminDeclined {
                wizard?.signIn = .failed("The key needs Touch ID to be sealed in the Core.")
                wizard?.failure = .key
                return
            } catch {
                wizard?.signIn = .failed(words(error))
                wizard?.failure = .key
                return
            }
        }
        if let keyID { UserDefaults.standard.set(keyID, forKey: AddHostWizard.lastKeyDefault) }
        guard let made = await createHost(f.draft(keyID: keyID)) else {
            let why = writeError ?? "The Core did not save it."
            if wizard?.signIn == .running { wizard?.signIn = .waiting }
            wizard?.failure = .save(why)
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
