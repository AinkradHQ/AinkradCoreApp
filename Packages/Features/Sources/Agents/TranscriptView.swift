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
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s3) {
                        header(store)
                        ForEach(Self.visible(store.entries)) { e in
                            row(e, store)
                                .id(e.seq)
                                // A new entry rises 6 pt as it fades in; with Reduce Motion it only fades.
                                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: 6)))
                        }
                        if session.live && !session.idle && store.load == .ready && !model.waiting(session.id) {
                            Thinking()
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
                    AppActionTile(title: "Latest", symbol: "arrow.down", key: "↓", hue: GlassInk.blue) {
                        toEnd(proxy)
                    }
                    .padding(Space.s4).transition(.opacity)
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

    @ViewBuilder private func row(_ e: TranscriptEntry, _ store: TranscriptStore) -> some View {
        if case .approvalRequest(let id, _, _, _) = e.kind, let r = store.approvals[id] {
            ApprovalEntryCard(model: model, request: r)
                .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: 6)))
        } else {
            EntryRow(entry: e, harness: session.harness) {
                model.shell.launcher.entry("connections")?.run()
            }
            .equatable()
            // A new entry rises 6 pt as it fades in; with Reduce Motion it only fades.
            .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: 6)))
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
                Text("Nothing here yet. Type a message below to begin.").meta(palette)
                    .frame(maxWidth: .infinity)
            } else {
                Label("Start of the session", systemImage: "flag.fill").coreFont(
                    size: MacTextSize.meta, weight: .semibold
                )
                .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3).frame(height: 24)
                .background(GlassInk.well, in: coreShape(6)).frame(maxWidth: .infinity).padding(.top, Space.s2)
            }
        }
    }
}

extension View {
    fileprivate func meta(_ p: Palette) -> some View { coreFont(size: MacTextSize.body).foregroundStyle(p.text2) }
}

/// Three small squares, the agent working. They rest under Reduce Motion.
struct Thinking: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduce)) { ctx in
            let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: Space.s1) {
                Text("thinking…").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.trailing, Space.s1)
                ForEach(0..<3, id: \.self) { i in
                    coreShape(2).fill(GlassInk.blue).frame(width: 7, height: 7)
                        .opacity(reduce || i == t ? 1 : 0.35).offset(y: reduce || i != t ? 0 : -3)
                        .animation(.spring(duration: 0.3), value: t)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityLabel("The AI session is working")
    }
}

/// One entry (N33, one column): the agent speaks at the left, you in a blue bubble at the right, each tool call as one
/// compact row that opens to its output, events as thin quiet dividers. Equatable, so
/// SwiftUI skips rows whose entry did not change.
struct EntryRow: View, Equatable {
    let entry: TranscriptEntry
    var harness = "claude"
    /// Opens Connections from a refused connection call (CN5).
    var openConnections: (() -> Void)?
    @State private var expanded = false

    nonisolated static func == (a: EntryRow, b: EntryRow) -> Bool { a.entry == b.entry && a.harness == b.harness }

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: Space.s8)
                Text(text).coreFont(size: MacTextSize.body).foregroundStyle(.white)
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(
                        LinearGradient(
                            colors: [GlassInk.blue, GlassInk.blue.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(Radius.cardMac)
                    )
                    .agentCopyMenu(text)
            }
            .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            HStack(alignment: .top, spacing: Space.s2) {
                MarkdownText(text)
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(GlassInk.well, in: coreShape(Radius.cardMac))
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                    .agentCopyMenu(text)
                Spacer(minLength: Space.s8)
            }
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
        case .turnEnded(let cost, let tokens): TurnDivider(at: entry.at, cost: cost, tokens: tokens)
        case .approvalRequest, .approvalDecided: EmptyView()  // drawn as one card by the transcript
        case .started(let h, let resumed):
            chip(resumed ? "woke up" : "started" + (h.map { " · \($0)" } ?? ""))
        case .interrupted(let reason):
            chip("interrupted" + (reason.isEmpty ? "" : ": \(AgentWords.reasonWords(reason))"))
        case .gap(let from, let to):
            chip("entries \(from) to \(to) were not kept")
        case .ended(let kind, let reason):
            let budget = kind == "budget" || (kind == "cancelled" && reason?.lowercased().contains("budget") == true)
            let why = budget ? nil : reason.flatMap { $0.isEmpty ? nil : AgentWords.reasonWords($0) }
            chip(Self.endedLine(budget ? "budget" : kind) + (why.map { " · \($0)" } ?? ""))
                .help("Code: \(kind)" + (reason.map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
        case .note(let type, let detail):
            chip((detail.isEmpty ? Self.words(type) : "\(Self.words(type)): \(detail)").lowercased())
        case .hidden: EmptyView()
        }
    }

    /// `approval_escalated` → `Approval escalated`.
    static func words(_ code: String) -> String {
        let w = code.replacingOccurrences(of: "_", with: " ")
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    private func facts(_ code: Int?, _ ms: Int?) -> String {
        [code.map { "exit \($0)" }, ms.map { "\(coreDecimal(Double($0) / 1000, 1)) s" }].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// "Ended: finished" reads as "finished" in a divider.
    static func endedLine(_ kind: String) -> String {
        let w = AgentWords.endedWords(kind)
        return w.hasPrefix("Ended: ") ? String(w.dropFirst(7)) : w.lowercased()
    }

    /// An event as a thin, quiet divider (N33): small text with its time, no pill, no colour.
    private func chip(_ text: String) -> some View {
        Text("— \(text) · \(entry.at.formatted(date: .omitted, time: .shortened)) —")
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary.opacity(0.8))
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
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if reduce {
                        expanded.toggle()
                    } else {
                        withAnimation(.smooth(duration: 0.25)) { expanded.toggle() }
                    }
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "chevron.right").coreFont(size: 10, weight: .semibold)
                            .foregroundStyle(GlassInk.secondary).rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 12)
                        Image(systemName: symbol).foregroundStyle(GlassInk.blue).frame(width: 16)
                        Text(PathWords.short(summary.isEmpty ? name : summary))
                            .coreFont(size: MacTextSize.body).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Space.s2)
                        trailing
                    }
                    .padding(.horizontal, Space.s2).frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(summary.isEmpty ? name : summary)
                if expanded {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        if !summary.isEmpty {
                            Text("$ " + summary).coreFont(size: 12, design: .monospaced)
                                .foregroundStyle(GlassInk.primary)
                        }
                        if !output.isEmpty { FoldedOutput(text: output) }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3)
                    .background(.black.opacity(0.25), in: coreShape(Radius.control))
                    .padding([.horizontal, .bottom], Space.s2)
                    .agentCopyMenu(output.isEmpty ? summary : output)
                    .transition(.opacity)
                }
            }
            .foregroundStyle(GlassInk.primary)
            .frame(maxWidth: .infinity)
            .background(GlassInk.well, in: coreShape(Radius.control + 2))
            .overlay { coreShape(Radius.control + 2).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
            .clipShape(coreShape(Radius.control + 2))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .running:
            // A small spinner while it runs; under Reduce Motion a still word.
            if reduce {
                Text("running").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
        case .ok(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
                Image(systemName: "checkmark").foregroundStyle(GlassInk.green)
            }
        case .failed(let facts):
            HStack(spacing: Space.s2) {
                if !facts.isEmpty {
                    Text(facts).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
                Image(systemName: "xmark").foregroundStyle(GlassInk.red)
            }
        }
    }
}
