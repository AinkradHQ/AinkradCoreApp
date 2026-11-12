import CoreUI
import SwiftUI

/// The streamed transcript: a lazy column, one row per entry with the seq as its identity, so an appended entry adds a row and
/// leaves the rest alone. It follows the end while you are at the end; scrolling up loads earlier entries.
struct TranscriptView: View {
    @Bindable var model: AgentsModel
    let store: TranscriptStore?
    let session: AgentSessionInfo
    var jump = 0
    @State private var atEnd = true
    /// A scroll to the end is queued for the next frame: a burst of entries asks once, not once each.
    @State private var scrollQueued = false
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
                    LazyVStack(alignment: .leading, spacing: Space.s3) {
                        header(store)
                        let turns = ConversationWords.turns(store.entries)
                        ForEach(Self.visible(store.entries)) { e in
                            row(e, store, turn: turns[e.seq])
                                .id(e.seq)
                                // A new entry rises 6 pt as it fades in; with Reduce Motion it only fades.
                                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
                        }
                        if session.live && !session.idle && store.load == .ready && !model.waiting(session.id) {
                            Thinking(since: session.updatedAt)
                        }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atEnd = true }
                            .onDisappear { atEnd = false }
                    }
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.never)
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
                if !atEnd {
                    // A quiet glass control centred over the composer, not an action tile.
                    Button(action: { toEnd(proxy) }) { Label("Latest", systemImage: "chevron.down") }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small)).environment(\.coreKeycap, "↓")
                        .coreGlass(radius: Radius.chip)
                        .help("Jump to the newest message (↓)")
                        .padding(.bottom, Space.s2)
                        .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
                }
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
            ApprovalEntryCard(model: model, request: r)
                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: Space.s2)))
        } else {
            EntryRow(entry: e, harness: session.harness, runner: model.runnerName(session.runner), turn: turn) {
                model.shell.launcher.entry("connections")?.run()
            }
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
            WorkingBar()
            Text("Thinking…").coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                Text(coreUnit("\(max(0, Int(ctx.date.timeIntervalSince(since))))", "s"))
                    .coreFont(size: MacTextSize.body).foregroundStyle(palette.text2).monospacedDigit()
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
    /// Opens Connections from a refused connection call (CN5).
    var openConnections: (() -> Void)?
    @State private var expanded = false

    nonisolated static func == (a: EntryRow, b: EntryRow) -> Bool {
        a.entry == b.entry && a.harness == b.harness && a.runner == b.runner && a.turn == b.turn
    }
    @Environment(\.corePalette) private var palette

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: Space.s8)
                Text(text).coreFont(size: MacTextSize.body).foregroundStyle(palette.btnInk)
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.btnPrimary, in: coreShape(Radius.cardMac))
                    .textSelection(.enabled)
                    .agentCopyMenu(text)
            }
            .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            // Printed on the glass, no bubble.
            MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading).agentCopyMenu(text)
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
        case .turnEnded(let cost, let tokens):
            line(ConversationWords.turn(turn, cost: cost))
                .help(
                    [tokens.map { "\(AgentWords.tokens($0)) tokens" }, AgentWords.exactCost(cost)].compactMap { $0 }
                        .joined(separator: " · "))
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
    private func line(_ parts: [String]) -> some View {
        Text((parts + [entry.at.formatted(date: .omitted, time: .shortened)]).joined(separator: " · "))
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
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
                withAnimation(reduce ? nil : Motion.out(Motion.ui)) { expanded.toggle() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: Space.s3)
                    Image(systemName: symbol).foregroundStyle(palette.primary).frame(width: Space.s4)
                    Text(PathWords.short(summary.isEmpty ? name : summary))
                        .coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.s2)
                    trailing
                }
                .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolRowStyle())
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
                .background(.black.opacity(0.25), in: coreShape(Radius.control))
                .padding([.horizontal, .bottom], Space.s2)
                .agentCopyMenu(output.isEmpty ? summary : output)
                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity)
        .clipShape(coreShape(Radius.control))
        .coreWell(radius: Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .running:
            HStack(spacing: Space.s2) {
                Text("running").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                WorkingBar(width: Space.s8)
            }
        case .ok(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                }
                Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.primary).accessibilityLabel("Done")
            }
        case .failed(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                }
                Image(systemName: "xmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.tone(.fail).ink).accessibilityLabel("Failed")
            }
        }
    }
}

/// The press and hover of a tool row: the well lightens on hover, presses to 0.99 (darkens under Reduce Motion).
struct ToolRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ToolRowBody(configuration: configuration) }
}

private struct ToolRowBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hovering = false
    var body: some View {
        configuration.label
            .background(hovering || configuration.isPressed ? palette.uDim : .clear)
            .overlay { Color.black.opacity(configuration.isPressed && reduce ? 0.12 : 0).allowsHitTesting(false) }
            .scaleEffect(configuration.isPressed && !reduce ? 0.99 : 1)
            .animation(Motion.out(Motion.hover), value: hovering)
            .animation(Motion.press(Motion.press), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
