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

/// The message field under a conversation. Always open while the session is live: Return sends (⇧Return a new line), the
/// message queues while a turn runs, ↑ on an empty field edits the last message, Esc stops the turn, "/" opens the commands.
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

    private var placeholder: String {
        switch session.state {
        case .running: "Type to queue a message for after this turn"
        case .waiting: "Message \(AgentWords.toolName(session.harness))…"
        case .starting: "Starting. You can type now; it is sent when the session is up."
        case .interrupted: "Resuming. You can type now."
        case .ended where session.idleEnded: "Ended (idle). Send a message to continue."
        case .ended: "This AI session ended. Start again to continue."
        default: "This AI session was lost. Send a message to bring it back."
        }
    }

    var body: some View {
        let on = focused.wrappedValue
        VStack(alignment: .leading, spacing: Space.s1) {
            if !commands.isEmpty { palette(commands) }
            VStack(alignment: .leading, spacing: Space.s2) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder).foregroundStyle(GlassInk.secondary).padding(.horizontal, 5).allowsHitTesting(
                            false)
                    }
                    TextEditor(text: draft)
                        .accessibilityIdentifier("agent-composer")
                        .scrollContentBackground(.hidden).focused(focused).focusEffectDisabled().disabled(!enabled)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            if !commands.isEmpty, commands[min(pick, commands.count - 1)].name != text {
                                draft.wrappedValue = commands[min(pick, commands.count - 1)].name + " "
                                return .handled
                            }
                            Task { await model.send(session.id) }
                            return .handled
                        }
                        .onKeyPress(.upArrow, phases: .down) { _ in
                            if !commands.isEmpty {
                                pick = max(0, pick - 1)
                                return .handled
                            }
                            guard text.isEmpty, let last = model.lastUserMessage(session.id) else { return .ignored }
                            draft.wrappedValue = last
                            return .handled
                        }
                        .onKeyPress(.downArrow, phases: .down) { _ in
                            guard !commands.isEmpty else { return .ignored }
                            pick = min(commands.count - 1, pick + 1)
                            return .handled
                        }
                        .onKeyPress(.escape, phases: .down) { _ in
                            if !commands.isEmpty {
                                draft.wrappedValue = ""
                            } else if model.canStopTurn(session) {
                                model.stopTurn(session.id)
                            } else {
                                focused.wrappedValue = false
                            }
                            return .handled
                        }
                }
                .coreFont(size: MacTextSize.body)
                .frame(minHeight: 44, maxHeight: 160).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    Button {
                        attach()
                    } label: {
                        Image(systemName: "paperclip").frame(width: 28, height: 28)
                            .background(GlassInk.well, in: coreShape(Radius.control))
                    }
                    .buttonStyle(.plain).disabled(!enabled).help("Attach a file: adds its path to the message")
                    .accessibilityLabel("Attach a file")
                    chip(AgentWords.toolName(session.harness) + " · " + (session.model ?? "default model"))
                    stateChip
                    Spacer(minLength: Space.s2)
                    if bytes > AgentsModel.messageLimit / 2 {
                        Text("\(coreDecimal(Double(bytes) / 1024, 1)) / 16 KiB")
                            .coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(over ? palette.tone(.fail).ink : GlassInk.secondary)
                    }
                    if model.canStopTurn(session) {
                        Button {
                            model.stopTurn(session.id)
                        } label: {
                            Label("Stop turn", systemImage: "stop.fill").coreFont(
                                size: MacTextSize.body, weight: .semibold
                            )
                            .padding(.horizontal, Space.s3).frame(height: 28)
                            .background(GlassInk.well, in: coreShape(Radius.control))
                            .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                        }
                        .buttonStyle(.plain).help("Stop the current turn (Esc). The session stays open.")
                    }
                    if enabled {
                        AppActionTile(
                            title: session.idle ? "Send" : "Queue", symbol: "arrow.up", key: "↩", hue: GlassInk.blue,
                            prominent: true
                        ) { Task { await model.send(session.id) } }
                        .disabled(!model.canSend(session.id)).opacity(model.canSend(session.id) ? 1 : 0.5)
                        .help("Send the message (Return)")
                    }
                }
                .coreFont(size: MacTextSize.meta)
            }
            .padding(Space.s3)
            .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    on ? GlassInk.blue.opacity(0.7) : GlassInk.wellEdge, lineWidth: 1)
            }
            .opacity(enabled || session.over ? 1 : 0.6)
            .animation(Motion.out(Motion.ui), value: on)
            hints
        }
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s1)
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
                        Text(c.help).foregroundStyle(GlassInk.secondary)
                        Spacer(minLength: 0)
                    }
                    .coreFont(size: MacTextSize.body).padding(.horizontal, Space.s3).frame(height: 30)
                    .background(i == min(pick, list.count - 1) ? GlassInk.blue.opacity(0.25) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(GlassInk.well, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityLabel("Commands")
    }

    private func chip(_ t: String) -> some View {
        Text(t).padding(.horizontal, Space.s2).frame(height: 24).lineLimit(1)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    @ViewBuilder private var stateChip: some View {
        if model.waiting(session.id) {
            Text("Waiting for your answer").foregroundStyle(GlassInk.orangeInk)
        } else if model.canStopTurn(session) {
            HStack(spacing: 4) {
                Text("Working ·")
                Text(session.updatedAt, style: .timer).monospacedDigit()
            }
            .foregroundStyle(GlassInk.blueInk)
        } else if session.idle {
            Text("Waiting for you").foregroundStyle(GlassInk.green)
        }
    }

    private var hints: some View {
        Text("⇧↩ new line · ↑ edit last message · esc stop turn · / commands")
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
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
