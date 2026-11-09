import CoreUI
import SwiftUI

/// New agent session, the quick way (⌘N): one prompt, the defaults shown as chips (harness, mode, the best runner),
/// ⌘Return starts it. ⌥⌘N or "More options" opens the full sheet with the prompt carried over.
struct QuickSessionView: View {
    @Bindable var model: AgentsModel
    @State private var prompt = ""
    @State private var busy = false
    @State private var notice: InlineNotice?
    @State private var shown = false
    @State private var chainID: Int64?
    @FocusState private var focus: Bool

    private let prefs = AgentPrefs.shared
    private var runner: RunnerInfo? {
        if !prefs.runner.isEmpty, let r = model.runners.first(where: { $0.id == prefs.runner }) { return r }
        return model.runners.first { $0.online && $0.runsAgents && !$0.degraded } ?? model.runners.first { $0.online }
    }
    /// The chain a start uses: the one picked on the chip, else the default one, when this device may see chains. It sets the
    /// harness and model. KAN-475: a pool chip would sit beside it once `SessionPoolHook.isAvailable`.
    private var chain: ChainOption? { model.chains.first { $0.id == chainID } ?? model.defaultChain }
    private var ready: Bool {
        runner != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
            && !PromptSize.over(prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile("sparkles", hue: GlassInk.violet, size: 44, bounce: shown)
                    .shadow(color: GlassInk.violet.opacity(0.45), radius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New agent session").font(.system(size: MacTextSize.large + 2, weight: .bold))
                    Text("Say what it should do. It keeps running if you close this Mac.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
            .coreRise(shown, 0)
            CoreTextArea(
                nil, placeholder: "Fix the failing tests in the citadel module…", text: $prompt,
                size: MacTextSize.headline, minHeight: 110, maxHeight: 220, focus: $focus
            )
            .coreRise(shown, 1)
            HStack(spacing: Space.s2) {
                if let chain {
                    chainChip(chain)
                } else {
                    chip("sparkles", AgentWords.harnessName(prefs.harness), GlassInk.violet)
                }
                chip("hand.raised", SessionMode.words(prefs.mode), GlassInk.blue)
                chip("server.rack", runner?.name ?? "no runner", runner == nil ? GlassInk.red : GlassInk.green)
                Spacer(minLength: 0)
                if let w = PromptSize.words(prompt) {
                    Text(w).font(.system(size: MacTextSize.meta)).foregroundStyle(
                        PromptSize.over(prompt) ? GlassInk.redInk : GlassInk.secondary)
                }
            }
            .coreRise(shown, 2)
            if let notice { NoticeBanner(notice: notice) }
            HStack(spacing: Space.s2) {
                Button("Cancel") { model.shell.closeDialog() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
                Button("More options") { advanced() }.buttonStyle(.coreSecondary)
                    .keyboardShortcut("n", modifiers: [.command, .option]).environment(\.coreKeycap, "⌥⌘N")
                Spacer(minLength: 0)
                Button {
                    start()
                } label: {
                    Label(busy ? "Starting…" : "Start", systemImage: "play.fill")
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                .keyboardShortcut(.return, modifiers: .command).environment(\.coreKeycap, "⌘↩")
                .disabled(!ready)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 18)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .coreModalEntrance()
        .onAppear {
            shown = true
            if let d = model.draftChain {
                chainID = d
                model.draftChain = nil
            }
        }
        .task {
            await model.loadRunners()
            try? await Task.sleep(for: .milliseconds(200))
            focus = true
        }
    }

    /// The chain the session draws accounts from. With more than one chain the chip opens a picker.
    @ViewBuilder private func chainChip(_ chain: ChainOption) -> some View {
        let help = "\(chain.isDefault ? "Default chain" : "Chain"): \(chain.steps.joined(separator: ", then "))"
        if model.chains.count > 1 {
            CoreDropdown(
                items: model.chains.map { c in
                    CoreDropdownItem(
                        c.name, symbol: "link", checked: c.id == chain.id, note: c.isDefault ? "default" : nil
                    ) {
                        chainID = c.id
                    }
                }
            ) {
                chip("link", chain.name, GlassInk.blue, picker: true)
            }
            .help("\(help). Click to choose another chain.")
            .accessibilityLabel("Chain, \(chain.name)")
        } else {
            chip("link", chain.name, GlassInk.blue).help(help)
        }
    }

    private func chip(_ symbol: String, _ text: String, _ hue: Color, picker: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(hue)
            Text(text).font(.system(size: MacTextSize.meta, weight: .medium))
            if picker {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.s2).frame(height: 22)
        .background(GlassInk.well, in: coreShape(6))
        .overlay { coreShape(6).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
    }

    private func start() {
        guard let runner, ready else { return }
        busy = true
        notice = nil
        let new = NewAgentSession(
            runner: runner.id, harness: prefs.harness, model: chain == nil && !prefs.model.isEmpty ? prefs.model : nil,
            prompt: prompt, mode: prefs.mode, secrets: [], chain: chain?.id)
        Task {
            let n = await model.create(new)
            busy = false
            if let n { notice = n } else { model.shell.closeDialog() }
        }
    }

    private func advanced() {
        model.draftPrompt = prompt
        model.draftChain = chain?.id
        model.shell.closeDialog()
        model.openNewSession(advanced: true)
    }
}
