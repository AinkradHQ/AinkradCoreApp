import AppKit
import CoreUI
import SwiftUI

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
    @Environment(\.corePalette) private var palette
    @State private var pick = 0

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
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        } else {
            composer
        }
    }

    private var composer: some View {
        let on = focused.wrappedValue
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !commands.isEmpty { palette(commands) }
            VStack(alignment: .leading, spacing: Space.s2) {
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
                        minHeight: Space.s8 + Space.s3, maxHeight: Space.s8 * 5, keys: keys)
                }
                .coreFont(size: MacTextSize.body)
                HStack(spacing: Space.s2) {
                    CoreIconButton(symbol: "paperclip", label: "Attach a file") { attach() }
                        .disabled(!enabled).help("Attach a file: adds its path to the message")
                    CoreChip(AgentWords.toolName(session.harness) + " · " + (session.model ?? "default model"))
                    stateChip
                    Spacer(minLength: Space.s2)
                    if bytes > AgentsModel.messageLimit / 2 {
                        Text("\(coreDecimal(Double(bytes) / 1024, 1)) / 16 KiB")
                            .coreFont(size: MacTextSize.meta).monospacedDigit()
                            .foregroundStyle(over ? palette.tone(.fail).ink : palette.text2)
                    }
                    if model.canStopTurn(session) {
                        Button("Stop turn") { model.stopTurn(session.id) }
                            .buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, "esc")
                            .help("Stop the current turn (Esc). The session stays open.")
                    }
                    if enabled {
                        Button(action: { Task { await model.send(session.id) } }) {
                            Label(session.idle || !session.live ? "Send" : "Queue", systemImage: "arrow.up")
                        }
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small)).environment(\.coreKeycap, "↩")
                        .disabled(!model.canSend(session.id))
                        .help(
                            session.idle || !session.live
                                ? "Send the message (Return)" : "Send it after this turn (Return)")
                    }
                }
            }
            .padding(Space.s3)
            // A plain field, no outline (Ahmed, 2026-11-15); a slightly stronger well while writing.
            .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
            .onTapGesture { if enabled { focused.wrappedValue = true } }
            .coreDimWhenDisabled(enabled || session.over)
        }
        .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
        .onChange(of: text) { _, _ in pick = 0 }
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

    /// What the session is doing, beside the tool: blue while it works, amber while an approval waits. Nothing when idle.
    @ViewBuilder private var stateChip: some View {
        if model.waiting(session.id) {
            StateBadge("Waiting for your answer", tone: .warn, symbol: "hand.raised")
        } else if model.canStopTurn(session) {
            TimelineView(.periodic(from: session.updatedAt, by: 1)) { ctx in
                StateBadge(
                    "Thinking · " + coreUnit("\(max(0, Int(ctx.date.timeIntervalSince(session.updatedAt))))", "s"),
                    tone: .done, symbol: "ellipsis")
            }
        }
    }

    /// Every key the field hands over (one place, read fresh on each update).
    private var keys: ComposerKeys {
        ComposerKeys(
            submit: { shift in
                switch ComposerReturn.action(shift: shift, text: text, commands: commands, pick: pick) {
                case .newline: return false
                case .fill(let name): draft.wrappedValue = name + " "
                case .send: Task { await model.send(session.id) }
                }
                return true
            },
            up: {
                if !commands.isEmpty {
                    pick = max(0, pick - 1)
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
            })
    }

    private func attach() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        let refs = p.urls.map { "@" + $0.path }.joined(separator: " ")
        draft.wrappedValue += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + refs + " "
        focused.wrappedValue = true
    }
}
