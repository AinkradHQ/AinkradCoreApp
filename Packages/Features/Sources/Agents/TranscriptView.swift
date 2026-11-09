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
                        ForEach(store.entries) { e in
                            EntryRow(entry: e, harness: session.harness) {
                                model.shell.launcher.entry("connections")?.run()
                            }
                            .equatable().id(e.seq)
                            .transition(
                                reduce
                                    ? .opacity
                                    : .opacity.combined(with: .move(edge: .bottom)).combined(
                                        with: .scale(scale: 0.97, anchor: .bottomLeading)))
                        }
                        if session.live && store.load == .ready && !model.waiting(session.id) { Thinking() }
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
                    if atEnd { withAnimation(.spring(duration: 0.4)) { proxy.scrollTo("end", anchor: .bottom) } }
                }
                .onChange(of: jump) { _, _ in
                    withAnimation(.spring(duration: 0.4)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                if !atEnd {
                    AppActionTile(title: "Latest", symbol: "arrow.down", key: "↓", hue: GlassInk.blue) {
                        withAnimation(.spring(duration: 0.4)) { proxy.scrollTo("end", anchor: .bottom) }
                    }
                    .padding(Space.s4).transition(.scale.combined(with: .opacity))
                }
            }
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
                Text("Nothing here yet. The first entries arrive when the agent starts.").meta(palette)
                    .frame(maxWidth: .infinity)
            } else {
                Label("Start of the session", systemImage: "flag.fill").font(
                    .system(size: MacTextSize.meta, weight: .semibold)
                )
                .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3).frame(height: 24)
                .background(GlassInk.well, in: coreShape(6)).frame(maxWidth: .infinity).padding(.top, Space.s2)
            }
        }
    }
}

extension Text {
    fileprivate func meta(_ p: Palette) -> some View { font(.system(size: MacTextSize.body)).foregroundStyle(p.text2) }
}

