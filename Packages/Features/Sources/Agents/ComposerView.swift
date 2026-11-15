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
    @Environment(\.corePalette) private var palette
    @State private var pick = 0
    @State private var dropping = false
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
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        } else {
            composer
        }
    }

    private var composer: some View {
        let on = focused.wrappedValue
        return VStack(alignment: .leading, spacing: Space.s2) {
            if !commands.isEmpty { palette(commands) }
            // What went wrong with the last send (or resume, wake...), right where you typed it.
            if let n = model.notices[session.id] {
                CoreNotice(symbol: n.symbol, title: n.title, text: n.detail, tone: n.tone)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
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
            // ponytail: "this Mac" is guessed from the runner's name; the Core does not say which runner is local yet.
            if !Self.onThisMac(model.runnerName(session.runner)) {
                Label(
                    "Files are read from this Mac; \(model.runnerName(session.runner)) can't open them yet.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
            }
        }
    }

    private func remove(_ url: URL) { model.attachments[session.id] = files.filter { $0 != url } }

    static func onThisMac(_ runner: String) -> Bool {
        let here = (Host.current().localizedName ?? "").lowercased()
        let r = runner.lowercased()
        return r.contains("this mac") || (!here.isEmpty && (r == here || r.hasPrefix(here) || here.hasPrefix(r)))
    }
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
