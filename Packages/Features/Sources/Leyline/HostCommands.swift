import AppKit
import CoreUI
import SwiftUI

/// Pre-set commands: a card per command, the saved ones meant for this host and then the built-ins (saved the first time they
/// run). Run goes through the Core's gate, the host's AI rule and Touch ID when the Core asks; the output opens in the drawer
/// under the cards. ⌥1…⌥9 run the first nine, the arrows light a card and ⏎ runs it, ⌘N saves a new one.
struct HostCommandsSection: View {
    let model: LeylineModel
    let host: HostItem
    let state: HostPageState
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HostSectionTitle("Pre-set commands", line: "\(host.aiRule.title) for AI on this host · ⌥1–⌥9 run")
            content
            if model.commandForm != nil {
                NewCommandForm(model: model, state: state).transition(entrance)
            } else if let id = state.shown, state.runs[id] != nil {
                CommandOutputDrawer(state: state, id: id).transition(entrance)
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: state.shown)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.commandForm == nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("host-commands")
    }

    /// The drawer and the form come down a few points under the cards; a fade only under Reduce Motion.
    private var entrance: AnyTransition { reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s2)) }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: Space.s8 * 7), spacing: Space.s2)] }

    @ViewBuilder private var content: some View {
        switch state.commands {
        case .idle, .loading:
            LazyVGrid(columns: columns, spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    CoreSkeleton(coreShape(Radius.cardMac)).frame(height: Space.s8 * 4)
                }
            }
        case .missing:
            Text(HostWords.gone("Pre-set commands")).foregroundStyle(GlassInk.secondary)
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "Commands did not load", text: why, tone: .warn) {
                Button("Try Again") { Task { await state.loadCommands() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        case .ready:
            LazyVGrid(columns: columns, spacing: Space.s2) {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                    CommandCard(item: item, index: i, state: state)
                }
                NewCommandCard(on: model.commandForm != nil) {
                    model.commandForm = model.commandForm == nil ? CommandDraft() : nil
                }
                .disabled(model.readOnly)
            }
        }
    }
}

/// One command: its glyph and key, its name, what it runs, how its last run here went, and Run.
private struct CommandCard: View {
    let item: HostCommandList.Item
    let index: Int
    let state: HostPageState
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    private var c: PresetCommand { item.command }
    private var run: CommandRun? { state.runs[c.id] }
    private var running: Bool { run.map { !$0.finished } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s2) {
                IconTile(
                    HostCommandList.symbol(c), hue: palette.btnPrimary, size: Space.s6 + Space.s1, bounce: run?.state)
                Spacer(minLength: Space.s2)
                if let k = HostCommandList.keyWord(index) { CoreKeycap(k) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(c.line).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(GlassInk.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(c.steps.joined(separator: "\n"))
            }
            HStack(spacing: Space.s2) {
                status
                Spacer(minLength: Space.s1)
                runButton
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SelectedFill(selected: state.lit == c.id, hover: hover, radius: Radius.cardMac))
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture {
            state.lit = c.id
            if run != nil { state.shown = c.id }
        }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .contextMenu {
            Button("Run") { state.tap(item) }.disabled(running)
            if run != nil { Button("Show Output") { state.shown = c.id } }
            Button("Copy Command") { copy(c.steps.joined(separator: "\n")) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(c.name)
        .accessibilityAddTraits(state.lit == c.id ? .isSelected : [])
    }

    @ViewBuilder private var status: some View {
        if let r = run {
            let b = HostWords.badge(r)
            StateBadge(b.word, tone: b.tone, symbol: "circle")
            if r.finished, let at = r.startedAt {
                Text(HostWords.ago(at)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(item.builtIn ? "Built-in" : c.confirm ? "Asks first" : c.readOnly ? "Read-only" : "Saved")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                .help(
                    item.builtIn
                        ? "Saved in your Core the first time it runs" : c.readOnly ? "Safe for AI under Read-only" : "")
        }
    }

    @ViewBuilder private var runButton: some View {
        let b = Button {
            state.tap(item)
        } label: {
            Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: running))
        .disabled(running || state.model.readOnly || state.host?.light == .off)
        .help(
            "Run \(c.name) on \(state.host?.name ?? "this host")"
                + (HostCommandList.keyWord(index).map { " (\($0))" } ?? "")
        )
        .accessibilityIdentifier("command-run-\(index + 1)")
        if let k = HostCommandList.key(index) {
            b.keyboardShortcut(KeyEquivalent(k), modifiers: .option)
        } else {
            b
        }
    }
}

/// The last card: New Command (⌘N), lit while its form is open.
private struct NewCommandCard: View {
    let on: Bool
    let run: () -> Void
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: run) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    IconTile("plus", hue: palette.btnPrimary, size: Space.s6 + Space.s1, bounce: on)
                    Spacer(minLength: Space.s2)
                    CoreKeycap("⌘N")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Command").coreFont(size: MacTextSize.body, weight: .semibold)
                    Text("Save one you run often").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(SelectedFill(selected: on, hover: hover, radius: Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac))
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help("Save a command for every host (⌘N)")
        .accessibilityIdentifier("command-new")
    }
}

/// The output of a run, under the cards: its state, exit code and time, the text as the Core redacted it, Copy and Close.
struct CommandOutputDrawer: View {
    let state: HostPageState
    let id: String

    var body: some View {
        if let r = state.runs[id] {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(r.commandName).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    let b = HostWords.badge(r)
                    StateBadge(b.word, tone: b.tone, symbol: "circle")
                    if let facts = HostWords.facts(r) {
                        Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: Space.s2)
                    CoreIconButton(symbol: "doc.on.doc", label: "Copy the output") { copy(r.output ?? "") }
                        .disabled((r.output ?? "").isEmpty)
                        .help("Copy the output")
                    CoreIconButton(symbol: "xmark", label: "Close the output") { state.shown = nil }
                        .help("Close the output")
                }
                output(r)
            }
            .padding(Space.s3)
            .coreWell(radius: Radius.cardMac)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("command-output")
        }
    }

