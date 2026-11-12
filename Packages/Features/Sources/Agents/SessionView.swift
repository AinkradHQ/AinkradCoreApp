import CoreUI
import SwiftUI

/// One AI session's conversation (N42): a compact header, one column of messages and tool rows, the composer. Adaptive: at
/// 1300 pt and wider the side panel shows beside it; at medium widths the Details strip toggles under the header; narrow
/// windows keep one column and tighten the header.
struct SessionView: View {
    /// A comfortable reading width for the notices, transcript and composer, centred on wide windows.
    static let readingWidth = Space.s8 * 24
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
            // One notice at a time, most urgent first; with none, the route cues (fallback, account) may speak.
            Group {
                if let b = ConversationWords.banner(
                    s, runner: model.runnerName(s.runner), reconnecting: model.link == .reconnecting,
                    notice: model.notices[sessionID])
                {
                    CoreNotice(symbol: b.symbol, title: b.title, text: b.text, tone: b.tone) {
                        if b.resume {
                            Button(action: { model.resume(s.id) }) { Label("Resume", systemImage: "arrow.clockwise") }
                                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                                .environment(\.coreKeycap, "R")
                                .help("Continue the conversation in the same folder (R)")
                        }
                    }
                    .transition(.opacity)
                } else {
                    SessionRouteCues(model: model, session: s)
                }
            }
            .frame(maxWidth: Self.readingWidth).frame(maxWidth: .infinity)
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
            TranscriptView(model: model, store: model.transcripts[sessionID], session: s, jump: jump)
                // A comfortable reading width, centred, on wide windows.
                .frame(maxWidth: Self.readingWidth).frame(maxWidth: .infinity)
            ComposerView(model: model, session: s, focused: $composing)
                .frame(maxWidth: Self.readingWidth).frame(maxWidth: .infinity)
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
