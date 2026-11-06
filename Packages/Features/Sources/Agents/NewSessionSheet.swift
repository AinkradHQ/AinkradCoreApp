import CoreUI
import SwiftUI

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
                    Text("Isolation (microVM, memory, disk, network egress): not available yet.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    field("Secrets to pass  \(secrets.count) of 16") { secretsField }
                }
                .padding(.bottom, Space.s1)
            }
            .frame(maxHeight: Space.s8 * 20)
            preview
            HStack(spacing: Space.s2) {
                Text("Starting needs Touch ID.").foregroundStyle(palette.text2)
                Spacer(minLength: 0)
                Button("Cancel") { model.shell.closeDialog() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
                Button(busy ? "Starting…" : "Start session") { start() }
                    .buttonStyle(.coreProminent).keyboardShortcut(.return, modifiers: .command).environment(
                        \.coreKeycap, "⌘↩"
                    ).disabled(!ready)
                    .help("Start the session (⌘Return)")
            }
        }
        .onAppear {
            pickRunner()
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

    /// What pressing Start will do, in one line, from what is chosen. No number here is invented: it is the harness, the runner
    /// and the options picked.
    private var preview: some View {
        let words = runner.map { "\(harness) on \($0.name)" } ?? "Choose a runner to start on"
        let options = [
            mode, llm.isEmpty ? nil : llm,
            secrets.isEmpty ? nil : "\(secrets.count) secret\(secrets.count == 1 ? "" : "s")",
        ]
        .compactMap { $0 }
        return VStack(alignment: .leading, spacing: Space.s1) {
            Text(runner == nil ? words : "This will run \(words)").font(
                .system(size: MacTextSize.headline, weight: .semibold))
            HStack(spacing: Space.s1) {
                ForEach(options, id: \.self) { o in
                    Text(o).font(.system(size: MacTextSize.meta, design: .monospaced))
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
            Text(PromptSize.words(prompt)).font(.system(size: MacTextSize.meta, design: .monospaced))
                .foregroundStyle(PromptSize.over(prompt) ? palette.tone(.fail).ink : palette.text2)
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
    static func words(_ s: String) -> String {
        over(s) ? "\(bytes(s)) of 64 KiB: too long" : String(format: "%.1f of 64 KiB", Double(bytes(s)) / 1024)
    }
}
