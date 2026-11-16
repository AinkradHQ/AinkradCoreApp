import AppKit
import CoreUI
import SwiftUI

// The right column's cards after Session (mockup `Designs/core/session-v3-panel`, approved 2026-11-16).

// MARK: Changes

/// The files the session changed: review progress, a diff bar per file, the diff inline on a click, and Review (⇧⌘R)
/// inside the card. Edits that were refused are listed as such.
struct ChangesCard: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    let entries: [TranscriptEntry]
    let diff: (String) -> [DiffLine]
    @State private var open: String?
    @Environment(\.sessionUI) private var ui
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let store = ReviewStore.shared

    var body: some View {
        let files = model.filesTouched(session.id)
        let denied = Self.denied(entries)
        let reviewed = files.filter { store.state(session.id, $0.path) != .toReview }.count
        let reviewing = ui?.reviewing ?? false
        SideCard(
            id: "changes", title: "Changes", count: files.isEmpty ? nil : "\(files.count) files",
            summary: files.isEmpty ? "Nothing changed yet" : "\(reviewed) of \(files.count) reviewed",
            action: files.isEmpty ? nil : (reviewing ? "Done" : "Review", "⇧⌘R", { ui?.reviewing.toggle() })
        ) {
            if reviewing {
                ReviewPane(model: model, session: session, diff: diff, embedded: true) { ui?.reviewing = false }
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(x: Space.s3)))
            } else if files.isEmpty && denied.isEmpty {
                Text("Nothing changed yet.").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            } else {
                list(files, denied: denied, reviewed: reviewed)
            }
        }
        .animation(Motion.calm(Motion.out(0.22), reduce), value: reviewing)
    }

    private func list(_ files: [FileTouch], denied: [String], reviewed: Int) -> some View {
        let top = max(files.map { $0.added + $0.removed }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            // One segment per file, filled as it is reviewed.
            HStack(spacing: 2) {
                ForEach(files) { f in
                    coreShape(2).fill(segment(store.state(session.id, f.path))).frame(height: 4)
                }
            }
            .animation(Motion.out(0.22), value: reviewed)
            HStack {
                Text("+\(files.map(\.added).reduce(0, +))").foregroundStyle(palette.tone(.run).ink)
                    + Text(" −\(files.map(\.removed).reduce(0, +))").foregroundStyle(SessionInk.bad)
                    + Text(" in \(files.count) files").foregroundStyle(SessionInk.text2)
                Spacer()
                Text("\(reviewed) of \(files.count) reviewed").foregroundStyle(SessionInk.text2)
            }
            .coreFont(size: MacTextSize.meta).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(files) { f in
                    row(f, top: top)
                    if open == f.path {
                        DiffBlock(lines: diff(f.path)).transition(.opacity)
                    }
                }
                ForEach(denied, id: \.self) { path in
                    HStack(spacing: Space.s2) {
                        Image(systemName: "xmark").foregroundStyle(SessionInk.text2).frame(width: Space.s4)
                        Text((path as NSString).lastPathComponent).coreFont(size: 12, design: .monospaced)
                            .foregroundStyle(SessionInk.text2).lineLimit(1)
                        Spacer()
                        Text("Edit denied").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                    }
                    .frame(minHeight: 28).help(path)
                }
            }
        }
    }

    private func row(_ f: FileTouch, top: Int) -> some View {
        Button {
            withAnimation(Motion.calm(Motion.out(0.22), reduce)) { open = open == f.path ? nil : f.path }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: f.created ? "doc.badge.plus" : "doc").foregroundStyle(SessionInk.text2)
                    .frame(width: Space.s4)
                Text(f.name).coreFont(size: 12, design: .monospaced).foregroundStyle(SessionInk.text).lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.s2)
                // The diff bar: added then removed, scaled to the biggest change in the session.
                HStack(spacing: 1) {
                    coreShape(1).fill(palette.tone(.run).ink)
                        .frame(width: 40 * CGFloat(f.added) / CGFloat(top))
                    coreShape(1).fill(SessionInk.bad).frame(width: 40 * CGFloat(f.removed) / CGFloat(top))
                }
                .frame(width: 40, height: 6, alignment: .leading)
                Text(f.created ? "+\(f.added) new" : "+\(f.added) −\(f.removed)").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(SessionInk.text2).monospacedDigit().frame(width: 58, alignment: .trailing)
                let st = store.state(session.id, f.path)
                Image(systemName: st.symbol).coreFont(size: MacTextSize.meta).foregroundStyle(segment(st))
                    .help(st.label)
            }
            .padding(.horizontal, Space.s1).frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .help("\(f.path)\nShow or hide its diff")
    }

    private func segment(_ s: ReviewState) -> Color {
        switch s {
        case .toReview: SessionInk.selected
        case .accepted: SessionInk.ink.opacity(0.75)
        case .revertAsked: GlassInk.amberInk
        }
    }

    /// Paths of edits the session tried that were refused (an approval denied, or the edit failed).
    static func denied(_ entries: [TranscriptEntry]) -> [String] {
        var out: [String] = []
        for e in entries {
            if case .toolEdit(_, _, let path, _, _, false, _) = e.kind, !out.contains(path) { out.append(path) }
        }
        return out
    }
}

