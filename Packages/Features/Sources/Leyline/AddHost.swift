import CoreUI
import Shell
import SwiftUI

/// The dialogs of hosts, shown over the shell like the other apps' dialogs.
@MainActor
enum HostDialogs {
    static func openAdd(_ m: LeylineModel, login: String) {
        m.quickOpen = false
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "host-add", onClose: { [weak m] in m?.clearWriteError() }) {
                HostSheet(model: m, editing: nil, login: login) { shell.closeDialog() }
            })
    }

    static func openEdit(_ m: LeylineModel, _ host: HostItem) {
        m.clearWriteError()
        let shell = m.host.shell
        shell.present(
            ShellDialog(id: "host-edit", onClose: { [weak m] in m?.clearWriteError() }) {
                HostSheet(model: m, editing: host, login: "") { shell.closeDialog() }
            })
    }
}

/// A dialog's own header: the title and one plain line under it (no icon tile).
/// TODO(design-system): proposal CoreDialogHead (Projects has the same private header).
struct DialogHead: View {
    let title: String
    let line: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let line { Text(line).foregroundStyle(palette.text2) }
        }
    }
}

/// ⌘N: a small pop-over under Add Host. `user@address` and Return is all it asks; it says what it will add.
struct QuickAddHost: View {
    let model: LeylineModel
    @Environment(\.corePalette) private var palette

    /// What the Core says when asked whether the typed address answers SSH (API minor 95; nothing on an older Core).
    private enum Answer: Equatable {
        case idle, checking
        case ok(Int)
        case failed(String)
    }
    @State private var answer = Answer.idle

