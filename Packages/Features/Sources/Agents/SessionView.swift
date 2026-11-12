import CoreUI
import SwiftUI

/// One AI session's conversation (N42): a compact header, one column of messages and tool rows, the composer. Adaptive: at
/// 1300 pt and wider the side panel shows beside it; at medium widths the Details strip toggles under the header; narrow
/// windows keep one column and tighten the header.
struct SessionView: View {
    @Bindable var model: AgentsModel
    let sessionID: String
    @Environment(\.corePalette) private var palette
    @FocusState private var paneFocus: Bool
    @FocusState private var composing: Bool
    @State private var jump = 0

    static let panelWidth: CGFloat = 1300
    static let narrow: CGFloat = 720

    var body: some View {
        if let s = model.sessions.session(sessionID) {
            GeometryReader { geo in
                let wide = geo.size.width >= Self.panelWidth
                HStack(alignment: .top, spacing: 0) {
                    conversation(s, wide: wide, narrow: geo.size.width < Self.narrow)
                    if wide {
                        SessionSidePanel(model: model, session: s).frame(width: 320).padding(.trailing, Space.s3)
                            .padding(.top, Space.s2).transition(.opacity)
                    }
                }
            }
            // The pane holds focus when you are not writing. A live session opens with the cursor in the composer.
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear { focusStart(s) }
            .retakeFocus(after: model.shell, pane: AgentsModel.paneID(sessionID)) { focusStart(s) }
            .onKeyPress(.return) { write(s) }
            .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in write(s) }
            .onKeyPress(.downArrow) { latest() }
            .onKeyPress(.end) { latest() }
            .onKeyPress(characters: .letters) { press in
                // Letters belong to the field while you write: no shortcut fires from typing.
                guard let key = PaneKeys.shortcut(press.characters, typing: composing) else { return .ignored }
                switch key {
                case "r" where s.state == .lost: model.resume(s.id)
                case "r" where s.over: model.startAgain(s.id)
                case "w" where s.outcome == .succeeded: model.wake(s.id)
                default: return .ignored
                }
                return .handled
            }
            .paneLook(AgentPrefs.shared.look)
            .clipShape(coreShape(Radius.cardMac))
            .accessibilityElement(children: .contain)
        } else {
            Text("This AI session is not in the list anymore.").foregroundStyle(palette.text2).padding(Space.s4)
        }
    }

    private func conversation(_ s: AgentSessionInfo, wide: Bool, narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionHero(model: model, session: s, panel: wide)
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
                SessionRouteCues(model: model, session: s)
            }
            .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
            TranscriptView(model: model, store: model.transcripts[sessionID], session: s, jump: jump)
                // A comfortable reading width, centred, on wide windows.
                .frame(maxWidth: 820).frame(maxWidth: .infinity)
            ComposerView(model: model, session: s, focused: $composing)
                .frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
    }

    private func focusStart(_ s: AgentSessionInfo) {
        if s.live { composing = true } else { paneFocus = true }
    }

    private func write(_ s: AgentSessionInfo) -> KeyPress.Result {
        guard model.canReply(s) else { return .ignored }
        composing = true
        return .handled
    }

    private func latest() -> KeyPress.Result {
        jump += 1
        return .handled
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
                "\(r) dropped it. The transcript up to that point is kept. Send a message to bring it back, or use Resume at the top right."
            )
        default:
            if session.idleEnded {
                row(
                    "moon.zzz", .queue, "Ended (idle)",
                    "Nobody came back, so it ended. Send a message to continue in the same conversation.")
            } else if session.keepsOpen == false && !session.over {
                row(
                    "info.circle", .warn, "One answer, then it ends",
                    "\(r) runs an older version that cannot keep the conversation open. Update the runner for live AI sessions."
                )
            } else if session.state.unknownRaw != nil {
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
