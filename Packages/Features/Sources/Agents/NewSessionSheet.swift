import CoreUI
import SwiftUI

/// New agent session: what the API takes (harness, policy mode, runner, model, prompt, secrets). The Core refuses a runner that
/// cannot run it, and the refusal shows here in place.
struct NewSessionSheet: View {
    @Bindable var model: AgentsModel
    @State private var harness = "claude"
    @State private var source = SessionSource.harness
    @State private var chainID: Int64?
    @State private var agentID = ""
    @State private var mode = "ask"
    @State private var runnerID: String?
    @State private var llm = ""
    @State private var prompt = ""
    @State private var secrets: [String] = []
    @State private var secretDraft = ""
    @State private var notice: InlineNotice?
    @State private var busy = false
    @Environment(\.corePalette) private var palette
    @FocusState private var promptFocus: Bool
    @FocusState private var runnerFocus: String?

    private var runner: RunnerInfo? { model.runners.first { $0.id == (runnerID ?? "") } }
    private var chain: ChainOption? { model.chains.first { $0.id == chainID } ?? model.defaultChain }
    private var agentOK: Bool { SessionSource.validAgent(agentID.trimmingCharacters(in: .whitespaces)) }
    private var sourceOK: Bool {
        switch source {
        case .harness: true
        case .chain: chain != nil
        case .agent: agentOK
        }
    }
    private var ready: Bool {
        runner != nil && sourceOK && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
            && !PromptSize.over(prompt)
    }

