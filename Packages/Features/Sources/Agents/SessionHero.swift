import CoreUI
import SwiftUI

/// The top of a conversation: one slim line with the state badge on the left and the actions on the right (the window tab
/// already carries the title). Below 1300 pt, where there is no side panel, the Details button (test-fixes decision 1, variant B)
/// shows or hides a strip of runner, account, order, tokens and cost under it, remembered on this Mac.
struct SessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    /// The window is wide: the side panel carries the details, so no strip and no Details button.
    var panel = false
    /// Opens the find bar (⌘F).
    var find: (() -> Void)?
    @AppStorage("agents.detailsStrip") private var showDetails = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    var body: some View {
        let waiting = model.waiting(session.id)
        let st = AgentWords.status(session, waiting: waiting)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                // The window tab already names the session; the header is just its state and actions.
                StateBadge(st.label, tone: st.tone, symbol: st.symbol).help(subtitle)
                Spacer(minLength: Space.s3)
                if empty {
                    Button("Advanced…") { model.openNewSession(advanced: true) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Choose the tool, runner, folder or repo, model and account order")
                }
                if !panel { detailsButton }
                if !panel { SessionActions(model: model, session: session, find: find) }
            }
            .frame(minHeight: MacSize.controlLg)
            if showDetails && !panel {
                strip(tone: st.tone).transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s2)))
            }
            if let stop = model.stopping[session.id], session.live {
                Label(
                    stop == .killing
                        ? "Killing: stopping it on the runner now."
                        : "Cancelling: it finishes the tool call in flight, then ends. K kills at once.",
                    systemImage: "hourglass"
                )
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.amberInk)
                .accessibilityIdentifier("session-stopping")
            }
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
        .task(id: session.id) { await model.followLedger(session.id) }
        .task(id: session.id) { await model.followRoute(session.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title(session))
    }

    /// A session with nothing in it yet is the quick "New AI session" page: the header offers Advanced….
    private var empty: Bool {
        session.live && model.transcripts[session.id]?.entries.isEmpty == true
            && model.transcripts[session.id]?.hasEarlier != true
    }

    /// Decision 1 (test-fixes, variant B): Details shows or hides the strip under the header; the choice is remembered.
    private var detailsButton: some View {
        Button {
            withAnimation(reduce ? nil : Motion.out(Motion.ui)) { showDetails.toggle() }
        } label: {
            Label("Details", systemImage: "info.square")
        }
        .buttonStyle(CoreButtonStyle(showDetails ? .prominent : .secondary, size: .small))
        .help(showDetails ? "Hide the details under the header" : "Show the runner, account, tokens and cost")
        .accessibilityValue(showDetails ? "Shown" : "Hidden")
        .accessibilityIdentifier("session-details")
    }

    private func strip(tone: Tone) -> some View {
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
            HStack(alignment: .center, spacing: Space.s5) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.0).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        Text(f.1).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                            .truncationMode(.middle).monospacedDigit().help(f.1)
                    }
                }
                Spacer(minLength: Space.s3)
                if burn.count >= 2 {
                    CoreSpark(burn, tone: tone == .fail ? .fail : .done).frame(width: Space.s8 * 4, height: Space.s8)
                        .help("Tokens used, as this Mac saw them change")
                }
            }
            if let l = model.ledgers[session.id] { SessionSpendStrip(session: session, ledger: l).transition(.opacity) }
        }
        .padding(Space.s3)
        .coreWell()
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
}
