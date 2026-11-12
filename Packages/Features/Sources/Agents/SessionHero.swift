import CoreUI
import SwiftUI

/// The top of a session pane (N33, variant B): one line of about 56 pt with the harness tile, the title, the state and the
/// actions, and under it a details strip that the Details button shows or hides (remembered on this Mac). The strip holds
/// what used to fill the header: runner, account, order, tokens, cost, wakes, the key note and the spend chart.
struct SessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    /// The window is wide: the side panel carries the details, so no strip and no Details button.
    var panel = false
    @AppStorage("agents.detailsStrip") private var showDetails = true
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let waiting = model.waiting(session.id)
        let st = AgentWords.status(session, waiting: waiting)
        let hue = SessionTile.hue(session.harness)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: AgentsModel.harnessSymbol(session.harness))
                    .coreFont(size: 15, weight: .semibold).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(8)
                    )
                    .accessibilityHidden(true)
                Text(model.title(session)).coreFont(size: MacTextSize.large, weight: .bold).lineLimit(1)
                    .truncationMode(.tail).help(model.title(session) + "\n" + session.id)
                StateBadge(st.label, tone: st.tone, symbol: st.symbol).help(subtitle)
                Spacer(minLength: Space.s3)
                if !panel { detailsButton }
                actions
            }
            .frame(minHeight: 40)
            if showDetails && !panel {
                strip(hue: hue, tone: st.tone).transition(
                    reduce ? .opacity : .opacity.combined(with: .move(edge: .top)))
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
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
        .padding([.horizontal, .top], Space.s1)
        .task(id: session.id) { await model.followLedger(session.id) }
        .task(id: session.id) { await model.followRoute(session.id) }
        .accessibilityElement(children: .contain)
    }

    private var detailsButton: some View {
        Button {
            if reduce { showDetails.toggle() } else { withAnimation(.smooth(duration: 0.3)) { showDetails.toggle() } }
        } label: {
            Label("Details", systemImage: showDetails ? "info.circle.fill" : "info.circle")
                .coreFont(size: MacTextSize.body, weight: .semibold)
                .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd + 4)
                .background(showDetails ? GlassInk.blue.opacity(0.22) : GlassInk.well, in: coreShape(Radius.control))
                .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help(showDetails ? "Hide the details under the header" : "Show the runner, account, tokens and cost")
        .accessibilityIdentifier("session-details")
    }

    private func strip(hue: Color, tone: Tone) -> some View {
        let route = session.route
        var facts: [(String, String)] = [("Runner", model.runnerName(session.runner))]
        if let a = route?.account { facts.append(("Account", model.accountNames[a] ?? "an account")) }
        if let r = route, let c = SessionCues.chain(r, name: model.chainName(r)) { facts.append(("Order", c)) }
        if let m = session.model { facts.append(("Model", m)) }
        facts.append(
            (
                "Tokens",
                "\(session.usage.map { AgentWords.tokens($0.input) } ?? "0") in · \(session.usage.map { AgentWords.tokens($0.output) } ?? "0") out"
            ))
        if let c = AgentWords.cost(session.usage?.costMicros), model.ledgers[session.id]?.isPlan != true {
            facts.append(("Cost", c))
        }
        if let w = session.resumes, w > 0 { facts.append(("Woke up", w == 1 ? "1 time" : "\(w) times")) }
        let burn = model.sessions.burn[session.id] ?? []
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s5) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.0).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        Text(f.1).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                            .truncationMode(.middle).monospacedDigit().help(f.1)
                    }
                }
                Spacer(minLength: Space.s3)
                if burn.count >= 2 {
                    CoreSpark(burn, tone: tone == .fail ? .fail : .run).frame(width: 140, height: 32)
                        .help("Tokens used, as this Mac saw them change")
                }
                timer
            }
            if let l = model.ledgers[session.id] { SessionSpendStrip(session: session, ledger: l).transition(.opacity) }
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }

    /// What happened, in words: why it ended, or what it is doing.
    private var subtitle: String {
        let r = model.runnerName(session.runner)
        if model.waiting(session.id) { return "Waiting for your approval below." }
        switch session.state {
        case .starting: return "Waiting for \(r) to launch \(session.harness). This usually takes a few seconds."
        case .waiting: return "It finished its turn. Type your next message."
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

    /// A live session has one action: End session. A finished one has recovery only (Wake, Resume, Start again).
    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s2) {
            if session.live {
                AppActionTile(title: "End session", symbol: "stop.fill", key: "", hue: GlassInk.red) {
                    model.confirmEnd(session.id)
                }
                .disabled(model.stopping[session.id] != nil)
                .help(
                    "Ends the session: the CLI exits and the composer closes. The transcript stays. Esc stops only the current turn."
                )
            } else {
                if case .succeeded? = session.outcome {
                    AppActionTile(title: "Wake", symbol: "alarm", key: "W", hue: GlassInk.violet) {
                        model.wake(session.id)
                    }
                    .help("Recovery: bring the process back on its runner, with the same conversation.")
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
                if session.state == .lost {
                    AppActionTile(
                        title: "Resume", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue, prominent: true
                    ) {
                        model.resume(session.id)
                    }
                    .help("Recovery: the runner lost it. Resume continues the conversation in the same folder.")
                } else {
                    AppActionTile(
                        title: "Start again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.blue, prominent: true
                    ) {
                        model.startAgain(session.id)
                    }
                    .help("Start a new AI session with the same first message and runner. This one stays as it is.")
                }
            }
        }
    }
}
