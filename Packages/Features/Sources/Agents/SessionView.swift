import AppKit
import CoreUI
import SwiftUI

/// One AI session's conversation (N42): a compact header, one column of messages and tool rows, the composer. Adaptive: at
/// 1300 pt and wider the side panel shows beside it; at medium widths the Details strip toggles under the header; narrow
/// windows keep one column and tighten the header.
struct SessionView: View {
    @Bindable var model: AgentsModel
    let sessionID: String
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @FocusState private var paneFocus: Bool
    @FocusState private var composing: Bool
    @State private var jump = 0
    // Find in the conversation (⌘F) and turn jumps (⌥↑ ⌥↓).
    @State private var finding = false
    @State private var findQuery = ""
    @State private var findIndex = 0
    @State private var focusSeq: Int64?
    /// What the screen has open (Open in…, the model menu, Review, the shortcut list), shared so a key opens what a click does.
    @State private var ui = SessionUI()
    @AppStorage("agents.detailsStrip") private var showDetails = true
    @AppStorage(SessionView.sidebarKey) private var showSidebar = true
    static let sidebarKey = "agents.sessionSidebar"
    /// The other sessions show at the left only when the pane has room for them beside a readable conversation.
    static let sidebarRoom: CGFloat = 900
    static let sidebarWidth: CGFloat = 240
    @State private var keyMonitor: Any?
    @State private var clickMonitor: Any?

    static let panelWidth: CGFloat = 1300
    static let narrow: CGFloat = 720
    /// Under this width (and no side panel) the header's actions show as icons, so they never squeeze the title.
    static let compact: CGFloat = 1100

