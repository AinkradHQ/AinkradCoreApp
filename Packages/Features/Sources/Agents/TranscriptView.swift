import CoreUI
import SwiftUI

/// The streamed transcript: a lazy column, one row per entry with the seq as its identity, so an appended entry adds a row and
/// leaves the rest alone. It follows the end while you are at the end; scrolling up loads earlier entries.
struct TranscriptView: View {
    @Bindable var model: AgentsModel
    let store: TranscriptStore?
    let session: AgentSessionInfo
    var jump = 0
    /// An entry to bring into view and mark: the find bar's current match or a turn jump.
    var focus: Int64?
    @State private var atEnd = true
    /// A scroll to the end is queued for the next frame: a burst of entries asks once, not once each.
    @State private var scrollQueued = false
    /// Runs of tool steps the person opened or folded (by first seq); ⌥⌘→ / ⌥⌘← set them all.
    @State private var runOpen: [Int64: Bool] = [:]
    @State private var runsAll: Bool?
    @Environment(\.sessionUI) private var ui
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if let store { content(store) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ store: TranscriptStore) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s4) {
                        header(store)
                        let turns = ConversationWords.turns(store.entries)
                        ForEach(columnRows(store)) { c in
                            Group {
                                switch c.kind {
                                case .entry(let e, let inRun):
                                    marked(e) { row(e, store, turn: turns[e.seq]) }
                                        .padding(.leading, inRun ? Space.s4 : 0)
                                case .run(let es, let open):
                                    ToolRunHeader(entries: es, open: open) {
                                        withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) {
                                            runOpen[es[0].seq] = !open
                                        }
                                    }
                                }
                            }
                            .id(c.id)
                            // A new entry rises 6 pt as it fades in; with Reduce Motion it only fades.
                            .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
                        }
                        // The Core's own holds are not transcript entries: they stand after the last one, newest last.
                        ForEach(store.heldList.filter { $0.status(now: Date(), sessionOver: session.over) != .pending })
                        {
                            r in
                            ApprovalEntryCard(model: model, request: r)
                                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
                        }
                        if session.live && !session.idle && store.load == .ready && !model.waiting(session.id) {
                            Thinking(since: session.updatedAt)
                        }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atEnd = true }
                            .onDisappear { atEnd = false }
                    }
                    .readingColumn()
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                }
                .shortStartsAtTop()
                .scrollIndicators(.never)
                // Soft edges (Ahmed, 2026-11-15: content was cut hard under the header and above the composer).
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Space.s4)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Space.s4)
                    }
                }
                .animation(Motion.out(Motion.ui), value: store.entries.count)
                .onChange(of: store.lastSeq) { _, _ in
                    guard atEnd, !scrollQueued else { return }
                    scrollQueued = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(16))
                        scrollQueued = false
                        toEnd(proxy)
                    }
                }
                .onChange(of: jump) { _, _ in toEnd(proxy) }
                .onChange(of: ui?.steps.gen) { _, _ in
                    guard let ui else { return }
                    withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) {
                        runOpen = [:]
                        runsAll = ui.steps.open
                    }
                }
                .onChange(of: focus) { _, f in
                    guard let f else { return }
                    // A match inside a folded run opens it (columnRows), so the entry itself is in the column.
                    let target = f
                    withAnimation(Motion.calm(Motion.out(Motion.move), reduce)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
                .onChange(of: store.heldList.count) { _, _ in if atEnd { toEnd(proxy) } }
                if !atEnd {
                    // A quiet glass control centred over the composer, not an action tile.
                    Button(action: { toEnd(proxy) }) { Label("Latest", systemImage: "chevron.down") }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small)).environment(\.coreKeycap, "↓")
                        .coreGlass(radius: Radius.chip)
                        .help("Jump to the newest message (↓)").keyHint("↓")
                        .padding(.bottom, Space.s2)
                        .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
                }
            }
        }
    }

    private func columnRows(_ store: TranscriptStore) -> [ColumnRow] {
        ColumnRow.rows(TranscriptItem.items(Self.visible(store.entries))) { seq, es in
            // A run holding the find bar's match opens, so the mark can show.
            if let focus, es.contains(where: { $0.seq == focus }) { return true }
            return runOpen[seq] ?? runsAll ?? ColumnRow.openByDefault(es)
        }
    }

    private func latestUser(_ store: TranscriptStore) -> Int64? {
        store.entries.last { if case .user = $0.kind { true } else { false } }?.seq
    }

    private func latestAnswer(_ store: TranscriptStore) -> Int64? {
        store.entries.last { if case .assistant = $0.kind { true } else { false } }?.seq
    }

    /// The find bar's or a turn jump's mark behind an entry.
    private func marked(_ e: TranscriptEntry, @ViewBuilder _ c: () -> some View) -> some View {
        c().background {
            if e.seq == focus {
                coreShape(Radius.control).fill(GlassInk.blue.opacity(0.16)).padding(-Space.s1)
            }
        }
    }

    /// What the column shows: an answer folds into its request's card, and the Core's "approval escalated" notes say
    /// nothing the card does not (N33: one approval, one card).
    static func visible(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        entries.filter {
            switch $0.kind {
            case .approvalDecided: false
            case .note(let type, _): !type.hasPrefix("approval")
            default: true
            }
        }
    }

    @ViewBuilder private func row(_ e: TranscriptEntry, _ store: TranscriptStore, turn: ConversationWords.Turn?)
        -> some View
    {
        if case .approvalRequest(let id, _, _, _) = e.kind, let r = store.approvals[id] {
            // A pending one is pinned above the composer (PinnedApprovals); answered or expired, it stays here as history.
            if r.status(now: Date(), sessionOver: session.over) != .pending {
                ApprovalEntryCard(model: model, request: r)
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
            }
        } else {
            EntryRow(
                entry: e, harness: session.harness, runner: model.runnerName(session.runner), turn: turn,
                latest: e.seq == latestUser(store) || e.seq == latestAnswer(store),
                openConnections: { model.shell.launcher.entry("connections")?.run() },
                actions: EntryActions.make(model, session, ui: ui)
            )
            .equatable()
            // A new entry rises 6 pt as it fades in; with Reduce Motion it only fades.
            .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
        }
    }

    /// Scrolls to the newest entry: eased, or at once under Reduce Motion.
    private func toEnd(_ proxy: ScrollViewProxy) {
        if reduce {
            proxy.scrollTo("end", anchor: .bottom)
        } else {
            withAnimation(Motion.out(Motion.move)) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func header(_ store: TranscriptStore) -> some View {
        switch store.load {
        case .idle, .loading:
            Text("Loading the transcript…").meta(palette).frame(maxWidth: .infinity)
        case .failed(let why):
            NoticeBanner(notice: InlineNotice(title: "Could not load the transcript", detail: why, tone: .fail))
        case .ready:
            if store.hasEarlier {
                Text("Earlier entries load as you scroll up")
                    .meta(palette).frame(maxWidth: .infinity)
                    .onAppear { model.loadEarlier(session.id) }
            } else if store.entries.isEmpty {
                NewSessionHero(model: model, session: session).padding(.top, Space.s8 * 3)
            }
        }
    }
}

extension View {
    fileprivate func meta(_ p: Palette) -> some View { coreFont(size: MacTextSize.meta).foregroundStyle(p.text2) }
}

/// The AI session working: a blue bar that slides, "Thinking…" and how long. The bar rests under Reduce Motion.
struct Thinking: View {
    let since: Date
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            CoreWorkingBar()
            Text("Thinking…").coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                Text(coreUnit("\(max(0, Int(ctx.date.timeIntervalSince(since))))", "s"))
                    .coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2).monospacedDigit()
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The AI session is thinking")
    }
}

