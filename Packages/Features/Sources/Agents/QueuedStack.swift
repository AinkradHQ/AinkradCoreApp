import CoreUI
import SwiftUI

/// The session screen's surfaces (Ahmed, 2026-11-16: "Day theme is very bad"). By night they are the glass wells. By day a
/// darker tint over a warm, blurred wallpaper read as muddy beige on beige; Mac light mode lifts content instead: lighter
/// than the pane, with a soft shadow.
enum SessionInk {
    static let field = GlassInk.adaptive(.white.opacity(0.08), day: .white.opacity(0.74))
    static let fieldOn = GlassInk.adaptive(.white.opacity(0.13), day: .white.opacity(0.92))
    static let row = GlassInk.adaptive(.white.opacity(0.08), day: .white.opacity(0.58))
    static let rowHover = GlassInk.adaptive(.white.opacity(0.13), day: .white.opacity(0.8))
    static let selected = GlassInk.adaptive(.white.opacity(0.13), day: .white.opacity(0.85))
    /// The lift under a day surface; none by night, where the wells sit in the glass.
    static let lift = GlassInk.adaptive(.clear, day: .black.opacity(0.08))
}

extension View {
    /// A content surface of the session screen. By night the card well it always was; by day lighter than the pane, with a
    /// soft lift.
    func sessionSurface(_ fill: Color = SessionInk.row, radius: CGFloat = Radius.control) -> some View {
        modifier(SessionSurface(fill: fill, radius: radius))
    }
}

private struct SessionSurface: ViewModifier {
    let fill: Color
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            content.coreWell(radius: radius)
        } else {
            content.background(fill, in: coreShape(radius)).shadow(color: SessionInk.lift, radius: 6, y: 2)
        }
    }
}

/// Messages typed during a turn, above the field (as in Claude Code and Codex): they wait there and go out together when
/// the turn ends. Each can go back to the field to change, be sent now, or be removed. A new one rises out of the field;
/// a sent or removed one fades.
struct QueuedStack: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let list = model.queued[session.id] ?? []
        VStack(alignment: .leading, spacing: Space.s1) {
            if !list.isEmpty {
                Label(
                    list.count == 1
                        ? "Queued · goes out when this turn ends · ↑ to edit"
                        : "\(list.count) queued · go out together when this turn ends · ↑ to edit",
                    systemImage: "clock"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .padding(.leading, Space.s1)
                .transition(.opacity)
            }
            ForEach(list) { m in
                row(m)
                    .transition(
                        .asymmetric(
                            insertion: reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s3)),
                            removal: .opacity))
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: list)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queued messages")
    }

    private func row(_ m: QueuedMessage) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            Text(m.text).coreFont(size: MacTextSize.body).foregroundStyle(palette.text).lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(m.text)
            CoreIconButton(symbol: "pencil", label: "Edit") { model.editQueued(session.id, m.id) }
                .help("Back to the field to change it")
            CoreIconButton(symbol: "arrow.up", label: "Send now") { model.sendQueuedNow(session.id, m.id) }
                .help("Send it now: the tool reads it at its next step, without waiting for the turn to end")
            CoreIconButton(symbol: "xmark", label: "Remove") { model.removeQueued(session.id, m.id) }
                .help("Remove it from the queue")
        }
        .padding(.leading, Space.s3).padding(.trailing, Space.s1).padding(.vertical, Space.s1)
        .sessionSurface(SessionInk.row, radius: Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queued: \(m.text)")
    }
}
