import CoreUI
import SwiftUI

/// The conversation's right column (Ahmed, 2026-11-16: "separated cards rather than one panel"; mockup
/// `Designs/core/session-v3-panel`): seven cards, each folding on its own. Session (state, where it runs, the turn strip),
/// Changes (files, diff bars, review inside the card), Sub-agents, Tasks, Activity, Approvals and connections, Usage.
/// Tasks, Activity and Approvals start folded so the column fits; it scrolls past that.
struct SessionSidePanel: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    var find: (() -> Void)?
    @Environment(\.sessionUI) private var ui

    static let width: CGFloat = 304

    var body: some View {
        let entries = model.transcripts[session.id]?.entries ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                SessionCard(model: model, session: session, entries: entries)
                ChangesCard(model: model, session: session, entries: entries, diff: diff)
                let subs = SubAgentInfo.all(entries)
                if !subs.isEmpty {
                    SubAgentsCard(
                        list: subs, again: model.canWrite(session) ? { runAgain($0) } : nil,
                        stop: session.canStopSubagents ? { model.stopSubagent(session.id, $0.id) } : nil)
                }
                if let todos = TasksCard.latest(entries) { TasksCard(items: todos) }
                ActivityCard(entries: entries)
                ApprovalsCard(model: model, session: session, entries: entries)
                UsageCard(model: model, session: session)
            }
            .padding(.bottom, Space.s6)
        }
        .scrollIndicators(.never)
        // A soft edge where the column runs past the window (the system's, not a mask: see TranscriptView).
        .softScrollEdges()
        .task(id: session.id) { await model.followRoute(session.id) }
    }

    /// A failed sub-agent's brief, in the message field: sending it is the user's call.
    func runAgain(_ a: SubAgentInfo) {
        model.drafts[session.id] =
            "Run the \(SubAgentInfo.kind(a.type).lowercased()) sub-agent again, with this brief:\n\n\(a.prompt)"
    }

    func diff(_ path: String) -> [DiffLine] {
        var out: [DiffLine] = []
        for e in model.transcripts[session.id]?.entries ?? [] {
            if case .toolEdit(_, _, let p, let old, let new, let ok, _) = e.kind, p == path, ok != false {
                out += DiffLines.make(old: old, new: new).map {
                    DiffLine(id: out.count + $0.id, kind: $0.kind, number: $0.number, text: $0.text)
                }
            }
        }
        return out
    }
}

