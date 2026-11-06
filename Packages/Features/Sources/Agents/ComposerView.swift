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
        default: "This session ended. Resume it to send a message."
        }
    }

    var body: some View {
        let on = focused.wrappedValue
        HStack(alignment: .center, spacing: Space.s2) {
            Image(systemName: enabled ? "text.bubble" : "lock")
                .font(.system(size: MacTextSize.body, weight: .semibold))
                .foregroundStyle(on ? GlassInk.blue : GlassInk.secondary)
                .contentTransition(.symbolEffect(.replace))
            TextField("Reply to the agent", text: draft, prompt: Text(placeholder))
                .accessibilityIdentifier("agent-composer")
                .textFieldStyle(.plain)
                .focused(focused)
                .focusEffectDisabled()
                .disabled(!enabled)
                .onSubmit { Task { await model.send(session.id) } }
                .onKeyPress(.escape) {
                    focused.wrappedValue = false
                    return .handled
                }
            Text(String(format: "%.1f of 16 KiB", Double(bytes) / 1024))
                .font(.system(size: MacTextSize.meta, design: .monospaced)).monospacedDigit()
                .foregroundStyle(over ? palette.tone(.fail).ink : GlassInk.secondary)
                .opacity(bytes > 0 ? 1 : 0)
            // A session that is over is resumed from the hero above; the composer only sends.
            if !session.over {
                AppActionTile(title: "Send", symbol: "paperplane.fill", key: "↩", hue: GlassInk.blue, prominent: true) {
                    Task { await model.send(session.id) }
                }
                .disabled(!model.canSend(session.id))
                .opacity(model.canSend(session.id) ? 1 : 0.5)
                .help("Send the message (Return)")
            }
        }
        .padding(.leading, Space.s3).padding(Space.s2)
        .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .opacity(enabled || session.over ? 1 : 0.6)
        .animation(Motion.out(Motion.hover), value: on)
        .animation(Motion.out(Motion.ui), value: bytes > 0)
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s1)
    }
}