// MARK: Sub-agents

/// Each sub-agent with a time bar on one scale (the working one grows live), its state in words; a click shows its brief
/// and report, with Copy Report and Show in Transcript.
struct SubAgentsCard: View {
    let list: [SubAgentInfo]
    @State private var open: String?
    @Environment(\.sessionUI) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let working = list.filter { $0.ok == nil }.count
        SideCard(
            id: "agents", title: "Sub-agents", count: "\(list.count)",
            summary: working > 0 ? "\(working) working" : "all finished"
        ) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let secs = list.map { seconds($0, now: ctx.date) }
                let scale = max(secs.max() ?? 1, 60)
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                        row(a, seconds: secs[i], scale: scale)
                        if open == a.id { report(a) }
                    }
                }
            }
        }
    }

    private func seconds(_ a: SubAgentInfo, now: Date) -> Double {
        a.ms.map { Double($0) / 1000 } ?? max(0, now.timeIntervalSince(a.at))
    }

    private func row(_ a: SubAgentInfo, seconds: Double, scale: Double) -> some View {
        Button {
            withAnimation(Motion.calm(Motion.out(0.22), reduce)) { open = open == a.id ? nil : a.id }
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Image(systemName: Self.symbol(a.type)).foregroundStyle(SessionInk.text2).frame(width: Space.s4)
                    Text(a.task).coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text).lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text(a.ok == nil ? AgentWords.clock(seconds) : "\(coreDecimal(seconds, 1)) s")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
                        // A working agent's timer rolls to each new second.
                        .contentTransition(.numericText(countsDown: false))
                        .animation(Motion.out(0.3), value: Int(seconds))
                }
                HStack(spacing: Space.s2) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            coreShape(2).fill(SessionInk.selected)
                            coreShape(2).fill(a.ok == false ? SessionInk.bad : SessionInk.ink.opacity(0.7))
                                .frame(width: g.size.width * CGFloat(min(seconds / scale, 1)))
                                .animation(Motion.out(0.9), value: seconds)
                            // Working: a soft highlight sweeps along the whole bar, so it reads as busy, not stuck.
                            if a.ok == nil { WorkingSheen() }
                        }
                    }
                    .frame(height: 4)
                    .padding(.leading, Space.s4 + Space.s2)
                    HStack(spacing: Space.s1) {
                        if a.ok == nil {
                            TurningIcon(symbol: "circle.dotted")
                        } else {
                            Image(systemName: a.ok == true ? "checkmark" : "xmark")
                        }
                        Text(a.state.word)
                    }
                    .coreFont(size: MacTextSize.meta)
                    .foregroundStyle(a.ok == false ? SessionInk.bad : SessionInk.text2)
                    .frame(width: 72, alignment: .trailing)
                }
            }
            .padding(.vertical, Space.s1).contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .help(open == a.id ? "Hide its report" : "Show its brief and report")
    }

    private func report(_ a: SubAgentInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Brief").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(SessionInk.text2)
            Text(a.prompt).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text).textSelection(.enabled)
            Text(a.ok == nil ? "Still working" : "Report").coreFont(size: MacTextSize.meta, weight: .semibold)
                .foregroundStyle(SessionInk.text2)
            if let r = a.result {
                Text(r).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text).textSelection(.enabled)
                    .lineLimit(14)
            }
            HStack(spacing: Space.s2) {
                if let r = a.result {
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(r, forType: .string)
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                Button("Show in Transcript") { ui?.jumpTo = a.seq }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
            }
        }
        .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionInk.code, in: coreShape(Radius.control))
        .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1)))
    }

    static func symbol(_ type: String) -> String {
        switch type.lowercased() {
        case "explore": "magnifyingglass"
        case let t where t.contains("review"): "eye"
        default: "person.crop.square"
        }
    }
}

