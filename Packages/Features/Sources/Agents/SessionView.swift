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
                    SessionRouteCues(model: model, session: s)
                }
                .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
                TranscriptView(model: model, store: model.transcripts[sessionID], session: s, jump: jump)
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
            .retakeFocus(after: model.shell, pane: AgentsModel.paneID(sessionID)) {
                if case .running = s.state { composing = true } else { paneFocus = true }
            }
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
        guard model.canReply(s) else { return .ignored }
        composing = true
        return .handled
    }

    private func latest() -> KeyPress.Result {
        jump += 1
        return .handled
    }

    /// The keys this pane answers, for what this session can do now.
    /// The stack badge's width (icon, "3 of 3", "⌃Tab", padding), growing with the app's text size like the badge.
    private var badgeRoom: CGFloat { 116 * CGFloat(TextSizePrefs.shared.scale) }

    private func keyHints(_ s: AgentSessionInfo) -> some View {
        let keys: [String] =
            s.live
            ? ["↩ reply", "esc leave field", "C cancel", "K kill", "↓ latest"]
            : [s.state == .lost ? "R resume" : "R start again"] + (s.outcome == .succeeded ? ["W wake"] : [])
                + ["↓ latest"]
        let line = keys.joined(separator: " · ")
        // With other panes open this one can be the front of a stack, whose "2 of 3 ⌃Tab" badge sits over the bottom right
        // corner: the hints stop short of it (and cut with an ellipsis, full line on hover) instead of running under it.
        return Text(line).coreFont(size: MacTextSize.meta)
            .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.tail).help(line)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Space.s4).padding(.trailing, Space.s4 + (model.shell.panes.count > 1 ? badgeRoom : 0))
            .padding(.bottom, Space.s2)
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
                "\(r) dropped it and could not resume it. The transcript up to that point is kept. Resume is at the top right."
            )
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