    var body: some View {
        if let s = model.sessions.session(sessionID) {
            GeometryReader { geo in
                let side = showSidebar && geo.size.width >= Self.sidebarRoom
                let rest = geo.size.width - (side ? Self.sidebarWidth + Space.s3 : 0)
                let wide = rest >= Self.panelWidth
                HStack(alignment: .top, spacing: 0) {
                    if side {
                        SessionSwitcher(model: model, current: sessionID).frame(width: Self.sidebarWidth)
                            .padding(.leading, Space.s3).padding(.vertical, Space.s2)
                            .transition(reduce ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    }
                    conversation(s, wide: wide, compact: rest < Self.compact, room: geo.size.width >= Self.sidebarRoom)
                    if wide {
                        SessionSidePanel(model: model, session: s, find: openFind).frame(width: 320).padding(
                            .trailing, Space.s3
                        )
                        .padding(.top, Space.s2).transition(.opacity)
                    }
                }
            }
            // The pane holds focus when you are not writing. A live session opens with the cursor in the composer.
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear {
                focusStart(s)
                // ⌘ held shows every button's key; only the pane in front shows them.
                let ui = ui
                let shell = model.shell
                let pane = AgentsModel.paneID(sessionID)
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { e in
                    MainActor.assumeIsolated { ui.track(e, active: shell.activePane == pane) }
                    return e
                }
                // Wherever you click in the conversation, the cursor goes back to the message field (Ahmed, 2026-11-16):
                // after the click lands, unless it put the cursor in another text field or selected words to copy.
                let model = model
                let id = sessionID
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { e in
                    MainActor.assumeIsolated {
                        ComposerFocus.clicks += 1
                        guard shell.activePane == pane, let s = model.sessions.session(id), model.canWrite(s),
                            let window = e.window ?? ui.field?.window
                        else { return }
                        ComposerFocus.handled += 1
                        // After SwiftUI has settled its own focus for the click.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(40))
                            guard ComposerFocus.shouldReturn(window.firstResponder) else { return }
                            ui.focusField()
                        }
                    }
                    return e
                }
            }
            .onDisappear {
                for m in [keyMonitor, clickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(m) }
                keyMonitor = nil
                clickMonitor = nil
                ui.showKeys = false
            }
            .retakeFocus(after: model.shell, pane: AgentsModel.paneID(sessionID)) { focusStart(s) }
            // The pane's keys step aside while a text field has the keyboard: SwiftUI hands them to the pane before the
            // field, so Return, "/" and the arrows never reached the composer (2026-11-15, found by the composer self-test).
            .onKeyPress(.return) { typing ? .ignored : write(s) }
            .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in typing ? .ignored : write(s) }
            .onKeyPress(.downArrow) { typing ? .ignored : latest() }
            .onKeyPress(.end) { typing ? .ignored : latest() }
            // The session's shortcuts (⌘F, ⌘↩, ⇧⌘R…), wherever the keyboard is in the pane; the message field hands over the
            // same ones itself (ComposerKeys.command). ⌥↑ ⌥↓ jump between your messages.
            .onKeyPress(phases: .down) { press in
                guard let key = SessionShortcut.match(press.key.character, press.modifiers) else { return .ignored }
                return run(key, s) ? .handled : .ignored
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard press.modifiers.contains(.option), !typing else { return .ignored }
                turnStep(press.key == .upArrow ? -1 : 1)
                return .handled
            }
            .onKeyPress(characters: .letters) { press in
                // Letters belong to the field while you write: no shortcut fires from typing.
                guard let key = PaneKeys.shortcut(press.characters, typing: composing || typing) else {
                    return .ignored
                }
                switch key {
                case "r" where s.state == .lost: model.resume(s.id)
                case "r" where s.over: model.startAgain(s.id)
                case "w" where s.outcome == .succeeded: model.wake(s.id)
                default: return .ignored
                }
                return .handled
            }
            .overlay(alignment: .top) {
                if ui.shortcuts {
                    ShortcutSheet { ui.shortcuts = false }.padding(.top, Space.s8 * 2).padding(.horizontal, Space.s4)
                        .transition(.opacity)
                }
            }
            .animation(Motion.out(Motion.ui), value: ui.shortcuts)
            .environment(\.sessionUI, ui)
            .onChange(of: ui.focusComposer) { _, _ in
                ui.focusField()
                composing = true
            }
            .paneLook(AgentPrefs.shared.look)
            .clipShape(coreShape(Radius.cardMac))
            .accessibilityElement(children: .contain)
        } else {
            Text("This AI session is not in the list anymore.").foregroundStyle(palette.text2).padding(Space.s4)
        }
    }

    private func conversation(_ s: AgentSessionInfo, wide: Bool, compact: Bool, room: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionHero(model: model, session: s, panel: wide, compact: compact, sidebarRoom: room, find: openFind)
            if finding {
                ConversationFindBar(
                    query: $findQuery, count: hits.count, index: min(findIndex, max(hits.count - 1, 0)),
                    step: { findStep($0) },
                    close: {
                        finding = false
                        focusSeq = nil
                    }
                )
                .readingColumn()
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
                .onChange(of: findQuery) { _, _ in
                    findIndex = 0
                    focusSeq = hits.first
                }
            }
            // One notice at a time, most urgent first; with none, the route cues (fallback, account) may speak.
            Group {
                if let b = ConversationWords.banner(
                    s, runner: model.runnerName(s.runner), reconnecting: model.link == .reconnecting,
                    notice: nil)
                {
                    CoreNotice(symbol: b.symbol, title: b.title, text: b.text, tone: b.tone) {
                        if b.resume {
                            Button(action: { model.resume(s.id) }) { Label("Resume", systemImage: "arrow.clockwise") }
                                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                                .environment(\.coreKeycap, "R")
                                .help("Continue the conversation in the same folder (R)").keyHint("R")
                        }
                    }
                    .transition(.opacity)
                } else {
                    SessionRouteCues(model: model, session: s)
                }
            }
            .readingColumn()
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s2)
            TranscriptView(model: model, store: model.transcripts[sessionID], session: s, jump: jump, focus: focusSeq)
                .frame(maxWidth: .infinity)
            PinnedApprovals(model: model, session: s).readingColumn().padding(.horizontal, Space.s4)
            ComposerView(model: model, session: s, focused: $composing) { run($0, s) }
                .frame(maxWidth: .infinity)
        }
        // A plan card's Go ahead approves the tool's pending plan request, or tells the agent to build; Change it starts a
        // message.
        .environment(\.planActions, model.canReply(s) ? planActions(s) : nil)
        // The conversation's own text size and typeface (Settings, AI Sessions, Text).
        .environment(\.coreTextScale, AgentPrefs.shared.textScale)
        .environment(\.coreFontDesign, AgentPrefs.shared.fontDesign)
    }

    /// Runs a session shortcut; false when it does not apply now, so the key goes on (to the text field, say).
    private func run(_ key: SessionShortcut, _ s: AgentSessionInfo) -> Bool {
        let pending = (model.transcripts[s.id]?.approvalList ?? [])
            .contains { $0.status(now: Date(), sessionOver: s.over) == .pending }
        switch key {
        case .find: openFind()
        case .findNext, .findPrevious:
            guard finding else { return false }
            findStep(key == .findNext ? 1 : -1)
        // A waiting approval's own buttons hold ⌘↩ and ⌘⌫; with none, ⌘↩ and ⇧⌘↩ answer the newest plan.
        case .goAhead, .changePlan:
            guard !pending, model.canReply(s), latestPlan != nil else { return false }
            let a = planActions(s)
            if key == .goAhead { a.goAhead() } else { a.change() }
        case .stopTurn:
            guard model.canStopTurn(s) else { return false }
            model.stopTurn(s.id)
        case .endSession:
            guard s.live, model.stopping[s.id] == nil else { return false }
            model.confirmEnd(s.id)
        case .terminal:
            guard s.live || s.state != .lost else { return false }
            model.host?.openTerminal(on: s.runner)
        case .openIn:
            guard s.live || s.state != .lost else { return false }
            ui.openIn.toggle()
        case .review:
            guard !model.filesTouched(s.id).isEmpty else { return false }
            ui.reviewing.toggle()
        case .attach:
            guard model.canWrite(s) else { return false }
            ui.attach += 1
        case .model:
            guard s.harness == "claude", model.canWrite(s) else { return false }
            ui.modelMenu.toggle()
        case .compact:
            guard model.canWrite(s) else { return false }
            model.drafts[s.id] = "/compact "
            composing = true
        case .copyAnswer:
            guard let text = lastAnswer else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.shell.showToast("Copied the last answer", actionTitle: "")
        case .expandSteps, .collapseSteps:
            ui.steps = (ui.steps.gen + 1, key == .expandSteps)
        case .details: withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { showDetails.toggle() }
        // A narrow pane keeps the sidebar hidden whatever this says.
        case .sidebar: withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { showSidebar.toggle() }
        case .shortcuts: ui.shortcuts.toggle()
        }
        return true
    }

    /// The newest plan the agent proposed, if the conversation has one.
    private var latestPlan: Int64? {
        entries.last { if case .plan = $0.kind { true } else { false } }?.seq
    }

    /// The agent's last words, for ⇧⌘C.
    private var lastAnswer: String? {
        for e in entries.reversed() { if case .assistant(let t) = e.kind { return t } }
        return nil
    }

    private var entries: [TranscriptEntry] { model.transcripts[sessionID]?.entries ?? [] }
    private var hits: [Int64] { ConversationSearch.hits(entries, findQuery) }

    /// The composer asks for focus while `composing` is on, so it would take the cursor back from the find field: let it go.
    private func openFind() {
        composing = false
        // The message field is AppKit's first responder and SwiftUI's focus does not take it from it: let it go first.
        if let field = KeyTextView.focusedField { field.window?.makeFirstResponder(nil) }
        finding = true
    }

    private func findStep(_ d: Int) {
        guard !hits.isEmpty else { return }
        findIndex = (findIndex + d + hits.count) % hits.count
        focusSeq = hits[findIndex]
    }

    private func turnStep(_ d: Int) {
        let turns = ConversationSearch.turns(entries)
        guard !turns.isEmpty else { return }
        let at = focusSeq.flatMap { f in turns.firstIndex { $0 >= f } } ?? turns.count
        focusSeq = turns[min(max(at + d, 0), turns.count - 1)]
    }

    private func planActions(_ s: AgentSessionInfo) -> PlanActions {
        PlanActions(
            goAhead: {
                let plan = model.transcripts[s.id]?.approvalList.first {
                    $0.tool.lowercased() == "exitplanmode" && $0.status(now: Date(), sessionOver: s.over) == .pending
                }
                Task {
                    if let plan {
                        await model.decide(plan, approved: true)
                    } else {
                        await model.say(s.id, "The plan is approved. Go ahead and build it.")
                    }
                }
            },
            change: {
                model.drafts[s.id] = "Change the plan: "
                composing = true
            })
    }

    private func focusStart(_ s: AgentSessionInfo) {
        if s.live { composing = true } else { paneFocus = true }
    }

    private func write(_ s: AgentSessionInfo) -> KeyPress.Result {
        guard model.canReply(s) else { return .ignored }
        composing = true
        return .handled
    }

    /// A text field has the keyboard: the window's real first responder, not SwiftUI's focus state (which drifts).
    private var typing: Bool {
        KeyTextView.focusedField != nil || (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder is NSText
    }

    private func latest() -> KeyPress.Result {
        jump += 1
        return .handled
    }
}