// MARK: Tasks

/// The agent's own to-do list: "4 of 5" with a segmented bar, the current item moving.
struct TasksCard: View {
    let items: [TodoItem]

    var body: some View {
        let done = items.filter { $0.status == .completed }.count
        let now = items.first { $0.status == .inProgress }
        SideCard(
            id: "tasks", title: "Tasks", foldedAtFirst: true, count: "\(done) of \(items.count)",
            summary: now?.text ?? ""
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                        ZStack(alignment: .leading) {
                            coreShape(2).fill(
                                t.status == .completed ? SessionInk.ink.opacity(0.7) : SessionInk.selected)
                            if t.status == .inProgress { CoreWorkingBar() }
                        }
                        .frame(height: 4).clipped()
                    }
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                    Label(
                        t.text,
                        systemImage: t.status == .completed
                            ? "checkmark.square.fill" : t.status == .inProgress ? "square.lefthalf.filled" : "square"
                    )
                    .coreFont(size: MacTextSize.meta)
                    .foregroundStyle(t.status == .completed ? SessionInk.text2 : SessionInk.text)
                    .strikethrough(t.status == .completed)
                }
            }
        }
    }

    /// The newest to-do list in the transcript.
    static func latest(_ entries: [TranscriptEntry]) -> [TodoItem]? {
        for e in entries.reversed() { if case .toolTodos(_, let items) = e.kind, !items.isEmpty { return items } }
        return nil
    }
}

// MARK: Activity

/// What the tools did: calls, failures and tool time, then calls by kind with failures in red, and the last call.
struct ActivityCard: View {
    let entries: [TranscriptEntry]