/// One card of the column: a header (chevron, title, count, one quiet action; a one-line summary when folded) and its
/// content, folding on its own (remembered per card). Its fill follows the Look, with a soft shadow and no line.
struct SideCard<Content: View>: View {
    let title: String
    var count: String?
    var summary: String = ""
    var action: (title: String, key: String, run: () -> Void)?
    /// Room at the right of the header for the column's fixed toggle (the first card).
    var toggleRoom = false
    @ViewBuilder let content: () -> Content
    @AppStorage private var folded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(
        id: String, title: String, foldedAtFirst: Bool = false, count: String? = nil, summary: String = "",
        action: (title: String, key: String, run: () -> Void)? = nil, toggleRoom: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.summary = summary
        self.action = action
        self.toggleRoom = toggleRoom
        self.content = content
        _folded = AppStorage(wrappedValue: foldedAtFirst, "agents.card.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    withAnimation(Motion.calm(Motion.out(0.22), reduce)) { folded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                            .foregroundStyle(SessionInk.text2).rotationEffect(.degrees(folded ? -90 : 0))
                            .frame(width: Space.s3)
                        Text(title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(SessionInk.text)
                        if let count {
                            Text(count).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                                .monospacedDigit().contentTransition(.numericText())
                        }
                        if folded && !summary.isEmpty {
                            Text(summary).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                                .lineLimit(1).truncationMode(.tail).transition(.opacity)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(folded ? "Show \(title)" : "Fold \(title)")
                .accessibilityLabel(title)
                .accessibilityValue(folded ? "Folded" : "Open")
                if let action, !folded {
                    Button(action.title, action: action.run).buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .fixedSize().help("\(action.title) (\(action.key))").keyHint(action.key)
                }
            }
            .padding(.trailing, toggleRoom ? Space.s8 + Space.s2 : 0)
            if !folded {
                content()
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface())
        .animation(Motion.calm(Motion.out(0.22), reduce), value: folded)
    }
}

// MARK: Session

/// What the session is doing now, where it runs, and its turns as a strip (each as wide as it took; click to jump).
struct SessionCard: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    let entries: [TranscriptEntry]
    @Environment(\.sessionUI) private var ui
    @Environment(\.corePalette) private var palette

    var body: some View {
        let waiting = model.pending.first { $0.session == session.id }
        let st = AgentWords.status(session, waiting: waiting != nil)
        let turns = TurnStrip.turns(entries, running: session.live && !session.idle && waiting == nil)
        SideCard(id: "session", title: "Session", summary: st.label, toggleRoom: true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        coreShape(2).fill(palette.tone(st.tone).ink).frame(width: 8, height: 8)
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                        Text(st.label).coreFont(size: MacTextSize.title, weight: .semibold)
                        if let w = waiting {
                            Text("waiting " + AgentWords.clock(ctx.date.timeIntervalSince(w.requestedAt)))
                                .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
                        }
                    }
                }
                if let w = waiting {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "terminal").foregroundStyle(SessionInk.text2)
                        Text(w.input).coreFont(size: 12, design: .monospaced).lineLimit(1).truncationMode(.tail)
                    }
                    .padding(.horizontal, Space.s2).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .background(SessionInk.row, in: coreShape(Radius.control))
                    .help(w.input)
                }
                FlowRow(spacing: Space.s1) {
                    if let mode = SessionMode.of(session) { tag(mode.symbol, mode.title).help(mode.help) }
                    tag(
                        "terminal",
                        AgentWords.toolName(session.harness) + " · " + (session.model ?? "default model"))
                    tag("server.rack", model.runnerName(session.runner))
                    tag("folder", session.project ?? "Fresh folder")
                    if let b = session.branch { tag("arrow.triangle.branch", b) }
                    if let a = session.route?.account { tag("person", model.accountNames[a] ?? "an account") }
                }
                if !turns.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        // A long transcript loads in pages: say these are the loaded turns, not the session's first ones.
                        let paged = model.transcripts[session.id]?.hasEarlier == true
                        let resumed = turns.filter(\.interrupted).count
                        Text(
                            (paged ? "Latest \(turns.count) turns loaded" : "Turns  \(turns.count)")
                                + (resumed == 1 ? " · resumed once" : resumed > 1 ? " · resumed \(resumed) times" : "")
                        )
                        .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                        TurnStrip(turns: turns) { ui?.jumpTo = $0 }
                    }
                }
                HStack {
                    Text("Started " + session.createdAt.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text("Last activity " + AgentWords.ago(session.updatedAt))
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            }
        }
    }

    private func tag(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).lineLimit(1)
            .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text)
            .padding(.horizontal, Space.s2).frame(minHeight: 22)
            .background(SessionInk.row, in: coreShape(6))
            .help(text)
    }
}

/// The session's turns side by side: each as wide as it took (at least a label's width), a mark where it was interrupted,
/// the running turn's bar moving. Hover shows its time and cost; a click jumps the conversation to it.
struct TurnStrip: View {
    struct Turn: Identifiable, Equatable {
        let number: Int
        let start: Int64
        let seconds: Int
        let cost: Int64?
        let interrupted: Bool
        let running: Bool
        var id: Int { number }
    }
    let turns: [Turn]
    let jump: (Int64) -> Void

    /// Up to this many turns show as numbered segments; more become a dense bar chart (Ahmed, 2026-11-16: sessions can
    /// run past 100 turns).
    static let numbered = 10

    var body: some View {
        if turns.count <= Self.numbered { segments } else { dense }
    }

    private var segments: some View {
        GeometryReader { g in
            let total = Double(max(turns.map { max($0.seconds, 1) }.reduce(0, +), 1))
            let gaps = CGFloat(turns.count - 1) * 4 + CGFloat(turns.filter(\.interrupted).count) * 6
            let free = max(g.size.width - gaps - CGFloat(turns.count) * 28, 0)
            HStack(spacing: 4) {
                ForEach(turns) { t in
                    if t.interrupted {
                        coreShape(1).fill(SessionInk.text2).frame(width: 2, height: 20)
                            .help("Interrupted here, then resumed")
                    }
                    Button {
                        jump(t.start)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            coreShape(6).fill(SessionInk.row)
                            if t.running {
                                CoreWorkingBar(width: Space.s8).padding(4)
                            } else {
                                coreShape(1).fill(SessionInk.ink.opacity(0.6)).frame(height: 2).padding(.horizontal, 4)
                                    .padding(.bottom, 3)
                            }
                            Text("\(t.number)").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                                .padding(.leading, 6).padding(.bottom, 7)
                        }
                        .frame(width: 28 + free * CGFloat(Double(max(t.seconds, 1)) / total), height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CoreQuietPressStyle(radius: 6, scale: 0.97, hoverFill: true))
                    .help(Self.help([t]))
                }
            }
        }
        .frame(height: 26)
    }