/// Three small squares, the agent working. They rest under Reduce Motion.
private struct Thinking: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduce)) { ctx in
            let t = Int(ctx.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: Space.s1) {
                ForEach(0..<3, id: \.self) { i in
                    coreShape(2).fill(GlassInk.violet).frame(width: 7, height: 7)
                        .opacity(reduce || i == t ? 1 : 0.35).offset(y: reduce || i != t ? 0 : -3)
                        .animation(.spring(duration: 0.3), value: t)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityLabel("The agent is working")
    }
}

/// One entry, visual (Ahmed, 2026-11-05): the agent speaks beside its glyph, you in a blue bubble at the right, each tool
/// call as a card with its own icon and a live status, its output folded inside; events as tinted chips. Equatable, so
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
                Text(text).font(.system(size: MacTextSize.body)).foregroundStyle(.white)
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(
                        LinearGradient(
                            colors: [GlassInk.blue, GlassInk.blue.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                        in: coreShape(Radius.cardMac)
                    )
                    .shadow(color: GlassInk.blue.opacity(0.3), radius: 8, y: 2)
                    .agentCopyMenu(text)
            }
            .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            HStack(alignment: .top, spacing: Space.s2) {
                let hue = SessionTile.hue(harness)
                Image(systemName: AgentsModel.harnessSymbol(harness)).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white).frame(width: 26, height: 26)
                    .background(hue.opacity(0.85), in: coreShape(7))
                    .shadow(color: hue.opacity(0.4), radius: 6)
                    .accessibilityHidden(true)
                Text(text).font(.system(size: MacTextSize.body)).lineSpacing(3).textSelection(.enabled)
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
                name: name, summary: summary, status: ok ? .ok(facts(code, ms)) : .failed(facts(code, ms)),
                output: output, expanded: $expanded)
        case .toolResult(_, let name, let ok, let code, let output, let ms):
            ToolCard(
                name: name ?? "Result", summary: "", status: ok ? .ok(facts(code, ms)) : .failed(facts(code, ms)),
                output: output, expanded: $expanded)
        case .approvalRequest(_, let tool, let input, _):
            chip(
                "lock.shield.fill", "Asked to \(ApprovalWords.ask(tool).verb)\(input.isEmpty ? "" : ": \(input)")",
                GlassInk.orange)
        case .approvalDecided(_, let approved):
            chip(
                approved ? "checkmark.shield.fill" : "xmark.shield.fill", approved ? "Approved" : "Denied",
                approved ? GlassInk.green : GlassInk.red)
        case .started(let h, let resumed):
            chip(
                resumed ? "arrow.clockwise" : "play.fill",
                (resumed ? "Resumed" : "Started") + (h.map { " · \($0)" } ?? ""), GlassInk.blue)
        case .interrupted(let reason):
            chip("arrow.clockwise", "Interrupted" + (reason.isEmpty ? "" : ": \(reason)"), GlassInk.orange)
        case .gap(let from, let to):
            chip("ellipsis", "Entries \(from) to \(to) were not kept", GlassInk.orange)
        case .ended(let kind, let reason):
            chip(
                kind == "succeeded" ? "flag.checkered" : "stop.fill",
                "Ended: \(kind)" + (reason.map { $0.isEmpty ? "" : " · \($0)" } ?? ""),
                kind == "succeeded" ? GlassInk.green : GlassInk.orange)
        case .note(let type, let detail):
            chip(
                "info.circle.fill", detail.isEmpty ? Self.words(type) : "\(Self.words(type)): \(detail)", GlassInk.slate
            )
        case .hidden: EmptyView()
        }
    }

    /// `approval_escalated` → `Approval escalated`.
    static func words(_ code: String) -> String {
        let w = code.replacingOccurrences(of: "_", with: " ")
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    private func facts(_ code: Int?, _ ms: Int?) -> String {
        [code.map { "exit \($0)" }, ms.map { String(format: "%.1f s", Double($0) / 1000) }].compactMap { $0 }
            .joined(separator: " · ")
    }

    private func chip(_ symbol: String, _ text: String, _ hue: Color) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).foregroundStyle(hue).accessibilityHidden(true)
            Text(text).lineLimit(2)
        }
        .font(.system(size: MacTextSize.meta, weight: .medium))
        .foregroundStyle(GlassInk.primary.opacity(0.9))
        .padding(.horizontal, Space.s3).padding(.vertical, 5)
        .background(hue.opacity(0.14), in: coreShape(7))
        .overlay { coreShape(7).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

/// A tool call as a card: an icon tile for the tool, the command in mono, a live status at the right (a spinner while it
/// runs, a green or red mark when done), and its output folded under, six lines and a way to the rest.
private struct ToolCard: View {
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
    @State private var spin = false

    private var hue: Color {
        switch name.lowercased() {
        case "bash", "shell": GlassInk.green
        case "read", "glob", "grep", "ls": GlassInk.blue
        case "edit", "write", "multiedit": GlassInk.orange
        case "webfetch", "websearch": GlassInk.violet
        default: GlassInk.slate
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
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let long = lines.count > 6
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(hue.opacity(0.85), in: coreShape(7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(hue)
                    if !summary.isEmpty {
                        Text(summary).font(.system(size: 12, design: .monospaced)).lineLimit(2)
                            .truncationMode(.middle).textSelection(.enabled)
                    }
                }
                Spacer(minLength: Space.s2)
                statusView
            }
            .padding(Space.s2)
            if !output.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(long && !expanded ? lines.prefix(6).joined(separator: "\n") + "\n…" : output)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(GlassInk.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if long {
                        Button {
                            withAnimation(.spring(duration: 0.35)) { expanded.toggle() }
                        } label: {
                            Label(
                                expanded ? "Show less" : "Show all \(lines.count) lines",
                                systemImage: expanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(hue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s3)
                .background(.black.opacity(0.25))
                .agentCopyMenu(output)
            }
        }
        .background(GlassInk.well)
        .clipShape(coreShape(Radius.control + 2))
        .overlay(alignment: .leading) { coreShape(2).fill(hue).frame(width: 3).padding(.vertical, Space.s2) }
        .overlay { coreShape(Radius.control + 2).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .running:
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath").rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                Text("running")
            }
            .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.blueInk)
        case .ok(let facts):
            badge("checkmark", facts.isEmpty ? "ok" : "ok · \(facts)", GlassInk.green)
        case .failed(let facts):
            badge("xmark", facts.isEmpty ? "failed" : "failed · \(facts)", GlassInk.red)
        }
    }

    private func badge(_ symbol: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).symbolEffect(.bounce, value: text)
            Text(text).monospacedDigit()
        }
        .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(c)
        .padding(.horizontal, 7).frame(height: 20)
        .background(c.opacity(0.15), in: coreShape(5))
    }
}