/// What waits on you, pinned above the composer with its timer (Ahmed, 2026-11-15): never scrolled out of sight. Answered
/// or expired, a request leaves here and stays in the transcript as history. Rechecked every second for expiry.
struct PinnedApprovals: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pending = (model.transcripts[session.id]?.approvalList ?? [])
                .filter { $0.status(now: ctx.date, sessionOver: session.over) == .pending }
            if !pending.isEmpty {
                VStack(spacing: Space.s2) {
                    ForEach(pending) { r in ApprovalEntryCard(model: model, request: r) }
                }
                .padding(.bottom, Space.s2)
                .transition(.opacity)
            }
        }
    }
}

/// Whether a click should hand the cursor back to the message field: not when the field has it already, not when another
/// text field took it (find bar, a comment), and not when words are selected to copy.
public enum ComposerFocus {
    /// Debug counts for the self-test: clicks seen, and clicks this pane acted on.
    nonisolated(unsafe) public static var clicks = 0
    nonisolated(unsafe) public static var handled = 0

    @MainActor static func shouldReturn(_ responder: NSResponder?) -> Bool {
        guard let tv = responder as? NSTextView else { return true }
        if tv is KeyTextView { return false }
        if tv.isEditable || tv.isFieldEditor { return false }
        return tv.selectedRange().length == 0
    }
}