/// One entry (N42, one column, like the CLI): the AI's words printed on the glass, you in a flat blue message at the right,
/// each tool call as one compact row that opens to its output, events as quiet centred lines. Equatable, so SwiftUI skips
/// rows whose entry did not change.
struct EntryRow: View, Equatable {
    let entry: TranscriptEntry
    var harness = "claude"
    var runner = ""
    var turn: ConversationWords.Turn?
    /// Your latest message or the latest answer: it carries the action row.
    var latest = false
    /// Opens Connections from a refused connection call (CN5).
    var openConnections: (() -> Void)?
    /// Copy, Edit, Resend, Retry, Quote. Only `canSend` is compared.
    var actions: EntryActions?
    @State private var expanded = EntryRow.openAtStart

    /// Debug screenshots only: rows start open.
    nonisolated(unsafe) static var openAtStart = false

    nonisolated static func == (a: EntryRow, b: EntryRow) -> Bool {
        a.entry == b.entry && a.harness == b.harness && a.runner == b.runner && a.turn == b.turn && a.latest == b.latest
            && a.actions?.canSend == b.actions?.canSend
    }
    @Environment(\.corePalette) private var palette
    @Environment(\.sessionUI) private var ui

    var body: some View {
        content.onChange(of: ui?.steps.gen) { _, _ in if let ui { expanded = ui.steps.open } }
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .user(let text):
            // The words in the bubble; attached images and files under it.
            let parts = MessageFiles.split(text)
            VStack(alignment: .trailing, spacing: Space.s2) {
                if !parts.words.isEmpty {
                    HStack {
                        Spacer(minLength: Space.s8 * 5)  // a bubble stays within about 80% of the column
                        // A neutral bubble, not a coloured one (direction A): your words, on the right.
                        Text(parts.words).coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text).lineSpacing(
                            4
                        )
                        .padding(.horizontal, Space.s4).padding(.vertical, 10)
                        .background(SessionInk.bubble, in: coreShape(12))
                        .textSelection(.enabled)
                        .messageActions(text: parts.words, user: true, latest: latest, actions)
                    }
                }
                if !parts.files.isEmpty { MessageFilesView(paths: parts.files) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            // Printed on the glass, no bubble.
            MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading)
                .messageActions(text: text, user: false, latest: latest, actions)
        case .toolUse(_, let name, let summary) where CodeModeTool.of(name) != nil:
            CodeModeCard(
                tool: CodeModeTool.of(name)!, summary: summary, status: .running, output: "", durationMs: nil,
                expanded: $expanded)
        case .toolDone(_, let name, let summary, let ok, _, let output, let ms) where CodeModeTool.of(name) != nil:
            CodeModeCard(
                tool: CodeModeTool.of(name)!, summary: summary, status: ok ? .done : .failed, output: output,
                durationMs: ms, expanded: $expanded)
        case .toolUse(_, let name, let summary) where ConnCue.kind(name) != nil:
            ConnCue(tool: name, summary: summary, ok: nil, why: "")
        case .toolDone(_, let name, let summary, let ok, _, let output, _) where ConnCue.kind(name) != nil:
            ConnCue(
                tool: name, summary: summary, ok: ok, why: output.split(separator: "\n").first.map(String.init) ?? "",
                openConnections: openConnections)
        case .toolResult(_, let name?, let ok, _, let output, _) where ConnCue.kind(name) != nil:
            ConnCue(
                tool: name, summary: "", ok: ok, why: output.split(separator: "\n").first.map(String.init) ?? "",
                openConnections: openConnections)
        case .toolUse(_, let name, let summary):
            ToolCard(name: name, summary: summary, status: .running, output: "", expanded: $expanded)
        case .toolDone(_, let name, let summary, let ok, let code, let output, let ms):
            ToolCard(
                name: name, summary: summary, status: ok ? .ok(facts(nil, ms)) : .failed(facts(code, ms)),
                output: output, expanded: $expanded)
        case .toolResult(_, let name, let ok, let code, let output, let ms):
            ToolCard(
                name: name ?? "Result", summary: "", status: ok ? .ok(facts(nil, ms)) : .failed(facts(code, ms)),
                output: output, expanded: $expanded)
        case .toolEdit(_, let name, let path, let old, let new, let ok, let ms):
            EditCard(name: name, path: path, old: old, new: new, ok: ok, ms: ms, expanded: $expanded)
        case .toolTodos(_, let items): TodoCard(items: items)
        case .subAgent(let id, let type, let task, let prompt, let result, let ok, let ms):
            SubAgentLine(
                info: SubAgentInfo(id: id, type: type, task: task, prompt: prompt, result: result, ok: ok, ms: ms))
        case .plan(_, let text): PlanCard(text: text)
        case .turnEnded(let cost, let tokens):
            // The quietest line in the column (Ahmed, 2026-11-15): the time and the exact numbers wait in the tooltip.
            line(ConversationWords.turn(turn, cost: cost), time: false)
                .help(
                    [
                        entry.at.formatted(date: .omitted, time: .shortened),
                        tokens.map { "\(AgentWords.tokens($0)) tokens" }, AgentWords.exactCost(cost),
                    ].compactMap { $0 }.joined(separator: " · "))
        case .approvalRequest, .approvalDecided: EmptyView()  // drawn as one card by the transcript
        case .ended(let kind, let reason):
            line([ConversationWords.event(entry.kind, runner: runner) ?? ""])
                .help("Code: \(kind)" + (reason.map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
        case .started, .interrupted, .gap, .note:
            line([ConversationWords.event(entry.kind, runner: runner) ?? ""])
        case .hidden: EmptyView()
        }
    }

    private func facts(_ code: Int?, _ ms: Int?) -> String {
        [code.map { "exit \($0)" }, ms.map { "\(coreDecimal(Double($0) / 1000, 1)) s" }].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// An event as one quiet centred line (N42): "Turn 1 done · 1.9K tokens · $0.04 · 10:38". No rules, no dashes.
    private func line(_ parts: [String], time: Bool = true) -> some View {
        Text((parts + (time ? [entry.at.formatted(date: .omitted, time: .shortened)] : [])).joined(separator: " · "))
            .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Space.s1)
            .accessibilityElement(children: .combine)
    }
}

/// A tool call as one compact row in the agent's column (N33): chevron, tool icon, a short summary, the time it took and a
/// state mark. It opens to the full command and output, which animate in; a long command never shows in full by default.
struct ToolCard: View {
    enum Status {
        case running
        case ok(String)
        case failed(String)
    }
    let name: String
    let summary: String
    let status: Status
    let output: String
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    /// What the tool did, as a verb: "Read", "Edited", "Ran".
    static func verb(_ name: String) -> String {
        switch name.lowercased() {
        case "read", "notebookread": "Read"
        case "glob", "grep", "ls": "Searched"
        case "edit", "multiedit", "notebookedit": "Edited"
        case "write": "Wrote"
        case "bash", "shell": "Ran"
        case "webfetch": "Fetched"
        case "websearch": "Searched the web for"
        default: name
        }
    }