    private var typed: Bool { !model.quickText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var login: HostRules.Login? { HostRules.login(model.quickText) }
    /// The Core's refusal, else what is wrong with the text (only once something is typed).
    private var problem: String? {
        if let e = model.writeError { return e }
        return typed && login == nil ? "Type it as user@address, like deploy@10.0.0.4." : nil
    }

    @ViewBuilder private var answerLine: some View {
        switch answer {
        case .idle: EmptyView()
        case .checking:
            Label("Checking…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(palette.text2)
        case .ok(let ms):
            Label("\(login?.address ?? "It") answered in \(ms) ms.", systemImage: "checkmark")
                .foregroundStyle(palette.tone(.run).ink)
        case .failed(let why):
            Label(why.prefix(1).uppercased() + why.dropFirst() + ".", systemImage: "exclamationmark.triangle")
                .foregroundStyle(palette.tone(.warn).ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 12) {
            VStack(alignment: .leading, spacing: Space.s3) {
                DialogHead(title: "Add Host", line: nil)
                CoreTextField(
                    "Login", placeholder: "user@address",
                    text: Binding(get: { model.quickText }, set: { model.quickText = $0 }), error: problem, mono: true,
                    autofocus: true, onSubmit: add
                )
                .accessibilityIdentifier("host-quick-login")
                Text(promise).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                answerLine
                CoreDialogFooter(
                    cancel: CoreAction("Advanced…") { HostDialogs.openAdd(model, login: model.quickText) },
                    primary: CoreAction("Add", key: .primary, run: add), busy: model.busy, enabled: login != nil)
            }
        }
        .task(id: login.map { "\($0.address):\($0.port)" }) {
            answer = .idle
            guard let l = login else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            answer = .checking
            do {
                let c = try await model.checkHost(l.address, l.port)
                answer = c.ok ? .ok(c.ms ?? 0) : .failed(c.reason ?? "it did not answer")
            } catch { answer = .idle }
        }
        .onChange(of: model.quickText) { _, _ in model.clearWriteError() }
        .onExitCommand { model.quickOpen = false }
        .accessibilityIdentifier("host-quick")
    }

    private var promise: String {
        guard let l = login else { return "Adds the host. Leyline asks you before AI runs anything on it." }
        return
            "Adds “\(HostRules.label(fromAddress: l.address))” as \(l.username) on port \(l.port). Leyline asks you before AI runs anything on it."
    }

    private func add() {
        guard let l = login, !model.busy else { return }
        Task {
            await model.addHost(
                HostDraft(
                    name: HostRules.label(fromAddress: l.address), address: l.address, username: l.username,
                    port: l.port))
        }
    }
}

/// Advanced… and Change…: every field of a host. With `editing` it saves a change; without, it adds a host. "Allowed" for the AI
/// rule is not here: it is set on the host's Access page, behind Touch ID.
struct HostSheet: View {
    let model: LeylineModel
    let editing: HostItem?
    let close: () -> Void
    @State private var name: String
    @State private var address: String
    @State private var port: String
    @State private var user: String
    @State private var key: String
    @State private var hops: [String]
    @State private var runner: String
    @State private var group: String
    @State private var tags: String
    @State private var rule: AIRule
    @State private var nameTouched: Bool
    @Environment(\.corePalette) private var palette

    init(model: LeylineModel, editing: HostItem?, login: String, close: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.close = close
        let l = HostRules.login(login)
        let h = editing
        _name = State(initialValue: h?.name ?? l.map { HostRules.label(fromAddress: $0.address) } ?? "")
        _address = State(initialValue: h?.address ?? l?.address ?? "")
        _port = State(initialValue: String(h?.port ?? l?.port ?? 22))
        _user = State(initialValue: h?.username ?? l?.username ?? "")
        _key = State(initialValue: h?.keyID ?? "")
        _hops = State(initialValue: (h?.jumpChain ?? []) + Array(repeating: "", count: 3 - (h?.jumpChain.count ?? 0)))
        _runner = State(initialValue: h?.viaRunner ?? "")
        _group = State(initialValue: h?.group ?? "")
        _tags = State(initialValue: h?.tags.joined(separator: ", ") ?? "")
        _rule = State(initialValue: h?.aiRule == .readOnly ? .readOnly : .ask)
        _nameTouched = State(initialValue: h != nil)
    }

    private var draft: HostDraft? {
        guard let p = Int(port), let t = HostRules.tags(tags) else { return nil }
        var seen: [String] = []
        for hop in hops {
            if hop.isEmpty { break }
            if !seen.contains(hop) { seen.append(hop) }
        }
        let g = group.trimmingCharacters(in: .whitespaces)
        return HostDraft(
            name: name.trimmingCharacters(in: .whitespaces), address: address.trimmingCharacters(in: .whitespaces),
            username: user.trimmingCharacters(in: .whitespaces), port: p, keyID: key.isEmpty ? nil : key,
            jumpChain: seen, viaRunner: runner.isEmpty ? nil : runner, group: g.isEmpty ? nil : g, tags: t,
            aiRule: editing.map { $0.aiRule == .allowed ? .allowed : rule } ?? rule)
    }
    private var problem: String? {
        guard let d = draft else {
            return "The port is a number, and tags are letters, digits, dots, dashes and underscores."
        }
        return LeylineModel.problem(d)
    }
    private var ready: Bool { draft != nil && problem == nil }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 20) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: editing == nil ? "Add Host" : "Change Host",
                    line: editing == nil
                        ? "Everything here can be changed later on the host’s Access page."
                        : "Saved in the Core; open terminals keep their current route.")
                HStack(alignment: .top, spacing: Space.s4) {
                    CoreTextField("Name", placeholder: "web-1", text: $name, autofocus: editing == nil)
                    CoreTextField("Group", placeholder: "A project or a group (optional)", text: $group)
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    CoreTextField("Address", placeholder: "10.0.0.4 or web-1.example.com", text: $address, mono: true)
                    CoreTextField("Port", placeholder: "22", text: $port, mono: true).frame(width: Space.s8 * 3)
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    CoreTextField("User", placeholder: "deploy", text: $user, mono: true)
                    CoreSelect("Key", selection: $key, options: keyOptions)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("Jump hosts")
                    HStack(spacing: Space.s2) {
                        ForEach(0..<3, id: \.self) { i in
                            CoreSelect(nil, selection: $hops[i], options: hopOptions(i))
                                .disabled(i > 0 && hops[i - 1].isEmpty)
                        }
                    }
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    // TODO(Y8-01): the runners list; until then a host goes out from the Core, or keeps the runner it has.
                    CoreSelect("Runs from", selection: $runner, options: runnerOptions)
                    CoreTextField("Tags", placeholder: "php, eu-west", text: $tags)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    CoreFieldLabel("AI on this host")
                    CoreSegmented(
                        "AI on this host",
                        segments: [CoreSegment(AIRule.readOnly, "Read-only"), CoreSegment(AIRule.ask, "Ask first")],
                        selection: $rule
                    )
                    .fixedSize().disabled(editing?.aiRule == .allowed)
                    if editing?.aiRule == .allowed {
                        Text("This host is set to Allowed. Change that on its Access page.").coreFont(
                            size: MacTextSize.meta
                        ).foregroundStyle(palette.text2)
                    }
                }
                if let e = model.writeError ?? (touched ? problem : nil) { CoreFieldError(e) }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(editing == nil ? "Add Host" : "Save", key: .primary, run: save),
                    busy: model.busy, enabled: ready)
            }
        }
        .onChange(of: address) { _, new in
            if !nameTouched, editing == nil { name = HostRules.label(fromAddress: new) }
            model.clearWriteError()
        }
        .onChange(of: name) { _, new in
            if new != HostRules.label(fromAddress: address) { nameTouched = true }
            model.clearWriteError()
        }
        .accessibilityIdentifier("host-sheet")
    }

    /// A problem shows once something is typed, not on a fresh form.
    private var touched: Bool { !address.isEmpty || !user.isEmpty }

    private var keyOptions: [CoreSelectOption<String>] {
        [CoreSelectOption("", "None · password")]
            + model.keys.map { CoreSelectOption($0.id, $0.name, note: $0.typeWord) }
    }

    private func hopOptions(_ i: Int) -> [CoreSelectOption<String>] {
        let taken = Set(hops.enumerated().filter { $0.offset != i }.map(\.element))
        return [CoreSelectOption("", i == 0 ? "No jump host" : "No more")]
            + model.hosts.filter { $0.id != editing?.id && !taken.contains($0.id) }.map {
                CoreSelectOption($0.id, $0.name)
            }
    }

    private var runnerOptions: [CoreSelectOption<String>] {
        [CoreSelectOption("", "\(model.coreName) · built in")]
            + (editing?.viaRunner.map { [CoreSelectOption($0, "Runner \($0)")] } ?? [])
    }

    private func save() {
        guard ready, !model.busy, let d = draft else { return }
        if let editing { Task { await model.saveHost(editing.id, d) } } else { Task { await model.addHost(d) } }
    }
}
