import CoreUI
import SwiftUI

/// One session's pane: run header, a banner for its state, the streamed transcript, pending approvals, the composer.
struct SessionView: View {
    @Bindable var model: AgentsModel
    let sessionID: String
    @Environment(\.corePalette) private var palette
    @FocusState private var paneFocus: Bool
    @FocusState private var composing: Bool
    @State private var jump = 0

    var body: some View {
        if let s = model.sessions.session(sessionID) {
            let mine = model.cards(for: sessionID)
            let keysHere = model.shell.activePane == AgentsModel.paneID(sessionID) && !model.shell.coverOpen
            VStack(alignment: .leading, spacing: 0) {
                SessionHero(model: model, session: s)
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
                TranscriptView(model: model, store: model.transcripts[sessionID], session: s, jump: jump)
                if !mine.isEmpty {
                    VStack(spacing: Space.s2) {
                        ForEach(Array(mine.enumerated()), id: \.element.id) { i, r in
                            ApprovalCardView(model: model, request: r, keys: keysHere && i == 0)
                        }
                    }
                    .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
                }
                ComposerView(model: model, session: s, focused: $composing)
                keyHints(s)
            }
            // Keyboard first: the pane holds focus when you are not writing. ↩ or / writes (Esc leaves the field),
            // R resume, W wake, C cancel, K kill, ↓ or End jumps to the latest.
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear {
                if case .running = s.state { composing = true } else { paneFocus = true }
            }
            .onKeyPress(.return) { write(s) }
            .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in write(s) }
            .onKeyPress(.downArrow) { latest() }
            .onKeyPress(.end) { latest() }
            .onKeyPress(characters: .letters) { press in
                switch press.characters.lowercased() {
                case "r" where s.over || s.state == .lost: model.resume(s.id)
                case "w" where s.outcome == .succeeded: model.wake(s.id)
                case "c" where s.live: model.confirmCancel(s.id)
                case "k" where s.live: model.confirmKill(s.id)
                default: return .ignored
                }
                return .handled
            }
            // The same look as the Agents app: its surface inside the pane's glass rim.
            .paneLook(AgentPrefs.shared.look)
            .clipShape(coreShape(Radius.cardMac))
            .accessibilityElement(children: .contain)
        } else {
            Text("This session is not in the list anymore.").foregroundStyle(palette.text2).padding(Space.s4)
        }
    }

    private func write(_ s: AgentSessionInfo) -> KeyPress.Result {
        guard case .running = s.state else { return .ignored }
        composing = true
        return .handled
    }

    private func latest() -> KeyPress.Result {
        jump += 1
        return .handled
    }

    /// The keys this pane answers, for what this session can do now.
    private func keyHints(_ s: AgentSessionInfo) -> some View {
        let keys: [String] =
            s.live
            ? ["↩ reply", "esc leave field", "C cancel", "K kill", "↓ latest"]
            : ["R resume"] + (s.outcome == .succeeded ? ["W wake"] : []) + ["↓ latest"]
        return Text(keys.joined(separator: " · ")).font(.system(size: MacTextSize.meta))
            .foregroundStyle(GlassInk.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
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
        case .lost:
            row(
                "wifi.exclamationmark", .fail, "Session lost",
                "\(r) dropped it and could not resume it. The transcript up to seq \(session.lastSeq) is kept."
            ) {
                Button("Resume") { model.resume(session.id) }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        default:
            if session.state.unknownRaw != nil {
                row("questionmark.circle", .queue, session.state.rawValue, "This state is newer than this app.")
            }
        }
    }

    private func row<Buttons: View>(
        _ symbol: String, _ tone: Tone, _ title: String, _ detail: String,
        @ViewBuilder buttons: () -> Buttons = { EmptyView() }
    ) -> some View {
        CoreNotice(symbol: symbol, title: title, text: detail, tone: tone) { HStack(spacing: Space.s2) { buttons() } }
    }
}
