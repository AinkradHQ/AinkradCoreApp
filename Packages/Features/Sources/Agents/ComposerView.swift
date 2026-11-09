import CoreUI
import SwiftUI

/// The reply field under a transcript: Return sends, the byte count shows against the 16 KiB the Core takes.
struct ComposerView: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    var focused: FocusState<Bool>.Binding
    @Environment(\.corePalette) private var palette

    private var draft: Binding<String> {
        Binding(get: { model.drafts[session.id] ?? "" }, set: { model.drafts[session.id] = $0 })
    }
    private var bytes: Int { (model.drafts[session.id] ?? "").utf8.count }
    private var over: Bool { bytes > AgentsModel.messageLimit }
    private var enabled: Bool {
        if case .running = session.state { return true }
        return false
    }

    private var placeholder: String {
        switch session.state {
        case .running: "Reply to \(session.harness)…"
        case .starting: "Starting. You can write when it is running."
        case .interrupted: "Resuming. You can write again when it is running."
        default: "This session ended. Resume it (top right) to send a message."
        }
    }

    var body: some View {
        let on = focused.wrappedValue
        HStack(alignment: .center, spacing: Space.s2) {
            Image(systemName: enabled ? "text.bubble" : "lock")
                .coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(on ? GlassInk.violet : GlassInk.secondary)
                .contentTransition(.symbolEffect(.replace)).coreBounce(on)
            TextField("Reply to the agent", text: draft, prompt: Text(placeholder))
                .accessibilityIdentifier("agent-composer")
                .textFieldStyle(.plain)
                .focused(focused)
                .disabled(!enabled)
                .onSubmit { Task { await model.send(session.id) } }
                .onKeyPress(.escape) {
                    focused.wrappedValue = false
                    return .handled
                }
            if bytes > 0 {
                Text("\(coreDecimal(Double(bytes) / 1024, bytes < 1024 ? 2 : 1)) / 16 KiB")
                    .coreFont(size: MacTextSize.meta, design: .monospaced)
                    .foregroundStyle(over ? palette.tone(.fail).ink : GlassInk.secondary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            // An ended session has one Resume, in its head; the composer just says so.
            if !session.over {
                AppActionTile(title: "Send", symbol: "paperplane.fill", key: "↩", hue: GlassInk.violet, prominent: true)
                {
                    Task { await model.send(session.id) }
                }
                .disabled(!model.canSend(session.id))
                .opacity(model.canSend(session.id) ? 1 : 0.5)
                .help("Send the message (Return)")
            }
        }
        .padding(.leading, Space.s3).padding(Space.s2)
        .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(on ? GlassInk.violet.opacity(0.6) : GlassInk.wellEdge, lineWidth: 1)
        }
        .shadow(color: GlassInk.violet.opacity(on ? 0.35 : 0), radius: 14)
        .opacity(enabled || session.over ? 1 : 0.6)
        .animation(Motion.out(Motion.ui), value: on)
        .animation(.spring(duration: 0.3), value: bytes > 0)
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s1)
    }
}
