import CoreUI
import SwiftUI

/// One session as a little stage (Ahmed, 2026-11-05: visual, like the terminal tiles): the harness glyph on a blue tile,
/// its state and model on the stage; what it burned as a live line; the runner, tokens, cost and time below. The
/// keyboard's tile and the hovered one show their actions with their keys, laid out always and faded in.
struct SessionTile: View {
    let session: AgentSessionInfo
    let runner: String
    let waiting: Bool
    var selected = false
    var burn: [Double] = []
    var act: (Character) -> Void = { _ in }
    @State private var hovering = false

    var body: some View {
        let st = AgentWords.status(session, waiting: waiting)
        let showActions = hovering || selected
        VStack(alignment: .leading, spacing: Space.s2) {
            stage(st: st)
                .overlay(alignment: .bottomTrailing) {
                    actions.opacity(showActions ? 1 : 0).allowsHitTesting(showActions)
                        .accessibilityHidden(!showActions)
                }
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(AgentWords.harness(session.harness)).font(
                        .system(size: MacTextSize.headline, weight: .semibold)
                    )
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
        .background(
            selected ? GlassInk.blue.opacity(0.16) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected ? GlassInk.blue.opacity(0.7) : waiting ? GlassInk.orange.opacity(0.6) : GlassInk.wellEdge,
                lineWidth: 1)
        }
        .opacity(session.live || waiting ? 1 : 0.85)
        .contentShape(coreShape(Radius.cardMac))
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.ui), value: selected)
        .help("\(session.harness) · \(session.id)")
        .accessibilityElement(children: .combine)
    }

    private var facts: String {
        var parts = [runner]
        if let u = session.usage {
            parts.append("\(AgentWords.tokens(u.tokens)) tokens")
            if let c = AgentWords.cost(u.costMicros) { parts.append(c) }
        }
        return parts.joined(separator: " · ")
    }

    /// The stage: a well, the glyph at the left, state at the top right, the burn line along the bottom.
    private func stage(st: (label: String, tone: Tone, symbol: String)) -> some View {
        ZStack(alignment: .topLeading) {
            // Top-aligned: the hover actions sit in the bottom right and never cover these lines.
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile(AgentsModel.harnessSymbol(session.harness), hue: GlassInk.blue, size: Space.s8 * 1.5)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(session.model ?? "Default model").font(.system(size: MacTextSize.body, weight: .semibold))
                        .lineLimit(1)
                    Text(line).font(.system(size: MacTextSize.meta, design: .monospaced))
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Spacer()
                StateBadge(st.label, tone: st.tone, symbol: st.symbol)
            }
            .padding(Space.s2)
            if burn.count >= 2 {
                VStack {
                    Spacer()
                    CoreSpark(burn, tone: st.tone == .fail ? .fail : .run).frame(height: Space.s5).opacity(0.8)
                }
                .padding(.horizontal, Space.s2).padding(.bottom, Space.s1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Space.s8 * 3 + Space.s2, maxHeight: Space.s8 * 3 + Space.s2)
        .background(GlassInk.well)
        .clipShape(coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    /// What the stage says under the model: what it is doing, or how it ended.
    private var line: String {
        if waiting { return "› waiting for your approval" }
        if session.live { return "› working on \(runner)" }
        return "› " + (session.outcomeReason ?? "ended")
    }

    /// Hover actions as mini buttons with their keys.
    private var actions: some View {
        HStack(spacing: Space.s1) {
            TileMiniButton("arrow.up.forward.app", key: "↩", label: "Open session") { act("o") }
            if session.live {
                TileMiniButton("stop.fill", key: "C", label: "Cancel session") { act("c") }
                TileMiniButton("xmark.octagon", key: "K", label: "Kill session", destructive: true) { act("k") }
            } else {
                TileMiniButton("arrow.clockwise", key: "R", label: "Resume session") { act("r") }
            }
        }
        .padding(Space.s2)
    }
}