    var body: some View {
        let steps = entries.compactMap(ToolStep.init)
        let failed = steps.filter { $0.ok == false }.count
        let secs = Double(steps.compactMap(\.ms).reduce(0, +)) / 1000
        let kinds = ToolStep.Kind.allCases.map { k in (k, steps.filter { $0.kind == k }) }.filter { !$0.1.isEmpty }
        let top = max(kinds.map(\.1.count).max() ?? 1, 1)
        SideCard(
            id: "activity", title: "Activity", foldedAtFirst: true, count: "\(steps.count) tools",
            summary: "\(failed) failed · \(coreDecimal(secs, 1)) s"
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s4) {
                    figure("\(steps.count)", "calls")
                    figure("\(failed)", "failed")
                    figure("\(coreDecimal(secs, 1)) s", "tool time")
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(kinds, id: \.0) { k, list in
                        let bad = list.filter { $0.ok == false }.count
                        HStack(spacing: Space.s2) {
                            Text(Self.name(k)).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                                .frame(width: 64, alignment: .leading)
                            GeometryReader { g in
                                HStack(spacing: 1) {
                                    coreShape(2).fill(SessionInk.ink.opacity(0.7))
                                        .frame(width: g.size.width * CGFloat(list.count - bad) / CGFloat(top))
                                    if bad > 0 {
                                        coreShape(2).fill(SessionInk.bad)
                                            .frame(width: g.size.width * CGFloat(bad) / CGFloat(top))
                                    }
                                }
                            }
                            .frame(height: 6)
                            Text("\(list.count)").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                                .monospacedDigit().frame(width: 20, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).foregroundStyle(SessionInk.text)
                .monospacedDigit()
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
        }
    }

    static func name(_ k: ToolStep.Kind) -> String {
        switch k {
        case .read: "Read"
        case .search: "Search"
        case .edit: "Edit"
        case .command: "Commands"
        case .web: "Web"
        case .other: "Other"
        }
    }
}

// MARK: Approvals and connections

/// Every approval with what became of it (the waiting one first), then the connection calls that worked or were refused.
struct ApprovalsCard: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    let entries: [TranscriptEntry]

    var body: some View {
        let now = Date()
        let approvals = (model.transcripts[session.id]?.approvalList ?? []).sorted {
            ($0.status(now: now, sessionOver: session.over) == .pending ? 0 : 1, $1.requestedAt)
                < ($1.status(now: now, sessionOver: session.over) == .pending ? 0 : 1, $0.requestedAt)
        }
        let calls = Self.calls(entries)
        let waiting = approvals.filter { $0.status(now: now, sessionOver: session.over) == .pending }.count
        let refused = calls.filter { $0.ok == false }.count
        if !approvals.isEmpty || !calls.isEmpty {
            SideCard(
                id: "approvals", title: "Approvals", foldedAtFirst: true,
                count: "\(approvals.count + calls.count)",
                summary: [waiting > 0 ? "\(waiting) needs you" : nil, refused > 0 ? "\(refused) refused" : nil]
                    .compactMap { $0 }.joined(separator: " · ")
            ) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(approvals) { r in approval(r, now: now) }
                    ForEach(calls, id: \.seq) { c in call(c) }
                }
            }
        }
    }

    private func approval(_ r: ApprovalRequest, now: Date) -> some View {
        let st = r.status(now: now, sessionOver: session.over)
        let word: String =
            switch st {
            case .pending: "Needs you"
            case .approved: "Allowed"
            case .denied: "Denied"
            case .expired: "Expired"
            }
        return HStack(spacing: Space.s2) {
            Image(systemName: st == .pending ? "hand.raised" : st == .approved ? "checkmark" : "xmark")
                .foregroundStyle(st == .pending ? GlassInk.amberInk : SessionInk.text2).frame(width: Space.s4)
            Text(r.input).coreFont(size: 12, design: .monospaced).foregroundStyle(SessionInk.text).lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.s2)
            Text(word).coreFont(size: MacTextSize.meta)
                .foregroundStyle(st == .pending ? GlassInk.amberInk : SessionInk.text2)
        }
        .frame(minHeight: 26).help("\(r.tool): \(r.input)")
    }

    private func call(_ c: (seq: Int64, tool: String, summary: String, ok: Bool?, why: String)) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: c.ok == false ? "exclamationmark.triangle" : "link").foregroundStyle(
                c.ok == false ? GlassInk.amberInk : SessionInk.text2
            ).frame(width: Space.s4)
            Text(ConnCue.line(c.tool, c.summary, done: c.ok == true)).coreFont(size: MacTextSize.meta)
                .foregroundStyle(SessionInk.text).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Space.s2)
            if c.ok == false {
                Button("Allow…") { model.shell.launcher.entry("connections")?.run() }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small)).help("Allow it in Connections: \(c.why)")
            }
        }
        .frame(minHeight: 26)
    }

    /// The connection calls in the transcript (GitHub, Jira…), with their outcome.
    static func calls(_ entries: [TranscriptEntry]) -> [(
        seq: Int64, tool: String, summary: String, ok: Bool?, why: String
    )] {
        entries.compactMap { e in
            switch e.kind {
            case .toolDone(_, let name, let summary, let ok, _, let output, _) where ConnCue.kind(name) != nil:
                (e.seq, name, summary, ok, output)
            case .toolUse(_, let name, let summary) where ConnCue.kind(name) != nil:
                (e.seq, name, summary, nil, "")
            default: nil
            }
        }
    }
}

// MARK: Usage

