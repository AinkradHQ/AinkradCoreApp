import CoreUI
import SwiftUI

/// One session's pane: run header, a banner for its state, the streamed transcript, pending approvals, the composer.
struct SessionView: View {
    @Bindable var model: AgentsModel
    let sessionID: String
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let s = model.sessions.session(sessionID) {
            let mine = model.pending.filter { $0.session == sessionID }
            let keysHere = model.shell.activePane == AgentsModel.paneID(sessionID) && !model.shell.coverOpen
            VStack(alignment: .leading, spacing: 0) {
                RunHeader(model: model, session: s)
                VStack(spacing: Space.s2) {
                    if model.link == .reconnecting {
                        NoticeBanner(
                            notice: InlineNotice(
                                title: "Reconnecting",
                                detail: "What you see stays visible; it resumes from where it left off.",
                                symbol: "arrow.triangle.2.circlepath"))
                    }
                    if let n = model.notices[sessionID] { NoticeBanner(notice: n) }
                    StateBanner(model: model, session: s)
                }
                .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
                TranscriptView(model: model, store: model.transcripts[sessionID], session: s)
                if !mine.isEmpty {
                    VStack(spacing: Space.s2) {
                        ForEach(Array(mine.enumerated()), id: \.element.id) { i, r in
                            ApprovalCardView(model: model, request: r, keys: keysHere && i == 0)
                        }
                    }
                    .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
                }
                ComposerView(model: model, session: s)
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("This session is not in the list anymore.").foregroundStyle(palette.text2).padding(Space.s4)
        }
    }
}

/// State, how long, who runs it, and what it used. Tokens and cost are what the harness reported: there is no cap to show against.
struct RunHeader: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        let st = AgentWords.status(session, waiting: model.waiting(session.id))
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                StateBadge(st.label, tone: st.tone, symbol: st.symbol)
                if session.live {
                    HStack(spacing: Space.s1) {
                        Text("running for").foregroundStyle(palette.text2)
                        Text(session.createdAt, style: .timer).font(
                            .system(size: MacTextSize.body, design: .monospaced))
                    }
                } else if let end = session.endedAt {
                    Text("ended \(AgentWords.ago(end))").foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s2)
                if session.live {
                    Button("Cancel") { model.confirmCancel(session.id) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Ask \(session.harness) to stop after its current tool call")
                    Button("Kill") { model.confirmKill(session.id) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Stop it at once; can leave files half-written")
                }
            }
            .font(.system(size: MacTextSize.body))
            HStack(alignment: .top, spacing: Space.s5) {
                stat("Tokens in", session.usage.map { AgentWords.tokens($0.input) } ?? "none yet")
                stat("Tokens out", session.usage.map { AgentWords.tokens($0.output) } ?? "none yet")
                stat("Cost", AgentWords.cost(session.usage?.costMicros) ?? "not reported")
                if let m = session.model { stat("Model", m) }
                if let r = session.resumes, r > 0 { stat("Resumed", "\(r) \(r == 1 ? "time" : "times")") }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s3)
        .accessibilityElement(children: .contain)
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            Text(v).font(.system(size: MacTextSize.body, weight: .medium, design: .monospaced)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the state means for you, and the one thing to do about it.
struct StateBanner: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        let r = model.runnerName(session.runner)
        switch session.state {
        case .starting:
            row(
                "hourglass", .done, "Starting",
                "Waiting for \(r) to launch \(session.harness). This usually takes a few seconds.")
        case .interrupted:
            row(
                "arrow.clockwise", .warn, "Interrupted: the runner restarted",
                "\(r) restarted. The session resumes by itself; you do not need to do anything.")
        case .lost:
            row(
                "wifi.exclamationmark", .fail, "Session lost",
                "\(r) dropped it and could not resume it. The transcript up to seq \(session.lastSeq) is kept."
            ) {
                Button("Resume") { model.resume(session.id) }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        case .ended:
            let o = session.outcome
            let tone = o?.tone ?? .queue
            row(o?.symbol ?? "stop.circle", tone, "Ended: \(o?.label.lowercased() ?? "no outcome")", endedDetail(o)) {
                Button("Resume") { model.resume(session.id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                if case .succeeded? = o {
                    Button("Wake") { model.wake(session.id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Queue another turn for this agent")
                }
            }
        default:
            if session.state.unknownRaw != nil {
                row("questionmark.circle", .queue, session.state.rawValue, "This state is newer than this app.")
            }
        }
    }

    private func endedDetail(_ o: SessionOutcome?) -> String {
        if let why = session.outcomeReason, !why.isEmpty { return why }
        switch o {
        case .succeeded?: return "It finished what it was asked."
        case .failed?: return "The agent stopped with an error. The last output is above."
        case .cancelled?: return "It was cancelled. What it did before stays in the transcript."
        case .tokenCap?: return "It used the tokens it was allowed and stopped."
        case .stalled?: return "It stopped making progress."
        default: return o.map { $0.rawValue } ?? "The Core did not say how it ended."
        }
    }

    private func row<Buttons: View>(
        _ symbol: String, _ tone: Tone, _ title: String, _ detail: String,
        @ViewBuilder buttons: () -> Buttons = { EmptyView() }
    ) -> some View {
        let c = palette.tone(tone)
        return HStack(spacing: Space.s3) {
            Image(systemName: symbol).foregroundStyle(c.ink).frame(width: Space.s5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            buttons()
        }
        .padding(Space.s3)
        .background(c.fill, in: coreShape(Radius.control))
        .accessibilityElement(children: .contain)
    }
}
