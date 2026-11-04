import CoreUI
import SwiftUI

/// The reply field under a transcript: Return sends, the byte count shows against the 16 KiB the Core takes.
struct ComposerView: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

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
        HStack(alignment: .bottom, spacing: Space.s2) {
            TextField("Reply to the agent", text: draft, prompt: Text(placeholder))
                .accessibilityIdentifier("agent-composer")
                .textFieldStyle(.plain)
                .focused($focused)
                .disabled(!enabled)
                .onSubmit { Task { await model.send(session.id) } }
            Text("\(String(format: bytes < 1024 ? "%.2f" : "%.1f", Double(bytes) / 1024)) / 16 KiB")
                .font(.system(size: MacTextSize.meta, design: .monospaced))
                .foregroundStyle(over ? palette.tone(.fail).ink : palette.text2)
                .overlay(alignment: .leading) {
                    if over { Image(systemName: "exclamationmark.triangle").offset(x: -Space.s4) }
                }
            if session.over {
                Button("Resume") { model.resume(session.id) }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    .help("Start this session again from where it stopped")
            } else {
                Button("Send") { Task { await model.send(session.id) } }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    .disabled(!model.canSend(session.id))
                    .help("Send the message (Return)")
            }
        }
        .padding(.leading, Space.s3).padding(Space.s2)
        .background(palette.glassCard, in: coreShape(Radius.control))
        .overlay {
            coreShape(Radius.control).strokeBorder(
                focused ? palette.focusRing : palette.glassCardEdge, lineWidth: focused ? 2 : 1)
        }
        .coreDimWhenDisabled(enabled || session.over)
        .padding([.horizontal, .bottom], Space.s3)
    }
}