    var body: some View {
        CoreDialogPanel("New agent session", width: Space.s8 * 17) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("It runs on a runner of the Home Core. You can close this Mac and it keeps going.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    if let notice { NoticeBanner(notice: notice) }
                    VStack(alignment: .leading, spacing: Space.s3) {
                        if !model.chains.isEmpty { sourceFields }
                        if source == .harness {
                            field("Harness") {
                                CoreSegmented(
                                    "Harness",
                                    segments: ["claude", "codex", "opencode", "agy"].map {
                                        CoreSegment($0, AgentWords.harnessName($0))
                                    },
                                    selection: $harness)
                            }
                        }
                        field("What it may do") {
                            CoreSegmented(
                                "What it may do",
                                segments: SessionMode.all.map { CoreSegment($0, SessionMode.words($0)) },
                                selection: $mode)
                        }
                    }
                    if mode == "sandboxed" {
                        Text("Sandboxed needs the admin scope; the Core refuses it otherwise.").foregroundStyle(
                            palette.text2)
                    } else {
                        Text(SessionMode.help(mode)).coreFont(size: MacTextSize.meta).foregroundStyle(
                            palette.text2)
                    }
                    field("Runner") { runnerList }
                    if source == .harness {
                        CoreTextField("Model (optional)", placeholder: "the harness default", text: $llm, mono: true)
                    }
                    field("Prompt") { promptField }
                    field("Secrets to pass  \(secrets.count) of 16") { secretsField }
                }
                .padding(.bottom, Space.s1)
            }
            .frame(maxHeight: Space.s8 * 20)
            preview
            Text("Starting needs Touch ID.").foregroundStyle(palette.text2)
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.shell.closeDialog() },
                primary: CoreAction(busy ? "Starting…" : notice == nil ? "Start session" : "Try again", key: nil) {
                    if ready { start() }
                }, busy: busy
            )
            .opacity(ready || busy ? 1 : 0.7)
            .help("Start the session (⌘Return)")
            .background {
                Button("") { if ready { start() } }.keyboardShortcut(.return, modifiers: .command).opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            #if DEBUG
            if let d = model.debugSource {
                source = d == "agent" ? .agent : .chain
                if d == "agent" { agentID = "atlas" }
                if d == "busy" {
                    notice = InlineNotice(
                        title: AgentsModel.refusal("runner_busy"),
                        detail: "mac-studio has no free slot. \(AgentsModel.fix("runner_busy"))")
                }
            }
            #endif
            pickRunner()
            if let d = model.draftChain {
                chainID = d
                if !model.chains.isEmpty { source = .chain }
                model.draftChain = nil
            }
            if prompt.isEmpty, !model.draftPrompt.isEmpty {
                prompt = model.draftPrompt
                model.draftPrompt = ""
            }
        }
        .task {
            // The prompt is the one thing to type here; focus it once the sheet is on screen.
            try? await Task.sleep(for: .milliseconds(250))
            promptFocus = true
        }
        .onChange(of: model.runners) { _, _ in pickRunner() }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreFieldLabel(label)
            content()
        }
    }

    /// Where the account comes from: a harness (a plain session), a chain, or an agent whose chain serves it. Chains are
    /// admin only, so a device that was given none sees no choice here.
    @ViewBuilder
    private var sourceFields: some View {
        field("Run from") {
            CoreSegmented(
                "Run from", segments: SessionSource.allCases.map { CoreSegment($0, $0.title) }, selection: $source)
        }
        switch source {
        case .harness: EmptyView()
        case .chain:
            CoreSelect(
                "Chain",
                selection: Binding(get: { chain?.id ?? 0 }, set: { chainID = $0 }),
                options: model.chains.map { CoreSelectOption($0.id, $0.name, note: $0.isDefault ? "default" : nil) })
            if let chain {
                Text("Tries, in order: \(chain.steps.joined(separator: ", then ")). It sets the harness and model.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .agent:
            if model.agentNames.isEmpty {
                CoreTextField(
                    "Agent id", placeholder: "atlas", text: $agentID,
                    error: agentID.isEmpty || agentOK ? nil : SessionSource.idRule, mono: true)
            } else {
                CoreSelect(
                    "Agent",
                    selection: Binding(
                        get: { model.agentNames.contains(agentID) ? agentID : model.agentNames[0] },
                        set: { agentID = $0 }),
                    options: model.agentNames.map { CoreSelectOption($0, $0) }
                )
                .onAppear { if agentID.isEmpty { agentID = model.agentNames[0] } }
            }
            HStack(spacing: Space.s2) {
                Text("The chain bound to this agent serves the session, else the default chain.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Agents and chains") {
                    model.shell.closeDialog()
                    model.openChainBinding()
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .help("Settings, Agents and chains: bind an agent to a chain")
            }
        }
    }

    private func pickRunner() {
        if runner == nil {
            // Asked for one runner (the runner page's Start an agent here): wait for the list if it is not loaded yet.
            if let want = model.newSessionRunner, !model.runners.contains(where: { $0.id == want }) { return }
            runnerID =
                model.newSessionRunner
                ?? (model.runners.first { $0.online && $0.runsAgents } ?? model.runners.first { $0.online })?.id
        }
    }

    @ViewBuilder
    private var runnerList: some View {
        if model.runners.isEmpty {
            Text("No runner is paired yet. Add one from Settings, Devices.").foregroundStyle(palette.text2)
        } else {
            VStack(spacing: Space.s1) {
                ForEach(model.runners) { r in
                    AgentRowButton(id: r.id, focus: $runnerFocus, selected: runnerID == r.id) {
                        runnerID = r.id
                        notice = nil
                    } label: {
                        RunnerRow(runner: r, chosen: runnerID == r.id)
                    }
                    .accessibilityLabel("\(r.name), \(r.online ? "online" : "offline")")
                    .accessibilityAddTraits(runnerID == r.id ? .isSelected : [])
                }
            }
        }
    }

    /// What pressing Start will do, in one line, from what is chosen. No number here is invented: it is the harness, the runner
    /// and the options picked.
    private var preview: some View {
        let what =
            switch source {
            case .harness: AgentWords.harnessName(harness)
            case .chain: "chain \(chain?.name ?? "")"
            case .agent: "\(agentID.trimmingCharacters(in: .whitespaces)) on its chain"
            }
        let words = runner.map { "\(what) on \($0.name)" } ?? "Choose a runner to start on"
        let options = [
            SessionMode.words(mode), llm.isEmpty || source != .harness ? nil : llm,
            secrets.isEmpty ? nil : "\(secrets.count) secret\(secrets.count == 1 ? "" : "s")",
        ]
        .compactMap { $0 }
        return VStack(alignment: .leading, spacing: Space.s1) {
            Text(runner == nil ? words : "This will run \(words)").coreFont(
                size: MacTextSize.headline, weight: .semibold)
            HStack(spacing: Space.s1) {
                ForEach(options, id: \.self) { o in
                    Text(o).coreFont(size: MacTextSize.meta, design: .monospaced)
                        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                        .background(palette.uDim, in: coreShape(Radius.chip))
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }

    private var promptField: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            promptEditor
            if let w = PromptSize.words(prompt) {
                Text(w).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(PromptSize.over(prompt) ? GlassInk.redInk : palette.text2)
            }
        }
    }

    private var promptEditor: some View {
        CoreTextArea(
            nil, placeholder: "What should the agent do?", text: $prompt, minHeight: Space.s8 * 3,
            focus: $promptFocus
        )
        .accessibilityLabel("Prompt")
    }

    private var secretsField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !secrets.isEmpty {
                HStack(spacing: Space.s1) {
                    ForEach(secrets, id: \.self) { s in
                        HStack(spacing: Space.s1) {
                            Text(s).coreFont(size: MacTextSize.meta, design: .monospaced)
                            Button {
                                secrets.removeAll { $0 == s }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain).accessibilityLabel("Remove \(s)")
                        }
                        .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                        .background(palette.uDim, in: coreShape(Radius.chip))
                    }
                    Spacer(minLength: 0)
                }
            }
            CoreTextField("Add a secret by name", placeholder: "GH_TOKEN", text: $secretDraft, mono: true) {
                addSecret()
            }
            .disabled(secrets.count >= 16)
            Text(
                "Any secret you pass can be read by the agent in that session. Each is leased to the runner at every start."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).fixedSize(
                horizontal: false, vertical: true)
        }
    }

    private func addSecret() {
        let s = secretDraft.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !secrets.contains(s), secrets.count < 16 else { return }
        secrets.append(s)
        secretDraft = ""
    }

    private func start() {
        guard let runner else { return }
        busy = true
        notice = nil
        let new = NewAgentSession(
            runner: runner.id, harness: harness, model: llm.isEmpty ? nil : llm, prompt: prompt, mode: mode,
            secrets: secrets, chain: source == .chain ? chain?.id : nil,
            agent: source == .agent ? agentID.trimmingCharacters(in: .whitespaces) : nil)
        Task {
            let n = await model.create(new)
            busy = false
            if let n { notice = n } else { model.shell.closeDialog() }
        }
    }
}

/// A runner to pick: its name, how busy it is, and whether it is there.
private struct RunnerRow: View {
    let runner: RunnerInfo
    let chosen: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: chosen ? "checkmark.square.fill" : "square")
                .foregroundStyle(chosen ? palette.primary : palette.text2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(runner.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
            if runner.online, let cap = runner.capacity { CoreSlots(used: runner.load, capacity: cap) }
            StateBadge(label, tone: tone, symbol: symbol)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(coreShape(Radius.control))
    }

    private var label: String { runner.online ? (runner.degraded ? "Degraded" : "Online") : "Offline" }
    private var tone: Tone { runner.online ? (runner.degraded ? .warn : .run) : .queue }
    private var symbol: String { runner.online ? "checkmark.circle" : "wifi.slash" }

    private var detail: String {
        var parts = ["\(runner.load) of \(runner.capacity.map(String.init) ?? "?") in use"]
        if !runner.drivers.isEmpty { parts.append(runner.runsAgents ? "runs agents" : "no agent driver") }
        return parts.joined(separator: " · ")
    }
}

/// The Core takes a prompt up to 64 KiB.
enum PromptSize {
    static let limit = 64 * 1024
    static func bytes(_ s: String) -> Int { s.utf8.count }
    static func over(_ s: String) -> Bool { bytes(s) > limit }
    /// Nil until the prompt nears the limit.
    static func words(_ s: String) -> String? { AgentWords.promptSizeWords(bytes: bytes(s), limit: limit) }
}

/// Where a new session's account comes from. The API takes a harness (plain), a chain's id, or an agent id; it takes no pool
/// of its own, so a pool is reached through the chain that lists it.
enum SessionSource: String, CaseIterable, Sendable {
    case harness, chain, agent
    var title: String {
        switch self {
        case .harness: "Harness"
        case .chain: "Chain"
        case .agent: "Agent"
        }
    }
    static let idRule = "Use 1 to 64 letters, digits, dots, dashes, colons or underscores."
    /// The Core's rule for an agent id: 1 to 64 of `[A-Za-z0-9._:-]`.
    static func validAgent(_ s: String) -> Bool {
        guard (1...64).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || "._:-".unicodeScalars.contains($0)
        }
    }
}

/// Policy modes in plain words.
enum SessionMode {
    static let all = ["ask", "accept_edits", "sandboxed"]
    static func words(_ mode: String) -> String {
        switch mode {
        case "ask": "Asks first"
        case "sandboxed": "Sandboxed"
        default: "Accepts edits"
        }
    }
    static func help(_ mode: String) -> String {
        switch mode {
        case "ask": "Asks you before each tool call that changes something."
        case "sandboxed": "Runs in a sandbox and asks for nothing. Needs the admin scope."
        default: "Edits files without asking; still asks before running commands."
        }
    }
}
