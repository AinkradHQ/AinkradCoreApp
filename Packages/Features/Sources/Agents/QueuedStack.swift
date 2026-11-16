import CoreUI
import SwiftUI

/// The session screen's colours (direction A, approved 2026-11-16, `Designs/core/session-v2/a.css`). The page itself follows
/// the Appearance setting (Look: transparency and blur, Ahmed 2026-11-16); the fills on it are tints, no lines.
enum SessionInk {
    private static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(
            red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255,
            opacity: a)
    }
    private static func ink(_ a: Double) -> Color { hex(0x1F1E1B, a) }
    private static func light(_ a: Double) -> Color { .white.opacity(a) }

    static let page = GlassInk.adaptive(hex(0x262624), day: hex(0xFAF9F5))
    /// The sidebar and the side panel, floating over the page.
    static let chrome = GlassInk.adaptive(hex(0x1F1F1D, 0.86), day: hex(0xF1EFE8, 0.82))
    static let text = GlassInk.adaptive(hex(0xECEAE3), day: hex(0x1F1E1B))
    static let text2 = GlassInk.adaptive(hex(0xA9A59C), day: hex(0x66625A))
    static let hover = GlassInk.adaptive(light(0.06), day: ink(0.05))
    static let selected = GlassInk.adaptive(light(0.09), day: ink(0.08))
    static let field = GlassInk.adaptive(light(0.06), day: ink(0.05))
    static let fieldOn = GlassInk.adaptive(light(0.09), day: ink(0.07))
    static let row = GlassInk.adaptive(light(0.06), day: ink(0.05))
    static let rowHover = hover
    // Tints, not solid colours, so they sit on whatever the Appearance setting (Look) shows behind them.
    static let bubble = GlassInk.adaptive(light(0.09), day: ink(0.07))
    static let card = GlassInk.adaptive(light(0.05), day: ink(0.04))
    static let code = GlassInk.adaptive(.black.opacity(0.22), day: ink(0.045))
    /// The floating stack at the bottom (approval and composer).
    static let float = GlassInk.adaptive(hex(0x32322F, 0.92), day: light(0.9))
    static let floatShadow = GlassInk.adaptive(.black.opacity(0.35), day: hex(0x3C321E, 0.10))
    /// Graphite: the one filled button colour (send, stop, approve).
    static let ink = GlassInk.adaptive(hex(0xECEAE3), day: hex(0x2A2925))
    static let onInk = GlassInk.adaptive(hex(0x1F1E1B), day: hex(0xFAF9F5))
    static let bad = GlassInk.adaptive(hex(0xF08379), day: hex(0xB33A31))
    /// Behind the conversation by day: a little paper over the Look, so words never sit on bare wallpaper (review
    /// 2026-11-16: secondary text read at about 2:1); none by night, where the dark Look already carries it.
    static let backing = GlassInk.adaptive(.clear, day: hex(0xFAF9F5, 0.55))
    /// Kept for the old call sites: no lift.
    static let lift = Color.clear
}

extension View {
    /// A content card of the session screen (tasks, plans, approvals, code): a fill, no line, no shadow.
    func sessionSurface(_ fill: Color = SessionInk.card, radius: CGFloat = Radius.cardMac) -> some View {
        background(fill, in: coreShape(radius))
    }

    /// The floating bottom stack (approval, composer): above the page, with a soft two-layer shadow.
    func sessionFloat(radius: CGFloat = 12) -> some View {
        // The shadow from the shape only, never from the text inside (a content shadow redraws every glyph).
        background {
            coreShape(radius).fill(SessionInk.float)
                .shadow(color: SessionInk.floatShadow.opacity(0.5), radius: 1, y: 1)
                .shadow(color: SessionInk.floatShadow, radius: 16, y: 12)
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
                .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                .padding(.leading, Space.s1)
                .transition(.opacity)
            }
            ForEach(list) { m in
                row(m)
                    .transition(
                        .asymmetric(
                            insertion: reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s3)),
                            // Sent at the turn's end, it lifts toward the conversation as it fades.
                            removal: reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s4))))
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
        .padding(.leading, Space.s3).padding(.trailing, Space.s1).frame(minHeight: 32)
        .background(SessionInk.row, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queued: \(m.text)")
    }
}

/// Graphite: the screen's one filled button (send, stop, approve), dark ink by day and light ink by night; presses to 0.97,
/// Reduce Motion darkens instead.
struct GraphiteButtonStyle: ButtonStyle {
    var iconOnly = false
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, iconOnly: iconOnly) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let iconOnly: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false

        var body: some View {
            configuration.label
                .coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(SessionInk.onInk)
                .padding(.horizontal, iconOnly ? 0 : Space.s3)
                .frame(minWidth: iconOnly ? 28 : nil, minHeight: 28)
                .background(SessionInk.ink.opacity(hover ? 0.88 : 1), in: coreShape(Radius.control))
                .overlay {
                    coreShape(Radius.control).fill(.black.opacity(configuration.isPressed && reduce ? 0.18 : 0))
                }
                .opacity(enabled ? 1 : 0.3)
                .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
                .animation(Motion.out(Motion.hover), value: hover)
                .animation(Motion.press(Motion.press), value: configuration.isPressed)
                .onHover { hover = $0 }
                .contentShape(coreShape(Radius.control))
        }
    }
}

/// End Session…: neutral ink at rest, red words and a red tint on hover (review 2026-11-16).
struct EndButtonStyle: ButtonStyle {
    var iconOnly = false
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, iconOnly: iconOnly) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let iconOnly: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false

        var body: some View {
            configuration.label
                .coreFont(size: iconOnly ? MacTextSize.meta : MacTextSize.body, weight: .semibold)
                .foregroundStyle(hover ? SessionInk.bad : SessionInk.text2)
                .padding(.horizontal, iconOnly ? Space.s2 : Space.s3)
                .frame(minHeight: iconOnly ? MacSize.controlSm : MacSize.controlMd)
                .background(hover ? SessionInk.bad.opacity(0.12) : .clear, in: coreShape(Radius.control))
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
                .animation(Motion.out(Motion.hover), value: hover)
                .onHover { hover = $0 }
                .contentShape(coreShape(Radius.control))
        }
    }
}
