import AppKit
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// The commands the CLI takes in its streaming mode; picking one fills the field, and Return sends it like any message.
enum SlashCommands {
    static let all: [(name: String, help: String)] = [
        ("/compact", "Summarise the conversation to free context"),
        ("/clear", "Start the conversation over in this folder"),
        ("/context", "Show how much context is used"),
        ("/cost", "Show what this session has cost"),
        ("/model", "Switch the model"),
        ("/init", "Write a CLAUDE.md for this folder"),
        ("/review", "Review the changes in this folder"),
    ]

    /// The commands a draft like `/co` offers; none once there is a space or it does not start with a slash.
    static func matches(_ draft: String) -> [(name: String, help: String)] {
        guard draft.hasPrefix("/"), !draft.contains(" "), !draft.contains("\n") else { return [] }
        let q = draft.lowercased()
        return all.filter { $0.name.hasPrefix(q) }
    }
}

/// What Return does in the field: ⇧Return a new line; with the command list open and a different command highlighted, fill it in;
/// otherwise send.
enum ComposerReturn: Equatable {
    case newline, send
    case fill(String)

    static func action(shift: Bool, text: String, commands: [(name: String, help: String)], pick: Int) -> Self {
        if shift { return .newline }
        if !commands.isEmpty {
            let name = commands[min(pick, commands.count - 1)].name
            if name != text { return .fill(name) }
        }
        return .send
    }
}