    private var symbol: String {
        switch name.lowercased() {
        case "bash", "shell": "terminal"
        case "read": "doc.text"
        case "glob", "grep", "ls": "magnifyingglass"
        case "edit", "write", "multiedit": "pencil"
        case "webfetch", "websearch": "globe"
        default: "wrench.and.screwdriver"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { expanded.toggle() }
            } label: {
                // One quiet line, no box (direction A): icon, the verb, what it acted on, then the time and its mark.
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Image(systemName: symbol).coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
                        .frame(width: Space.s4)
                    Text(Self.verb(name)).coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
                    Text(PathWords.short(summary.isEmpty ? name : summary))
                        .coreFont(size: 12, design: .monospaced).foregroundStyle(SessionInk.text)
                        .lineLimit(1).truncationMode(.middle)
                    // The working bar gives way to ✓ or ✗ with a short crossfade when the step finishes.
                    trailing.animation(Motion.out(0.2), value: statusKey)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s2).frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
            .help(summary.isEmpty ? name : summary)
            if expanded {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if !summary.isEmpty {
                        Text("$ " + summary).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(palette.text)
                    }
                    if !output.isEmpty { FoldedOutput(text: output) }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(GlassInk.sunk(0.25), in: coreShape(Radius.control))
                .padding([.horizontal, .bottom], Space.s2)
                .agentCopyMenu(output.isEmpty ? summary : output)
                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    private var statusKey: Int {
        switch status {
        case .running: 0
        case .ok: 1
        case .failed: 2
        }
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .running:
            HStack(spacing: Space.s2) {
                Text("running").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                CoreWorkingBar(width: Space.s8)
            }
        case .ok(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
                }
                Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.primary).accessibilityLabel("Done")
            }
        case .failed(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
                }
                Label("Failed", systemImage: "xmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(SessionInk.bad)
            }
        }
    }
}

extension View {
    /// A short conversation starts at the top (no empty band above it); a long one still opens at its latest message.
    @ViewBuilder fileprivate func shortStartsAtTop() -> some View {
        if #available(macOS 15, *) {
            defaultScrollAnchor(.top, for: .alignment).defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            defaultScrollAnchor(.bottom)
        }
    }
}
