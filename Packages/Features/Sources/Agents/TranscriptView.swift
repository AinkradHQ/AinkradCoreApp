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
                            EntryRow(entry: e, harness: session.harness).equatable().id(e.seq)
                                .transition(
                                    reduce
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .bottom)).combined(
                                            with: .scale(scale: 0.97, anchor: .bottomLeading)))
                        }
                        if session.live && store.load == .ready && !model.waiting(session.id) {
                            BusyBar().frame(width: Space.s8 * 2).padding(.vertical, Space.s1)
                        }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atEnd = true }
                            .onDisappear { atEnd = false }
                    }
                    .padding(.horizontal, Space.s4).padding(.bottom, Space.s3)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.never)
                .animation(Motion.out(Motion.move), value: store.entries.count)
                .onChange(of: store.lastSeq) { _, _ in
                    if atEnd { withAnimation(Motion.out(Motion.move)) { proxy.scrollTo("end", anchor: .bottom) } }
                }
                .onChange(of: jump) { _, _ in
                    withAnimation(Motion.out(Motion.move)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                if !atEnd {
                    AppActionTile(title: "Latest", symbol: "arrow.down", key: "↓", hue: GlassInk.blue) {
                        withAnimation(Motion.out(Motion.move)) { proxy.scrollTo("end", anchor: .bottom) }
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
            BusyBar().frame(maxWidth: .infinity)
        case .failed(let why):
            NoticeBanner(
                notice: InlineNotice(
                    title: "Could not load the transcript",
                    detail: "Check that your Core is reachable, then try again.",
                    tone: .fail)
            )
            .help(why)
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
                .foregroundStyle(GlassInk.secondary).padding(.horizontal, Space.s3).frame(height: MacSize.controlSm)
                .background(GlassInk.well, in: coreShape(Radius.chip)).frame(maxWidth: .infinity).padding(
                    .top, Space.s2)
            }
        }
    }
}

extension Text {
    fileprivate func meta(_ p: Palette) -> some View { font(.system(size: MacTextSize.body)).foregroundStyle(p.text2) }
}