/// The message field under a conversation. Always open while the session is live: Return sends (⇧Return a new line), the
/// message queues while a turn runs, ↑ on an empty field edits the last message, Esc stops the turn, "/" opens the commands
/// (↑ ↓ pick, Return or Tab take one). The keys come from `ComposerTextView`, so they work whatever SwiftUI thinks has focus.
struct ComposerView: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    var focused: FocusState<Bool>.Binding
    /// A session shortcut pressed while typing (`SessionShortcut`): true when the session took it.
    var command: (SessionShortcut) -> Bool = { _ in false }
    @Environment(\.sessionUI) private var ui
    @Environment(\.corePalette) private var palette
    @State private var pick = 0
    @State private var dropping = false
    @State private var voice = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var files: [URL] { model.attachments[session.id] ?? [] }

    private var draft: Binding<String> {
        Binding(get: { model.drafts[session.id] ?? "" }, set: { model.drafts[session.id] = $0 })
    }
    private var text: String { model.drafts[session.id] ?? "" }
    private var bytes: Int { text.utf8.count }
    private var over: Bool { bytes > AgentsModel.messageLimit }
    private var enabled: Bool { model.canWrite(session) }
    private var commands: [(name: String, help: String)] { enabled ? SlashCommands.matches(text) : [] }

    private var placeholder: String { ConversationWords.placeholder(session) }

    var body: some View {
        if !enabled && session.state == .ended {
            // An ended session takes no message: one quiet line where the composer was (Start again is in the header).
            Label(placeholder, systemImage: "lock")
                .coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .coreWell()
                .readingColumn()
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        } else {
            composer
        }
    }

    private var composer: some View {
        let on = focused.wrappedValue
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !commands.isEmpty { palette(commands) }
            // The agent's own steps, one line above the composer (opens upward).
            if let todos = TodoStrip.items(model.transcripts[session.id]?.entries ?? []) { TodoStrip(items: todos) }
            // What went wrong with the last send (or resume, wake...), right where you typed it.
            if let n = model.notices[session.id] {
                CoreNotice(symbol: n.symbol, title: n.title, text: n.detail, tone: n.tone)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                // Queued messages live inside the composer card, above the field (direction A).
                QueuedStack(model: model, session: session)
                if !files.isEmpty { attachmentsRow }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder).foregroundStyle(palette.text2).padding(.horizontal, Space.s1 + 1)
                            .allowsHitTesting(false)
                    }
                    ComposerTextView(
                        text: draft, focused: focused, enabled: enabled,
                        font: AgentPrefs.shared.nsFont(
                            size: MacTextSize.scaled(
                                MacTextSize.body, by: TextSizePrefs.shared.scale * AgentPrefs.shared.textScale)),
                        minHeight: Space.s8 + Space.s3, maxHeight: Space.s8 * 5, keys: keys, onFiles: add)
                }
                .coreFont(size: MacTextSize.body)
                HStack(spacing: Space.s2) {
                    CoreIconButton(symbol: "paperclip", label: "Attach a file") { attach() }
                        .disabled(!enabled).help("Attach a file: adds its path to the message (⇧⌘A)").keyHint(.attach)
                    // Icon-first (the mockup's): the chips show their words only while you write.
                    modelPicker(labels: on)
                    ModeChip(model: model, session: session, labels: on)
                    Spacer(minLength: Space.s2)
                    contextButton
                    if Dictation.available, enabled { micButton }
                    if bytes > AgentsModel.messageLimit / 2 {
                        Text("\(coreDecimal(Double(bytes) / 1024, 1)) / 16 KiB")
                            .coreFont(size: MacTextSize.meta).monospacedDigit()
                            .foregroundStyle(over ? palette.tone(.fail).ink : palette.text2)
                    }
                    if enabled, model.canStopTurn(session), canSteer { steerButton }
                    if enabled || model.canStopTurn(session) { actionButton }
                }
            }
            .padding(Space.s3)
            // A plain field, no outline (Ahmed, 2026-11-15); a slightly stronger well while writing.
            // A card floating over the page, as chat apps' composers do; one step stronger while you write.
            .sessionFloat()
            .animation(Motion.out(Motion.hover), value: on)
            .contentShape(coreShape(Radius.cardMac))
            .onTapGesture { if enabled { focused.wrappedValue = true } }
            // Files dropped anywhere on the composer attach, like a chat app.
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                guard enabled else { return false }
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in add([url]) }
                    }
                }
                return true
            }
            .overlay {
                if dropping {
                    coreShape(Radius.cardMac).strokeBorder(GlassInk.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .allowsHitTesting(false)
                }
            }
            .coreDimWhenDisabled(enabled || session.over)
        }
        .readingColumn()
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
        .onChange(of: text) { _, new in
            pick = 0
            DraftStore.save(session.id, new)
        }
        .onAppear {
            // A draft kept from last time comes back into an empty field.
            if text.isEmpty { draft.wrappedValue = DraftStore.load(session.id) }
        }
        .onChange(of: ui?.attach) { _, _ in if enabled { attach() } }
    }

    private func palette(_ list: [(name: String, help: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                Button {
                    draft.wrappedValue = c.name + " "
                } label: {
                    HStack(spacing: Space.s3) {
                        Text(c.name).coreFont(size: MacTextSize.body, weight: .semibold, design: .monospaced)
                        Text(c.help).foregroundStyle(palette.text2)
                        Spacer(minLength: 0)
                    }
                    .coreFont(size: MacTextSize.body).padding(.horizontal, Space.s3)
                    .frame(minHeight: MacSize.controlLg)
                    .background(
                        i == min(pick, list.count - 1) ? palette.uDimHover : .clear, in: coreShape(Radius.control)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.row, interactive: false)
        .accessibilityLabel("Commands")
    }

    /// One compact button that follows what is happening (Ahmed, 2026-11-16): Stop while a turn runs and the field is empty,
    /// Queue once you type during a turn, Send when it is idle, dimmed with nothing to send.
    private var actionButton: some View {
        let act = ComposerAction.of(
            running: model.canStopTurn(session),
            hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !files.isEmpty, canSend: model.canSend(session.id))
        return Button {
            if act == .stop { model.stopTurn(session.id) } else { submit() }
        } label: {
            Image(systemName: act == .stop ? "stop.fill" : "arrow.up")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: MacSize.controlSm - Space.s2)
        }
        .buttonStyle(GraphiteButtonStyle(iconOnly: true))
        .disabled(act == .idle)
        .keyHint(act == .stop ? "esc" : act == .idle ? "" : "↩")
        .help(act.help)
        .accessibilityLabel(act.name)
        .animation(Motion.out(Motion.ui), value: act)
    }

    /// The tool and its model; for Claude Code a menu that switches the model with the tool's own `/model` command. Other
    /// tools show their model as a label (they have no in-session switch the app can send).
    @ViewBuilder private func modelPicker(labels: Bool) -> some View {
        let label = AgentWords.toolName(session.harness) + " · " + (session.model ?? "default model")
        if session.harness == "claude", enabled {
            CoreDropdown(
                items: Self.claudeModels.map { m in
                    CoreDropdownItem(
                        m.title, checked: (session.model ?? "").lowercased().contains(m.id), note: m.note
                    ) { Task { await model.say(session.id, "/model \(m.id)") } }
                },
                isPresented: Binding(get: { ui?.modelMenu ?? false }, set: { ui?.modelMenu = $0 })
            ) {
                HStack(spacing: Space.s1) {
                    Image(systemName: "sparkles")
                    if labels {
                        Text(label)
                        Image(systemName: "chevron.up.chevron.down").coreFont(size: MacTextSize.meta - 1)
                    }
                }
                .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: labels)
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                .background(GlassInk.well, in: coreShape(Radius.chip))
            }
            .help("Switch the model for the rest of this session (⇧⌘M)").keyHint(.model)
        } else {
            CoreChip(labels ? label : "", symbol: "sparkles", minWidth: 0).help(label)
        }
    }

    /// The context meter (the mockup's): a small bar of how much of the window the conversation fills; it turns amber near
    /// the end, and a click offers /compact. The window size is a table in `ContextWindow` (the Core exposes none).
    @ViewBuilder private var contextButton: some View {
        if let used = session.usage?.tokens, used > 0 {
            let ctx = ConversationWords.context(used: used, window: ContextWindow.tokens(model: session.model))
            Button {
                if enabled, ctx.fill > 0.7 { draft.wrappedValue = "/compact " } else { focused.wrappedValue = true }
            } label: {
                CoreMeter(ctx.fill, low: ctx.fill > 0.8, label: "Context used").frame(width: 44)
                    .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.chip, scale: 0.97, hoverFill: true))
            .help("\(Int(ctx.fill * 100))% of the context is used (\(ctx.text))" + (ctx.fill > 0.7 ? ". Click to compact." : ""))
            .accessibilityLabel("Context used: \(Int(ctx.fill * 100)) percent")
        }
    }

    /// Dictation, on this Mac only. The first press asks for the microphone and speech recognition.
    private var micButton: some View {
        let listening = voice.state == .listening
        return CoreIconButton(
            symbol: listening ? "mic.fill" : "mic", label: listening ? "Stop dictating" : "Dictate", selected: listening
        ) {
            let base = text
            Task {
                await voice.toggle { phrase in
                    draft.wrappedValue = base + (base.isEmpty || base.hasSuffix(" ") ? "" : " ") + phrase
                }
            }
        }
        .help(listening ? "Stop dictating" : "Dictate: speech is recognised on this Mac, nothing is sent out")
        .onChange(of: voice.state) { _, now in
            if case .blocked(let why) = now { model.note(session.id, InlineNotice(title: "Dictation is off", detail: why, tone: .warn)) }
        }
        .onDisappear { voice.stop() }
    }

    /// Steer needs the tool to take an interrupt (every tool the Core can stop a turn of).
    private var canSteer: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.canSend(session.id)
    }

    /// Redirect now: stop the running turn and send this message as the next one.
    private var steerButton: some View {
        Button { Task { await model.steer(session.id) } } label: {
            Label("Steer", systemImage: "arrow.turn.down.right")
        }
        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        .help("Stop the turn now and send this message instead (the queue waits)")
    }

    static let claudeModels: [(id: String, title: String, note: String?)] = [
        ("default", "Default", "the account's choice"), ("opus", "Opus", "most capable"),
        ("sonnet", "Sonnet", "balanced"),
        ("haiku", "Haiku", "fastest"),
    ]

    /// Every key the field hands over (one place, read fresh on each update).
    private var keys: ComposerKeys {
        ComposerKeys(
            submit: { shift in
                switch ComposerReturn.action(shift: shift, text: text, commands: commands, pick: pick) {
                case .newline: return false
                case .fill(let name): draft.wrappedValue = name + " "
                case .send: submit()
                }
                return true
            },
            up: {
                if !commands.isEmpty {
                    pick = max(0, pick - 1)
                    return true
                }
                // ↑ on an empty field, as in the Claude CLI: the queued messages come back to the field to edit first;
                // with none queued, your last message does.
                if text.isEmpty, model.queued[session.id]?.isEmpty == false {
                    model.editAllQueued(session.id)
                    return true
                }
                guard text.isEmpty, let last = model.lastUserMessage(session.id) else { return false }
                draft.wrappedValue = last
                return true
            },
            down: {
                guard !commands.isEmpty else { return false }
                pick = min(commands.count - 1, pick + 1)
                return true
            },
            tab: {
                // Tab takes the highlighted command; otherwise the field moves focus on (KeyTextView).
                guard !commands.isEmpty else { return false }
                draft.wrappedValue = commands[min(pick, commands.count - 1)].name + " "
                return true
            },
            escape: {
                if !commands.isEmpty {
                    draft.wrappedValue = ""
                } else if model.canStopTurn(session) {
                    model.stopTurn(session.id)
                } else {
                    focused.wrappedValue = false
                }
                return true
            },
            command: { e in SessionShortcut.match(e).map(command) ?? false },
            backtab: {
                guard let mode = SessionMode.of(session), let next = mode.next(harness: session.harness) else {
                    return false
                }
                Task { await model.setMode(session.id, to: next) }
                return true
            })
    }

    /// Return or the button: while a turn runs the message waits in the queue; otherwise it goes now.
    private func submit() {
        if model.canStopTurn(session) { model.enqueue(session.id) } else { Task { await model.send(session.id) } }
    }

    /// The 📎 button: pick files to attach.
    private func attach() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        add(p.urls)
        focused.wrappedValue = true
    }

    /// Attach files, once each.
    private func add(_ urls: [URL]) {
        var list = files
        for u in urls where !list.contains(u) { list.append(u) }
        model.attachments[session.id] = list
    }

    /// The attached files above the field: a thumbnail for an image, a document glyph otherwise, and a way to remove each.
    private var attachmentsRow: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ScrollView(.horizontal) {
                HStack(spacing: Space.s2) {
                    ForEach(files, id: \.self) { url in AttachmentChip(url: url) { remove(url) } }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func remove(_ url: URL) { model.attachments[session.id] = files.filter { $0 != url } }
}

/// One attached file: an image's thumbnail or a document glyph, its name, and ✕ to remove it.
private struct AttachmentChip: View {
    let url: URL
    let remove: () -> Void
    private var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            if isImage, let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().scaledToFill().frame(width: 28, height: 28)
                    .clipShape(coreShape(Radius.chip))
            } else {
                Image(systemName: "doc").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .frame(width: 28, height: 28).background(GlassInk.well, in: coreShape(Radius.chip))
            }
            Text(url.lastPathComponent).coreFont(size: MacTextSize.meta).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: Space.s8 * 5, alignment: .leading)
            CoreIconButton(symbol: "xmark", label: "Remove \(url.lastPathComponent)", action: remove)
        }
        .padding(.leading, Space.s1).padding(.trailing, Space.s1).padding(.vertical, Space.s1)
        .background(GlassInk.wellHover, in: coreShape(Radius.control))
        .help(url.path)
    }

}

/// What the composer's one button does now.
enum ComposerAction: Equatable {
    case stop, queue, send, idle

    static func of(running: Bool, hasText: Bool, canSend: Bool) -> Self {
        if hasText && canSend { return running ? .queue : .send }
        if running { return .stop }
        return .idle
    }

    var name: String {
        switch self {
        case .stop: "Stop turn"
        case .queue: "Queue"
        case .send, .idle: "Send"
        }
    }

    var help: String {
        switch self {
        case .stop: "Stop the current turn (Esc or ⌘.). The session stays open."
        case .queue: "Queue it: it goes out when this turn ends (Return). Esc stops the turn."
        case .send: "Send the message (Return)"
        case .idle: "Type a message to send"
        }
    }
}
