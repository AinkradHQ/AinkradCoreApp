import CoreUI
import SwiftUI

/// One session as a little stage (Ahmed, 2026-11-05: visual and animated, like the terminal tiles): the harness glyph
/// glowing in its own colour, breathing while it runs, pulsing orange when it waits on you; its state and model on the
/// stage; what it burned as a live line; the runner, tokens, cost and time below. Hover shows its actions with their keys.
struct SessionTile: View {
    let session: AgentSessionInfo
    let runner: String
    let waiting: Bool
    var selected = false
    var burn: [Double] = []
    var act: (Character) -> Void = { _ in }
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

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
                .overlay(alignment: .bottomTrailing) {
                    // The keyboard's tile shows its actions too, so every key is visible where it acts.
                    if hovering || selected { actions.transition(.opacity.combined(with: .move(edge: .trailing))) }
                }
            HStack(spacing: Space.s2) {
                coreShape(2).fill(hue).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.harness.capitalized).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .lineLimit(1)
                    Text(facts).font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                        .lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
                Spacer(minLength: 0)
                Label {
                    if session.live {
                        Text(session.createdAt, style: .timer)
                    } else {
                        Text(AgentWords.ago(session.endedAt ?? session.updatedAt))
                    }
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
            .padding(.horizontal, Space.s1)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s2)
        .opacity(session.live || waiting ? 1 : 0.85)
        .contentShape(coreShape(Radius.cardMac))
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.25), value: hovering)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
    }

    private var facts: String {
        var parts = [runner, session.shortID]
        if let u = session.usage {
            parts.append("\(AgentWords.tokens(u.tokens)) tokens")
            if let c = AgentWords.cost(u.costMicros) { parts.append(c) }
        }
        return parts.joined(separator: " · ")
    }

    /// The stage: a dark glass well washed in the harness colour, the glyph glowing at the left, state at the top right.
    private func stage(hue: Color, state: Color, label: String) -> some View {
        let alive = (session.live || waiting) && !reduce
        return ZStack(alignment: .topLeading) {
            // A soft glow drifts behind the glyph while the session is alive.
            coreShape(40).fill(hue.opacity(0.55)).frame(width: 120, height: 120).blur(radius: 36)
                .offset(x: alive && shown ? 40 : -10, y: alive && shown ? 10 : -20)
                .animation(alive ? .easeInOut(duration: 3.2).repeatForever() : .default, value: shown)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: AgentsModel.harnessSymbol(session.harness))
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(12)
                    )
                    .overlay { coreShape(12).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .shadow(color: hue.opacity(0.6), radius: alive ? 14 : 6)
                    .symbolEffect(.pulse, options: .repeating, isActive: session.live && !waiting && !reduce)
                    .symbolEffect(.bounce, value: hovering)
                    .scaleEffect(shown ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.model ?? "Default model").font(.system(size: MacTextSize.body, weight: .semibold))
                        .lineLimit(1)
                    Text(line).font(.system(size: MacTextSize.meta, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
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
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104)
        .background(Color(red: 0.05, green: 0.06, blue: 0.1).opacity(0.75))
        .clipShape(coreShape(Radius.row))
        .overlay {
            coreShape(Radius.row).strokeBorder(
                selected ? hue.opacity(0.8) : waiting ? GlassInk.orange.opacity(0.7) : .white.opacity(0.12),
                lineWidth: selected || waiting ? 1.5 : 1)
        }
        .shadow(color: (waiting ? GlassInk.orange : hue).opacity(selected || hovering || waiting ? 0.4 : 0), radius: 14)
    }

    /// What the stage says under the model: what it is doing, or how it ended.
    private var line: String {
        if waiting { return "› waiting for your approval" }
        if session.live { return "› working on \(runner)" }
        return "› " + (session.outcomeReason ?? "ended")
    }

    private func badge(state: Color, label: String) -> some View {
        HStack(spacing: 5) {
            if waiting {
                Image(systemName: "hand.raised.fill").symbolEffect(.pulse, options: .repeating)
            } else if session.live {
                Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                coreShape(2).fill(state).frame(width: 6, height: 6)
            }
            Text(label).lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 7).frame(height: 20)
        .background(state.opacity(0.3), in: coreShape(5))
        .overlay { coreShape(5).strokeBorder(state.opacity(0.5), lineWidth: 1) }
    }

    /// Hover actions as icon tiles with their keys, bouncing in.
    private var actions: some View {
        HStack(spacing: 6) {
            mini("arrow.up.forward.app", "↩", GlassInk.blue, "o")
            if session.live {
                mini("stop.fill", "C", GlassInk.orange, "c")
                mini("xmark.octagon", "K", GlassInk.red, "k")
            } else {
                mini("arrow.clockwise", "R", GlassInk.green, "r")
            }
        }
        .padding(8)
    }

    private func mini(_ symbol: String, _ key: String, _ hue: Color, _ code: Character) -> some View {
        Button {
            act(code)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).symbolEffect(.bounce, value: hovering)
                Text(key).font(.system(size: 8, weight: .bold, design: .rounded)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [hue, hue.opacity(0.65)], startPoint: .top, endPoint: .bottom), in: coreShape(7)
            )
            .overlay { coreShape(7).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}
