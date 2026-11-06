import CoreUI
import SwiftUI

/// The top of a session pane (Ahmed, 2026-11-05: visual, keyboard friendly): the session's stage, like its tile. The
/// harness glyph on a blue tile, the state and how it ended in words, what it used as chips, the burn line, and its
/// actions at the top right with their keys.
struct SessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let waiting = model.waiting(session.id)
        let st = AgentWords.status(session, waiting: waiting)
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                IconTile(
                    AgentsModel.harnessSymbol(session.harness), hue: GlassInk.blue, size: Space.s8 + Space.s6,
                    bounce: shown
                )
                .scaleEffect(shown || reduce ? 1 : 0.6)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    HStack(spacing: Space.s2) {
                        Text(AgentWords.harness(session.harness)).font(
                            .system(size: MacTextSize.large, weight: .semibold))
                        StateBadge(st.label, tone: st.tone, symbol: st.symbol)
                    }
                    Text(subtitle).font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                actions
            }
            HStack(spacing: Space.s2) {
                AppStatChip("server.rack", model.runnerName(session.runner), GlassInk.slate)
                if let m = session.model { AppStatChip("brain", m, GlassInk.slate) }
                AppStatChip(
                    "arrow.down.square", "\(session.usage.map { AgentWords.tokens($0.input) } ?? "0") in",
                    GlassInk.slate
                )
                AppStatChip(
                    "arrow.up.square", "\(session.usage.map { AgentWords.tokens($0.output) } ?? "0") out",
                    GlassInk.slate)
                if let c = AgentWords.cost(session.usage?.costMicros) { AppStatChip("dollarsign", c, GlassInk.slate) }
                if let r = session.resumes, r > 0 {
                    AppStatChip("arrow.clockwise", "resumed \(r)×", GlassInk.slate)
                }
                Spacer(minLength: 0)
                timer
            }
            if let l = model.ledgers[session.id] { SessionSpendStrip(session: session, ledger: l).transition(.opacity) }
            let burn = model.sessions.burn[session.id] ?? []
            if burn.count >= 2 {
                CoreSpark(burn, tone: st.tone == .fail ? .fail : .run).frame(height: Space.s6 + Space.s1)
                    .help("Tokens used, as this Mac saw them change")
            }
            if let stop = model.stopping[session.id], session.live {
                Label(
                    stop == .killing
                        ? "Killing: stopping it on the runner now"
                        : "Cancelling: it finishes the tool call in flight, then ends. K kills at once",
                    systemImage: "hourglass"
                )
                .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.orange)
                .accessibilityIdentifier("session-stopping")
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1)
        .padding([.horizontal, .top], Space.s3).padding(.bottom, Space.s2)
        .animation(Motion.out(Motion.move), value: shown)
        .onAppear { shown = true }
        .task(id: session.id) { await model.followLedger(session.id) }
        .accessibilityElement(children: .contain)
    }

    /// What happened, in words: why it ended, or what it is doing.
    private var subtitle: String {
        let r = model.runnerName(session.runner)
        if model.waiting(session.id) { return "Waiting for your approval below." }
        switch session.state {
        case .starting:
            return
                "Waiting for \(r) to launch \(AgentWords.harness(session.harness)). This usually takes a few seconds."
        case .interrupted: return "\(r) restarted. It resumes by itself."
        case .lost: return "\(r) dropped it and could not resume it. The transcript is kept."
        case .ended:
            if let why = session.outcomeReason, !why.isEmpty { return why }
            switch session.outcome {
            case .succeeded?: return "It finished what it was asked."
            case .failed?: return "It stopped with an error. The last output is below."
            case .cancelled?: return "It was cancelled. What it did stays in the transcript."
            case .tokenCap?: return "It used the tokens it was allowed and stopped."
            case .stalled?: return "It stopped making progress."
            default: return "The Core did not say how it ended."
            }
        default: return "Working on \(r)."
        }
    }

    private var timer: some View {
        Label {
            if session.live {
                Text(session.createdAt, style: .timer)
            } else if let end = session.endedAt {
                Text("ran \(AgentWords.clock(end.timeIntervalSince(session.createdAt))) · \(AgentWords.ago(end))")
            }
        } icon: {
            Image(systemName: "clock")
        }
        .font(.system(size: MacTextSize.meta, weight: .medium)).foregroundStyle(GlassInk.secondary).monospacedDigit()
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s2) {
            if session.live {
                AppActionTile(title: "Cancel", symbol: "stop.fill", key: "C", hue: GlassInk.slate) {
                    model.confirmCancel(session.id)
                }
                .disabled(model.stopping[session.id] != nil)
                .help("Ask \(AgentWords.harness(session.harness)) to stop after its current tool call")
                AppActionTile(title: "Kill", symbol: "xmark.octagon", key: "K", hue: GlassInk.red) {
                    model.confirmKill(session.id)
                }
                .help("Stop it at once; can leave files half-written")
            } else {
                if case .succeeded? = session.outcome {
                    AppActionTile(title: "Wake", symbol: "alarm", key: "W", hue: GlassInk.slate) {
                        model.wake(session.id)
                    }
                    .help("Queue another turn for this agent")
                }
                AppActionTile(title: "Resume", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue, prominent: true)
                {
                    model.resume(session.id)
                }
                .help("Start this session again from where it stopped")
            }
        }
    }
}