/// Context as blocks of the window, or the cost of each turn as bars; Compact (⇧⌘K) puts /compact in the field.
struct UsageCard: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @AppStorage("agents.card.usage.view") private var view = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let used = session.usage?.tokens ?? 0
        let window = ContextWindow.tokens(model: session.model)
        let ctx = ConversationWords.context(used: used, window: window)
        SideCard(
            id: "usage", title: "Usage", count: AgentWords.cost(session.usage?.costMicros), summary: ctx.text,
            action: model.canWrite(session) ? ("Compact", "⇧⌘K", { model.drafts[session.id] = "/compact " }) : nil
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                // A quiet two-way switch: the chosen view on a light fill, never the accent.
                HStack(spacing: 2) {
                    ForEach([(0, "Context"), (1, "Cost per turn")], id: \.0) { i, t in
                        Button(t) { view = i }
                            .buttonStyle(.plain).coreFont(
                                size: MacTextSize.meta, weight: view == i ? .semibold : .regular
                            )
                            .foregroundStyle(view == i ? SessionInk.text : SessionInk.text2)
                            .padding(.horizontal, Space.s2).frame(minHeight: 22)
                            .background(view == i ? SessionInk.selected : .clear, in: coreShape(6))
                    }
                }
                .padding(2).background(SessionInk.row, in: coreShape(8))
                .accessibilityElement(children: .contain).accessibilityLabel("Usage view")
                if view == 0 { context(ctx, used: used, window: window) } else { costs }
            }
            .animation(Motion.calm(Motion.out(0.22), reduce), value: view)
        }
    }

    private func context(_ ctx: (fill: Double, text: String), used: Int64, window: Int64) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(ctx.text).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(SessionInk.text)
                .contentTransition(.numericText())
            // 20 blocks of the window, filled as it is used.
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    coreShape(2).fill(Double(i) < ctx.fill * 20 ? SessionInk.ink.opacity(0.7) : SessionInk.selected)
                        .frame(height: 8)
                }
            }
            .animation(Motion.out(0.26), value: ctx.fill)
            Text(
                "\(AgentWords.tokens(session.usage?.input ?? 0)) in · \(AgentWords.tokens(session.usage?.output ?? 0)) out"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
        }
        .transition(.opacity)
    }

    private var costs: some View {
        let turns = model.turnCosts(session.id)
        let top = max(turns.map(\.cost).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(turns, id: \.turn) { n, c in
                    VStack(spacing: Space.s1) {
                        Text(AgentWords.cost(c) ?? "").coreFont(size: MacTextSize.meta).foregroundStyle(
                            SessionInk.text2
                        )
                        .monospacedDigit()
                        coreShape(3).fill(SessionInk.ink.opacity(0.7))
                            .frame(width: 32, height: max(4, 56 * CGFloat(c) / CGFloat(top)))
                        Text("Turn \(n)").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                    }
                    .help(AgentWords.exactCost(c) ?? "")
                }
                Spacer(minLength: 0)
            }
            PanelRow(label: "This session", value: AgentWords.cost(session.usage?.costMicros) ?? "—")
        }
        .transition(.opacity)
    }
}

/// A soft light band sweeping along a bar every 1.6 s: the working sub-agent's bar (Ahmed, 2026-11-16: "add some
/// animation to the working agents"). It runs under Reduce Motion too, as he asked for this movement; it is the only
/// thing moving in the card, never a pulse.
struct WorkingSheen: View {
    var period = 1.6

    var body: some View {
        if ScrollBench.off.contains("anims") { Color.clear } else { sheen }
    }

    private var sheen: some View {
        GeometryReader { g in
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                let band = max(g.size.width * 0.3, 24)
                LinearGradient(
                    colors: [.clear, SessionInk.text.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + (g.size.width + band) * CGFloat(t))
            }
        }
        .clipShape(coreShape(2))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A symbol turning slowly (one turn in 2.4 s), for "working".
struct TurningIcon: View {
    let symbol: String
    var period = 2.4

    var body: some View {
        TimelineView(.animation(paused: ScrollBench.off.contains("anims"))) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            Image(systemName: symbol).rotationEffect(.degrees(360 * t))
        }
        .accessibilityHidden(true)
    }
}