    /// One thin bar per turn, as tall as the turn took; when there are more turns than room, neighbours share a bar.
    private var dense: some View {
        GeometryReader { g in
            let slots = max(Int(g.size.width / 3), 1)
            let groups = Self.groups(turns, slots: slots)
            let top = Double(groups.map { $0.map(\.seconds).reduce(0, +) }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    let secs = Double(group.map(\.seconds).reduce(0, +))
                    let last = group.contains { $0.running || $0.number == turns.last?.number }
                    Button {
                        jump(group[0].start)
                    } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            coreShape(1)
                                .fill(last ? SessionInk.ink : SessionInk.ink.opacity(0.45))
                                .frame(height: max(3, 26 * CGFloat(secs / max(top, 1))))
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Self.help(group))
                    .padding(.leading, group.contains(where: \.interrupted) ? 2 : 0)
                }
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(turns.count) turns")
    }

    /// Turns spread over at most `slots` bars, in order.
    static func groups(_ turns: [Turn], slots: Int) -> [[Turn]] {
        guard turns.count > slots else { return turns.map { [$0] } }
        let size = Int((Double(turns.count) / Double(slots)).rounded(.up))
        return stride(from: 0, to: turns.count, by: size).map { Array(turns[$0..<min($0 + size, turns.count)]) }
    }

    static func help(_ group: [Turn]) -> String {
        guard let a = group.first, let b = group.last else { return "" }
        let name = group.count == 1 ? "Turn \(a.number)" : "Turns \(a.number)–\(b.number)"
        let secs = group.map(\.seconds).reduce(0, +)
        let cost = group.compactMap(\.cost).reduce(0, +)
        return name + (b.running ? " · working" : " · " + ConversationWords.took(secs))
            + (cost > 0 ? AgentWords.cost(cost).map { " · \($0)" } ?? "" : "") + "\nClick to jump to it"
    }

    /// The turns from the transcript: each starts at your message and ends at its "turn done"; an interruption between
    /// two marks the next one; a running session has one more turn, still working.
    static func turns(_ entries: [TranscriptEntry], running: Bool) -> [Turn] {
        var out: [Turn] = []
        var start: (seq: Int64, at: Date)?
        var interrupted = false
        for e in entries {
            switch e.kind {
            case .user: if start == nil { start = (e.seq, e.at) }
            case .interrupted: interrupted = true
            case .turnEnded(let cost, _):
                if let s = start {
                    out.append(
                        Turn(
                            number: out.count + 1, start: s.seq, seconds: max(0, Int(e.at.timeIntervalSince(s.at))),
                            cost: cost, interrupted: interrupted && !out.isEmpty, running: false))
                    interrupted = false
                }
                start = nil
            default: break
            }
        }
        if let s = start {
            out.append(
                Turn(
                    number: out.count + 1, start: s.seq, seconds: max(1, Int(Date().timeIntervalSince(s.at))),
                    cost: nil, interrupted: interrupted && !out.isEmpty, running: running))
        }
        return out
    }
}

/// Lays its children in rows, wrapping when the next one does not fit (the Session card's tags).
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0, x + d.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += d.width + spacing
            line = max(line, d.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + d.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            s.place(
                at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(d.width, bounds.width), height: d.height)
            )
            x += d.width + spacing
            line = max(line, d.height)
        }
    }
}

/// A card's surface: the Look's card fill (bench switch "cardblur" swaps in a plain tint to measure its cost).
private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        if ScrollBench.off.contains("cardblur") {
            content.background(SessionInk.card, in: coreShape(12))
        } else {
            content.coreWell(radius: 12)  // follows the Appearance setting (Look)
        }
    }
}
