import CoreUI
import SwiftUI

/// One session as a little stage (Ahmed, 2026-11-05: visual and animated, like the terminal tiles): the harness glyph
/// glowing in its own colour, breathing while it runs, pulsing orange when it waits on you; its state and model on the
/// stage; what it burned as a live line; the runner, tokens, cost and time below. Hover shows its actions with their keys.
struct SessionTile: View {
    let session: AgentSessionInfo
    let runner: String
    /// The session's name: its prompt's first line, else harness and id tail.
    var title: String = ""
    let waiting: Bool
    var selected = false
    var burn: [Double] = []
    var act: (Character) -> Void = { _ in }
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    static func hue(_ harness: String) -> Color {
        switch harness {
        case "claude": GlassInk.violet
        case "codex": GlassInk.green
        case "opencode": GlassInk.blue
        default: GlassInk.orange
        }
    }

    var body: some View {
        let st = AgentWords.status(session, waiting: waiting)
        let hue = Self.hue(session.harness)
        let state: Color =
            waiting ? GlassInk.orange : st.tone == .fail ? GlassInk.red : session.live ? GlassInk.green : GlassInk.slate
        VStack(alignment: .leading, spacing: Space.s2) {
            stage(hue: hue, state: state, label: st.label)
            HStack(spacing: Space.s2) {
                coreShape(2).fill(hue).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AgentWords.harnessName(session.harness))
                        .coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
                Spacer(minLength: 0)
                // The time, and in its place the actions while the pointer or the keyboard is on the tile.
                ZStack(alignment: .trailing) {
                    Label {
                        if session.live {
                            Text(session.createdAt, style: .timer)
                        } else {
                            Text(AgentWords.ago(session.endedAt ?? session.updatedAt))
                        }
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    .opacity(showActions ? 0 : 1)
                    actions.opacity(showActions ? 1 : 0).allowsHitTesting(showActions)
                }
                .animation(Motion.out(Motion.hover), value: showActions)
            }
            .padding(.horizontal, Space.s1)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s2)
        // The terminal tile's frame: the cursor tile tints in its harness colour; hover steps the fill and edge.
        .background(
            selected ? hue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected
                    ? hue.opacity(0.7)
                    : waiting ? GlassInk.orange.opacity(0.6) : hovering ? .white.opacity(0.26) : GlassInk.wellEdge,
                lineWidth: selected || waiting ? 1.5 : 1)
        }
        .opacity(session.live || waiting ? 1 : 0.85)
        .contentShape(coreShape(Radius.cardMac))
        .help("\(title)\n\(AgentWords.harnessName(session.harness)) on \(runner) · \(session.id)")
        .accessibilityActions {
            Button("Open") { act("o") }
            if session.live {
                Button("Cancel, stop after its current tool call") { act("c") }
                Button("Kill, stop at once") { act("k") }
            } else {
                Button("Resume") { act("r") }
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: selected)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
    }

    private var showActions: Bool { hovering || selected }

    private var facts: String {
        var parts = [runner]
        if let u = session.usage {
            parts.append("\(AgentWords.tokens(u.tokens)) tokens")
            if let c = AgentWords.cost(u.costMicros) { parts.append(c) }
        }
        return parts.joined(separator: " · ")
    }

    /// The stage: a dark glass well washed in the harness colour, the glyph glowing at the left, state at the top right.
    private func stage(hue: Color, state: Color, label: String) -> some View {
        // Larger text makes the stage taller and pushes the title below the state badge.
        let grow = max(1, TextSizePrefs.shared.scale)
        let alive = (session.live || waiting) && !reduce
        return ZStack(alignment: .topLeading) {
            // A still wash of the harness colour behind the glyph: a gradient, no blur and no loop.
            RadialGradient(
                colors: [hue.opacity(alive ? 0.4 : 0.25), .clear], center: .topLeading, startRadius: 0, endRadius: 150)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: AgentsModel.harnessSymbol(session.harness))
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(12)
                    )
                    .overlay { coreShape(12).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .symbolEffect(.pulse, options: .repeating, isActive: session.live && !waiting && !reduce)
                    .scaleEffect(shown || reduce ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(2)
                    Text(line).coreFont(size: MacTextSize.meta, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).padding(.bottom, Space.s3).padding(.top, Space.s3 + (grow - 1) * 28)
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                badge(state: state, label: label)
            }
            .padding(Space.s2)
            if burn.count >= 2 {
                VStack {
                    Spacer()
                    CoreSpark(burn, tone: state == GlassInk.red ? .fail : .run).frame(height: 18).opacity(0.8)
                }
                .padding(.horizontal, Space.s2).padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104 * grow, maxHeight: 104 * grow)
        .background(Color(red: 0.05, green: 0.06, blue: 0.1).opacity(0.75))
        .clipShape(coreShape(Radius.row))
        .overlay {
            coreShape(Radius.row).strokeBorder(
                selected ? hue.opacity(0.8) : waiting ? GlassInk.orange.opacity(0.7) : .white.opacity(0.12),
                lineWidth: selected || waiting ? 1.5 : 1)
        }
    }

    /// What the stage says under the model: what it is doing, or how it ended.
    private var line: String {
        if waiting { return "› waiting for your approval" }
        if session.live { return "› working on \(runner)" }
        return "› "
            + (session.outcomeReason.map(AgentWords.reasonWords) ?? AgentWords.status(session, waiting: false).label)
    }

    private func badge(state: Color, label: String) -> some View {
        HStack(spacing: 5) {
            if waiting {
                Image(systemName: "hand.raised.fill").corePulse()
            } else if session.live {
                Image(systemName: "waveform").coreIterate()
            } else {
                coreShape(2).fill(state).frame(width: 6, height: 6)
            }
            Text(label).lineLimit(1)
        }
        .coreFont(size: 10, weight: .semibold).foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 7).frame(height: 20)
        .background(state.opacity(0.3), in: coreShape(5))
        .overlay { coreShape(5).strokeBorder(state.opacity(0.5), lineWidth: 1) }
    }

    /// The tile's actions in its footer row, one colour, with what each does on hover. Keys are 10 pt.
    private var actions: some View {
        HStack(spacing: 6) {
            mini("arrow.up.forward.app", "↩", "Open the session", "o")
            if session.live {
                mini(
                    "stop.fill", "C",
                    "Cancel: asks \(AgentWords.harnessName(session.harness)) to stop after its current tool call", "c")
                mini(
                    "xmark.octagon", "K",
                    "Kill: stops it at once; can leave files half-written. Use it if Cancel did not work", "k")
            } else {
                mini(
                    "arrow.clockwise", "R", "Resume: start it again from where it stopped. The transcript is kept", "r")
            }
        }
    }

    private func mini(_ symbol: String, _ key: String, _ help: String, _ code: Character) -> some View {
        Button {
            act(code)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(key).coreFont(size: 10, weight: .semibold, design: .rounded)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 7).frame(height: 24)
            .background(GlassInk.wellHover, in: coreShape(Radius.chip))
            .overlay { coreShape(Radius.chip).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .contentShape(coreShape(Radius.chip))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityHidden(true)
    }
}
