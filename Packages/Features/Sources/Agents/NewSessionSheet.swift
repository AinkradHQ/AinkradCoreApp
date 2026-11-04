import CoreUI
import SwiftUI

/// The surface dialogs of this module share: a panel with a title, over the shell.
struct AgentDialogCard<Content: View>: View {
    let title: String
    var width: CGFloat = Space.s8 * 17
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content
        }
        .foregroundStyle(palette.text)
        .corePanel(radius: Radius.panel, padding: Space.s6)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// New agent session: what the API takes (harness, policy mode, runner, model, prompt, secrets). The Core refuses a runner that
/// cannot run it, and the refusal shows here in place.
struct NewSessionSheet: View {
    @Bindable var model: AgentsModel
    @State private var harness = "claude"
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
    private var ready: Bool {
        runner != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    var body: some View {
        AgentDialogCard(title: "New agent session") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("It runs on a runner of the Home Core. You can close this Mac and it keeps going.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    if let notice { NoticeBanner(notice: notice) }
                    VStack(alignment: .leading, spacing: Space.s3) {
                        field("Harness") {
                            CoreSegmented(
                                "Harness",
                                segments: ["claude", "codex", "opencode", "agy"].map { CoreSegment($0, $0) },
                                selection: $harness)
                        }
                        field("Policy mode") {
                            CoreSegmented(
                                "Policy mode",
                                segments: ["ask", "accept_edits", "sandboxed"].map { CoreSegment($0, $0) },
                                selection: $mode)
                        }
                    }
                    if mode == "sandboxed" {
                        Text("Sandboxed needs the admin scope; the Core refuses it otherwise.").foregroundStyle(
                            palette.text2)
                    }
                    field("Runner") { runnerList }
                    CoreTextField("Model (optional)", placeholder: "the harness default", text: $llm, mono: true)
                    field("Prompt") { promptField }
                    field("Secrets to pass  \(secrets.count) of 16") { secretsField }
                }
                .padding(.bottom, Space.s1)
            }
            .frame(maxHeight: Space.s8 * 20)
            HStack(spacing: Space.s2) {
                Text("Starting needs Touch ID.").foregroundStyle(palette.text2)
                Spacer(minLength: 0)
                Button("Cancel") { model.shell.closeDialog() }.buttonStyle(.coreSecondary).keyboardShortcut(
                    .cancelAction)
                Button(busy ? "Starting…" : "Start session") { start() }
                    .buttonStyle(.coreProminent).keyboardShortcut(.return, modifiers: .command).disabled(!ready)
                    .help("Start the session (⌘Return)")
            }
        }
        .onAppear {
            pickRunner()
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

    private func pickRunner() {
        if runner == nil {
            runnerID = (model.runners.first { $0.online && $0.runsAgents } ?? model.runners.first { $0.online })?.id
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

    private var promptField: some View {
        TextEditor(text: $prompt).font(.system(size: MacTextSize.body)).scrollContentBackground(.hidden)
            .focused($promptFocus).frame(minHeight: Space.s8 * 3).padding(Space.s2)
            .background(palette.glassCard, in: coreShape(Radius.control))
            .overlay {
                coreShape(Radius.control).strokeBorder(
                    promptFocus ? palette.focusRing : palette.glassCardEdge, lineWidth: promptFocus ? 2 : 1)
            }
            .accessibilityLabel("Prompt")
    }

    private var secretsField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !secrets.isEmpty {
                HStack(spacing: Space.s1) {
                    ForEach(secrets, id: \.self) { s in
                        HStack(spacing: Space.s1) {
                            Text(s).font(.system(size: MacTextSize.meta, design: .monospaced))
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
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).fixedSize(
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
            secrets: secrets)
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
                Text(runner.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
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