/// One entry, visual (Ahmed, 2026-11-05): the agent speaks beside its glyph, you in a blue bubble at the right, each tool
/// call as a card with its own icon and a live status, its output folded inside; events as tinted chips. Equatable, so
/// SwiftUI skips rows whose entry did not change.
struct EntryRow: View, Equatable {
    let entry: TranscriptEntry
    var harness = "claude"
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
                    .agentCopyMenu(text)
            }
            .accessibilityLabel("You: \(text)")
        case .assistant(let text):
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: AgentsModel.harnessSymbol(harness))
                    .font(.system(size: MacTextSize.body, weight: .semibold))
                    .foregroundStyle(.white).frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(GlassInk.blue.opacity(0.85), in: coreShape(Radius.control))
                    .accessibilityHidden(true)
                Text(text).font(.system(size: MacTextSize.body)).lineSpacing(3).textSelection(.enabled)
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(GlassInk.well, in: coreShape(Radius.cardMac))
                    .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
                    .agentCopyMenu(text)
                Spacer(minLength: Space.s8)
            }
        case .toolUse(_, let name, let summary):
            ToolCard(name: name, summary: summary, status: .running, output: "", expanded: $expanded)
        case .toolDone(_, let name, let summary, let ok, let code, let output, let ms):
            ToolCard(
                name: name, summary: summary,
                status: .finished(ok: ok, text: facts(ok, code, ms), help: codeHelp(code)),
                output: output, expanded: $expanded)
        case .toolResult(_, let name, let ok, let code, let output, let ms):
            ToolCard(
                name: name ?? "Result", summary: "",
                status: .finished(ok: ok, text: facts(ok, code, ms), help: codeHelp(code)),
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
                (resumed ? "Resumed" : "Started") + (h.map { " · \(AgentWords.harness($0))" } ?? ""), GlassInk.slate)
        case .interrupted(let reason):
            chip("arrow.clockwise", "Interrupted" + (reason.isEmpty ? "" : ": \(reason)"), GlassInk.orange)
        case .gap(let from, let to):
            chip("ellipsis", "Entries \(from) to \(to) were not kept", GlassInk.orange)
        case .ended(let kind, let reason):
            let why = Self.sentence(reason ?? "")
            chip(
                kind == "succeeded" ? "flag.checkered" : "stop.fill",
                "Ended: \(SessionOutcome(rawValue: kind).label)" + (why.isEmpty ? "" : " · \(why)"),
                kind == "succeeded" ? GlassInk.green : kind == "failed" ? GlassInk.red : GlassInk.orange, help: kind)
        case .note(let type, let detail):
            chip(
                "info.square.fill", detail.isEmpty ? Self.words(type) : "\(Self.words(type)): \(detail)",
                GlassInk.slate,
                help: type
            )
        case .hidden: EmptyView()
        }
    }

    /// A reason as a short label: first letter capital, no trailing period.
    static func sentence(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix(".") { t.removeLast() }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// `approval_escalated` → `Approval escalated`.
    static func words(_ code: String) -> String {
        let w = code.replacingOccurrences(of: "_", with: " ")
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    private func facts(_ ok: Bool, _ code: Int?, _ ms: Int?) -> String {
        AgentWords.toolFacts(ok: ok, code: code, ms: ms)
    }
    private func codeHelp(_ code: Int?) -> String? { code.map { "Exit code \($0)" } }

    private func chip(_ symbol: String, _ text: String, _ hue: Color, help: String = "") -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).foregroundStyle(hue).accessibilityHidden(true)
            Text(text).lineLimit(2)
        }
        .font(.system(size: MacTextSize.meta, weight: .medium))
        .foregroundStyle(GlassInk.primary.opacity(0.9))
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
        .background(hue.opacity(0.14), in: coreShape(Radius.chip))
        .overlay { coreShape(Radius.chip).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
        .frame(maxWidth: .infinity, alignment: .center)
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

/// A tool call as a card: an icon tile for the tool, the command in mono, a live status at the right (a bar while it
/// runs, Done or Failed when finished), and its output folded under, six lines and a way to the rest.
private struct ToolCard: View {
    enum Status {
        case running
        case finished(ok: Bool, text: String, help: String?)
    }
    let name: String
    let summary: String
    let status: Status
    let output: String
    @Binding var expanded: Bool

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
                Image(systemName: symbol).font(.system(size: MacTextSize.body, weight: .semibold)).foregroundStyle(
                    .white
                )
                .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                .background(GlassInk.slate.opacity(0.85), in: coreShape(Radius.control))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(
                        GlassInk.secondary)
                    if !summary.isEmpty {
                        Text(summary).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(2)
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
                        .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(GlassInk.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if long {
                        Button {
                            withAnimation(Motion.out(Motion.move)) { expanded.toggle() }
                        } label: {
                            Label(
                                expanded ? "Show less" : "Show all \(lines.count) lines",
                                systemImage: expanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s3)
                .background(GlassInk.well)
                .agentCopyMenu(output)
            }
        }
        .background(GlassInk.well)
        .clipShape(coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool \(name): \(summary)")
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .running:
            HStack(spacing: Space.s2) {
                BusyBar().frame(width: Space.s8 * 1.5)
                Text("Running")
            }
            .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.blue)
        case .finished(let ok, let text, let help):
            badge(ok ? "checkmark.square.fill" : "xmark.square", text, ok ? GlassInk.green : GlassInk.red)
                .help(help ?? "")
        }
    }

    private func badge(_ symbol: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).symbolEffect(.bounce, value: text)
            Text(text).monospacedDigit()
        }
        .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(c)
        .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
        .background(c.opacity(0.15), in: coreShape(Radius.chip))
    }
}
