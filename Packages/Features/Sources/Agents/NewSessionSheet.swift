import CoreUI
import SwiftUI

/// New AI session (advanced): tool, runner, model, where it works (fresh folder, an existing folder, or a repo and branch) and the
/// order of accounts. No first message is needed: the session opens live and waits, like the CLI. The Core refuses a runner that
/// cannot run it, and the refusal shows here in place.
struct NewSessionSheet: View {
    @Bindable var model: AgentsModel
    @State private var harness = AgentPrefs.shared.harness
    @State private var mode = AgentPrefs.shared.mode
    @State private var runnerID: String?
    @State private var llm = ""
    @State private var place = Place.fresh
    @State private var folder = ""
    @State private var repo = ""
    @State private var branch = ""
    @State private var base = ""
    @State private var chainID: Int64?
    @State private var notice: InlineNotice?
    @State private var busy = false
    @Environment(\.corePalette) private var palette

    enum Place: String, CaseIterable, Sendable { case fresh, folder, repo }

    private var runner: RunnerInfo? { model.runners.first { $0.id == (runnerID ?? "") } }
    private var chain: ChainOption? { model.chains.first { $0.id == chainID } ?? model.defaultChain }
    private var placeOK: Bool {
        switch place {
        case .fresh: true
        case .folder: !folder.trimmingCharacters(in: .whitespaces).isEmpty
        case .repo: !repo.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    private var ready: Bool { runner != nil && placeOK && !busy }

    var body: some View {
        CoreDialogPanel("New AI session (advanced)", width: Space.s8 * 17) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("No first message needed. The session opens and waits for you, on a runner of the Home Core.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    if let notice { NoticeBanner(notice: notice) }
                    field("Tool") {
                        HStack(spacing: Space.s2) {
                            ForEach(["claude", "codex", "opencode", "agy"], id: \.self) { t in toolTile(t) }
                        }
                    }
                    HStack(alignment: .top, spacing: Space.s3) {
                        field("Runner") {
                            CoreSelect(
                                "Runner", selection: Binding(get: { runnerID ?? "" }, set: { runnerID = $0 }),
                                options: model.runners.map {
                                    CoreSelectOption($0.id, $0.name, note: $0.online ? nil : "offline")
                                })
                            Text(runnerLine).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                        VStack(alignment: .leading, spacing: Space.s1) {
                            CoreTextField(
                                "Model", placeholder: "Default for \(AgentWords.toolName(harness))", text: $llm,
                                mono: true)
                            Text("You can change it later with /model.").coreFont(size: MacTextSize.meta)
                                .foregroundStyle(palette.text2)
                        }
                    }
                    field("Where it works") {
                        CoreSegmented(
                            "Where it works",
                            segments: [
                                CoreSegment(Place.fresh, "Fresh folder"), CoreSegment(Place.folder, "Existing folder"),
                                CoreSegment(Place.repo, "Repo and branch"),
                            ], selection: $place)
                        switch place {
                        case .fresh: EmptyView()
                        case .folder:
                            CoreTextField("Folder", placeholder: "/path/on/the/runner", text: $folder, mono: true)
                            CoreTextField("Start from", placeholder: "main", text: $base, mono: true)
                            Text("The folder must be a git repo. The session works in its own copy of it.")
                                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        case .repo:
                            HStack(spacing: Space.s3) {
                                CoreTextField("Repository", placeholder: "AinkradCore", text: $repo, mono: true)
                                CoreTextField("Branch", placeholder: "feat/my-branch", text: $branch, mono: true)
                            }
                            CoreTextField("Start from", placeholder: "main", text: $base, mono: true)
                            Text("Works in its own copy of the repo on the runner, so your branch stays as it is.")
                                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                    }
                    if !model.chains.isEmpty {
                        field("Accounts, tried in this order") {
                            CoreSelect(
                                "Order", selection: Binding(get: { chain?.id ?? 0 }, set: { chainID = $0 }),
                                options: model.chains.map {
                                    CoreSelectOption($0.id, $0.name, note: $0.isDefault ? "default" : nil)
                                })
                            if let chain {
                                Text(
                                    chain.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(
                                        separator: "   ")
                                )
                                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    field("What it may do") {
                        CoreSegmented(
                            "What it may do", segments: SessionMode.all.map { CoreSegment($0, SessionMode.words($0)) },
                            selection: $mode)
                        Text(SessionMode.help(mode)).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                }
                .padding(.bottom, Space.s1)
            }
            .frame(maxHeight: Space.s8 * 20)
            Text("Starting needs Touch ID.").foregroundStyle(palette.text2)
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.shell.closeDialog() },
                primary: CoreAction(busy ? "Starting…" : notice == nil ? "Start AI session" : "Try again", key: nil) {
                    if ready { start() }
                }, busy: busy
            )
            .opacity(ready || busy ? 1 : 0.7)
            .help("Start the AI session (⌘Return)")
            .background {
                Button("") { if ready { start() } }.keyboardShortcut(.return, modifiers: .command).opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { pickRunner() }
        .onChange(of: model.runners) { _, _ in pickRunner() }
    }

    private var runnerLine: String {
        guard let r = runner else { return "Choose a runner." }
        return r.online
            ? "Online, \(r.load) AI session\(r.load == 1 ? "" : "s") running"
            : "Offline. Pick another, or bring it back online."
    }

    private func toolTile(_ t: String) -> some View {
        let on = harness == t
        let n = model.runners.filter { $0.online && $0.runsAgents }.count
        return Button {
            harness = t
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(AgentWords.toolName(t)).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(n == 0 ? "No runner offers it" : "On \(n) runner\(n == 1 ? "" : "s")")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? GlassInk.blue.opacity(0.22) : GlassInk.well, in: coreShape(Radius.control))
            .overlay {
                coreShape(Radius.control).strokeBorder(on ? GlassInk.blue : GlassInk.wellEdge, lineWidth: on ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreFieldLabel(label)
            content()
        }
    }

    private func pickRunner() {
        if runner == nil {
            // Asked for one runner (the runner page's start button): wait for the list if it is not loaded yet.
            if let want = model.newSessionRunner, !model.runners.contains(where: { $0.id == want }) { return }
            runnerID =
                model.newSessionRunner
                ?? (model.runners.first { $0.online && $0.runsAgents } ?? model.runners.first { $0.online })?.id
        }
    }

    private func start() {
        guard let runner else { return }
        busy = true
        notice = nil
        let project: String? =
            switch place {
            case .fresh: nil
            case .folder: folder.trimmingCharacters(in: .whitespaces)
            case .repo: repo.trimmingCharacters(in: .whitespaces)
            }
        let new = NewAgentSession(
            runner: runner.id, harness: harness, model: llm.isEmpty ? nil : llm, prompt: "", mode: mode,
            chain: chain?.id, project: project, branch: place == .repo && !branch.isEmpty ? branch : nil,
            base: base.trimmingCharacters(in: .whitespaces))
        Task {
            let n = await model.create(new)
            busy = false
            if let n { notice = n } else { model.shell.closeDialog() }
        }
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
        case .agent: "AI session"
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