    @ViewBuilder private func output(_ r: CommandRun) -> some View {
        if let out = r.output, !out.isEmpty {
            ScrollView {
                Text(out).coreFont(size: MacTextSize.meta, design: .monospaced).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3)
            }
            .frame(height: Space.s8 * 7)
            .background(GlassInk.well, in: coreShape(Radius.control))
        } else if !r.finished {
            HStack(spacing: Space.s3) {
                CoreWorkingBar().frame(maxWidth: Space.s8 * 4)
                Text(
                    r.state == .needsApproval
                        ? "Waiting for a person to approve it. Approving uses Touch ID."
                        : "Running on \(state.host?.name ?? "the host")…"
                )
                .foregroundStyle(GlassInk.secondary)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.control))
        } else {
            Text("It printed nothing.").foregroundStyle(GlassInk.secondary)
        }
    }
}

/// New Command: a name, the line to run and whether it asks first. Saved in the Core for every host; Return saves, Esc
/// cancels.
private struct NewCommandForm: View {
    let model: LeylineModel
    let state: HostPageState
    @State private var tried = false

    var body: some View {
        let draft = Binding(get: { model.commandForm ?? CommandDraft() }, set: { model.commandForm = $0 })
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("New Command").coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(
                    .isHeader)
                Text("Saved in your Core for every host. AI follows each host’s rule.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                CoreTextField("Name", placeholder: "Restart the app", text: draft.name, autofocus: true) { save() }
                    .frame(width: Space.s8 * 7)
                CoreTextField("Command", placeholder: "sudo systemctl restart app", text: draft.command, mono: true) {
                    save()
                }
            }
            CoreCheckbox(
                "Ask before it runs", detail: "A confirm card comes first, for you and for AI.", isOn: draft.confirm)
            if tried, let p = draft.wrappedValue.problem { CoreFieldError(p) }
            CoreDialogFooter(
                cancel: CoreAction("Cancel", key: .cancel) { model.commandForm = nil },
                primary: CoreAction("Save", key: .primary) { save() }, busy: state.saving)
        }
        .padding(Space.s4)
        .coreWell(radius: Radius.cardMac)
        .accessibilityIdentifier("command-form")
    }

    private func save() {
        tried = true
        guard let d = model.commandForm, d.problem == nil else { return }
        Task { if await state.save(d) { model.commandForm = nil } }
    }
}

private func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
