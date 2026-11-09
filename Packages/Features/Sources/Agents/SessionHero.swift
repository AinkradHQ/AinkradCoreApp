import CoreUI
import SwiftUI

/// The top of a session pane (Ahmed, 2026-11-05: visual, animated, keyboard friendly): the session's stage, like its
/// tile. The harness glyph glows in its colour (breathing while it runs), the state and how it ended in words, what it
/// used as chips, the burn line, and its actions at the top right as tiles with their keys.
struct SessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let waiting = model.waiting(session.id)
        let st = AgentWords.status(session, waiting: waiting)
        let hue = SessionTile.hue(session.harness)
        let state: Color =
            waiting ? GlassInk.orange : st.tone == .fail ? GlassInk.red : session.live ? GlassInk.green : GlassInk.slate
        let alive = (session.live || waiting) && !reduce
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: AgentsModel.harnessSymbol(session.harness))
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(13)
                    )
                    .overlay { coreShape(13).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .corePulse(alive)
                    .scaleEffect(shown || reduce ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s2) {
                        Text(model.title(session)).coreFont(size: MacTextSize.large, weight: .bold).lineLimit(2)
                            .help(model.title(session) + "\n" + session.id)
                        badge(st.label, st.symbol, state, live: session.live, waiting: waiting)
                    }
                    Text(subtitle).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                actions
            }
            HStack(spacing: Space.s2) {
                AppStatChip("sparkles", AgentWords.harnessName(session.harness), hue)
                AppStatChip("server.rack", model.runnerName(session.runner), hue).help("Runner \(session.runner)")
                if let m = session.model { AppStatChip("brain", m, GlassInk.violet) }
                if let r = session.route {
                    if let c = SessionCues.chain(r, name: model.chainName(r)) {
                        AppStatChip("link", c, GlassInk.blue).help(SessionCues.step(r).map { "Now on \($0)" } ?? "")
                    }
                    if let a = r.account {
                        AppStatChip("key", model.accountNames[a] ?? "an account", GlassInk.orange)
                            .help(SessionCues.repicked(r.repicked) ?? "The account this session holds")
                    }
                }
                AppStatChip(
                    "arrow.down.circle", "\(session.usage.map { AgentWords.tokens($0.input) } ?? "0") in", GlassInk.blue
                )
                AppStatChip(
                    "arrow.up.circle", "\(session.usage.map { AgentWords.tokens($0.output) } ?? "0") out",
                    GlassInk.green)
                if let c = AgentWords.cost(session.usage?.costMicros) { AppStatChip("dollarsign", c, GlassInk.orange) }
                if let r = session.resumes, r > 0 {
                    AppStatChip("arrow.clockwise", "resumed \(r)×", GlassInk.slate)
                }
                Spacer(minLength: 0)
                timer
            }
            if let l = model.ledgers[session.id] { SessionSpendStrip(session: session, ledger: l).transition(.opacity) }
            let burn = model.sessions.burn[session.id] ?? []
            if burn.count >= 2 {
                CoreSpark(burn, tone: st.tone == .fail ? .fail : .run).frame(height: 26)
                    .help("Tokens used, as this Mac saw them change")
            }
            if let stop = model.stopping[session.id], session.live {
                Label(
                    stop == .killing
                        ? "Killing: stopping it on the runner now."
                        : "Cancelling: it finishes the tool call in flight, then ends. K kills at once.",
                    systemImage: "hourglass"
                )
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.orangeInk)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduce)
                .accessibilityIdentifier("session-stopping")
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s4)
        .background {
            Color(red: 0.05, green: 0.06, blue: 0.1).opacity(0.55)
                .overlay {
                    // A still wash of the harness colour: a gradient, no blur and no loop.
                    RadialGradient(
                        colors: [hue.opacity(alive ? 0.3 : 0.18), .clear], center: .leading, startRadius: 0,
                        endRadius: 260)
                }
                .clipShape(coreShape(Radius.cardMac))
        }
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                waiting ? GlassInk.orange.opacity(0.6) : hue.opacity(0.35), lineWidth: 1)
        }
        .padding([.horizontal, .top], Space.s3).padding(.bottom, Space.s2)
        .animation(Motion.out(Motion.ui), value: shown)
        .onAppear { shown = true }
        .task(id: session.id) { await model.followLedger(session.id) }
        .task(id: session.id) { await model.followRoute(session.id) }
        .accessibilityElement(children: .contain)
    }

    /// What happened, in words: why it ended, or what it is doing.
    private var subtitle: String {
        let r = model.runnerName(session.runner)
        if model.waiting(session.id) { return "Waiting for your approval below." }
        switch session.state {
        case .starting: return "Waiting for \(r) to launch \(session.harness). This usually takes a few seconds."
        case .interrupted: return "\(r) restarted. It resumes by itself."
        case .lost: return "\(r) dropped it and could not resume it. The transcript up to that point is kept."
        case .ended:
            if session.stoppedByBudget {
                return "A budget ran out, so Core stopped it. Raise the budget or use another account, then resume."
            }
            if let why = session.outcomeReason, !why.isEmpty { return AgentWords.reasonWords(why) }
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
        .coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary).monospacedDigit()
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s2) {
            if session.live {
                AppActionTile(title: "Cancel", symbol: "stop.fill", key: "C", hue: GlassInk.orange) {
                    model.confirmCancel(session.id)
                }
                .disabled(model.stopping[session.id] != nil)
                .help(
                    "Cancel asks \(AgentWords.harnessName(session.harness)) to stop after its current tool call. Safe; try this first."
                )
                AppActionTile(title: "Kill", symbol: "xmark.octagon", key: "K", hue: GlassInk.red) {
                    model.confirmKill(session.id)
                }
                .help(
                    "Kill stops it at once on the runner and can leave files half-written. Use it only if Cancel did not work."
                )
            } else {
                if case .succeeded? = session.outcome {
                    AppActionTile(title: "Wake", symbol: "alarm", key: "W", hue: GlassInk.violet) {
                        model.wake(session.id)
                    }
                    .help(
                        "Wake queues another turn for this finished agent. It keeps the same session. Resume restarts one that stopped."
                    )
                }
                if session.stoppedByBudget {
                    AppActionTile(title: "Raise budget…", symbol: "arrow.up.circle", key: "", hue: GlassInk.blue) {
                        model.raiseBudget(session)
                    }
                    .help("Open the budget that stopped this session, raise it, then resume")
                    AppActionTile(title: "Open Accounts", symbol: "creditcard", key: "", hue: GlassInk.slate) {
                        model.openAccounts()
                    }
                }
                AppActionTile(title: "Resume", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue, prominent: true)
                {
                    model.resume(session.id)
                }
                .help("Resume starts this session again from where it stopped. The transcript is kept.")
            }
        }
    }

    private func badge(_ label: String, _ symbol: String, _ c: Color, live: Bool, waiting: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: waiting ? "hand.raised.fill" : live ? "waveform" : symbol)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: live && !waiting && !reduce)
                .symbolEffect(.pulse, options: .repeating, isActive: waiting && !reduce)
            Text(label).lineLimit(1)
        }
        .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 8).frame(height: 22)
        .background(c.opacity(0.3), in: coreShape(6))
        .overlay { coreShape(6).strokeBorder(c.opacity(0.55), lineWidth: 1) }
    }
}
