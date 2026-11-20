import CoreUI
import Shell
import SwiftUI

/// The top of a conversation: one slim line with the session's title, tool and runner on the left and the actions on the
/// right (Ahmed, 2026-11-15: the tab cut the title short; the state is said once, in the conversation, not here too). Below 1300 pt, where there is no side panel, the Details button (test-fixes decision 1, variant B)
/// shows or hides a strip of runner, account, order, tokens and cost under it, remembered on this Mac.
struct SessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    /// The window is wide: the side panel carries the details, so no strip and no Details button.
    var panel = false
    /// A narrow pane: the actions show as icons (their names in the tooltips), so they never squeeze the title.
    var compact = false
    /// The pane has room for the session panel: the title line ends with its toggle (⌥⌘I).
    var panelRoom = false
    /// Opens the find bar (⌘F).
    var find: (() -> Void)?
    var togglePanel: () -> Void = {}
    @AppStorage("agents.detailsStrip") private var showDetails = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = AgentWords.status(session, waiting: model.waiting(session.id))
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                titleLine
                Spacer(minLength: Space.s3)
                if empty {
                    Button("Advanced…") { model.openNewSession(advanced: true) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Choose the tool, runner, folder or repo, model and account order")
                }
                // The session's actions always live here (one home, one name each); the panel holds information.
                Group {
                    if !panel && !panelRoom { detailsButton }
                    // Icons only; names and keys are in the tooltips (Ahmed, 2026-11-16).
                    SessionActions(model: model, session: session, find: find, compact: true)
                }
                .fixedSize()
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
        .readingColumn()
        .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
        .task(id: session.id) { await model.followLedger(session.id) }
        .task(id: session.id) { await model.followRoute(session.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title(session))
    }

    /// "Write a status report for the fleet · Claude Code · mac-studio": the title in full, then where it runs, quieter.
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(model.title(session)).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                .truncationMode(.tail)
            // Where it runs only when it fits whole: never a clipped "(".
            ViewThatFits(in: .horizontal) {
                Text([AgentWords.toolName(session.harness), model.runnerName(session.runner)].joined(separator: " · "))
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1).fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            // Where it ran when that was not the Core (E15): an overflowed or pinned session, or one with heavy jobs.
            RanOnChip(
                model.shell.hardwareDeck.place(
                    session: session.id, runner: session.runner, placeReason: session.placeReason))
        }
        .help(model.title(session) + "\n" + subtitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// A session with nothing in it yet is the quick "New AI session" page: the header offers Advanced….
    private var empty: Bool {
        session.live && model.transcripts[session.id]?.entries.isEmpty == true
            && model.transcripts[session.id]?.hasEarlier != true
    }

    /// Decision 1 (test-fixes, variant B): Details shows or hides the strip under the header; the choice is remembered.
    @ViewBuilder private var detailsButton: some View {
        if compact {
            CoreIconButton(symbol: "info.square", label: "Details", selected: showDetails) { toggleDetails() }
                .help(showDetails ? "Hide the details (⌥⌘I)" : "Show the runner, account, tokens and cost (⌥⌘I)")
                .keyHint(.details).accessibilityIdentifier("session-details")
        } else {
            fullDetailsButton
        }
    }

    private func toggleDetails() {
        withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { showDetails.toggle() }
    }

    private var fullDetailsButton: some View {
        Button(action: toggleDetails) {
            Label("Details", systemImage: "info.square")
        }
        .buttonStyle(CoreButtonStyle(showDetails ? .prominent : .secondary, size: .small))
        .help(
            showDetails
                ? "Hide the details under the header (⌥⌘I)" : "Show the runner, account, tokens and cost (⌥⌘I)"
        )
        .accessibilityValue(showDetails ? "Shown" : "Hidden")
        .keyHint(.details).accessibilityIdentifier("session-details")
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
