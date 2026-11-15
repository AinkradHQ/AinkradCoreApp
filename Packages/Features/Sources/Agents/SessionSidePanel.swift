import CoreUI
import SwiftUI

/// The conversation's side panel (windows of 1300 pt and up, N42), three cards (Ahmed, 2026-11-15: organised): the session
/// (where it runs and its tools), files touched with their diffs, and usage (context and cost). One row style throughout. Under that width the same facts live in the Details strip.
struct SessionSidePanel: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    var find: (() -> Void)?
    @State private var openFile: String?
    @Environment(\.corePalette) private var palette
    @Environment(\.sessionUI) private var ui
    private var reviewing: Bool { ui?.reviewing ?? false }

    var body: some View {
        let files = model.filesTouched(session.id)
        if reviewing {
            ReviewPane(model: model, session: session, diff: diff) { ui?.reviewing = false }
                .task(id: session.id) { await model.followRoute(session.id) }
        } else {
            cards(files)
        }
    }

    private func cards(_ files: [FileTouch]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                SessionActions(model: model, session: session, find: find, stacked: true, facts: facts)
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .coreWell()
                section(
                    "Files touched", symbol: "doc", count: files.count,
                    review: files.isEmpty ? nil : { ui?.reviewing = true }
                ) {
                    if files.isEmpty {
                        Text("Nothing changed yet.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    } else {
                        ForEach(files) { f in
                            Button {
                                openFile = openFile == f.path ? nil : f.path
                            } label: {
                                HStack(spacing: Space.s2) {
                                    Text(f.name).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: Space.s2)
                                    Text("+\(f.added)").foregroundStyle(palette.tone(.run).ink)
                                    Text(f.created ? "new" : "−\(f.removed)").foregroundStyle(
                                        palette.tone(f.created ? .run : .fail).ink)
                                }
                                .coreFont(size: MacTextSize.meta).monospacedDigit()
                                .padding(.vertical, Space.s1).contentShape(Rectangle())
                            }
                            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
                            .help("\(f.path)\nShow or hide its diff")
                            if openFile == f.path { DiffBlock(lines: diff(f.path)).transition(.opacity) }
                        }
                    }
                }
                section(
                    "Usage", symbol: "gauge.with.dots.needle.50percent",
                    action: model.canWrite(session) ? ("/compact", { model.drafts[session.id] = "/compact " }) : nil
                ) {
                    let ctx = ConversationWords.context(
                        used: session.usage?.tokens ?? 0, window: ContextWindow.tokens(model: session.model))
                    PanelRow(label: "Context", value: ctx.text)
                    CoreMeter(ctx.fill, label: "Context used")
                    let turns = model.turnCosts(session.id)
                    let top = max(turns.map(\.cost).max() ?? 1, 1)
                    ForEach(turns, id: \.turn) { n, c in
                        HStack(spacing: Space.s2) {
                            Text("Turn \(n)").foregroundStyle(palette.text2).frame(
                                width: Space.s8 + Space.s4, alignment: .leading)
                            CoreMeter(Double(c) / Double(top), label: "Turn \(n) cost")
                            Text(AgentWords.cost(c) ?? "").monospacedDigit()
                                .frame(width: Space.s8 * 2, alignment: .trailing)
                                .help(AgentWords.exactCost(c) ?? "")
                        }
                        .coreFont(size: MacTextSize.meta)
                    }
                    PanelRow(label: "Cost this session", value: AgentWords.cost(session.usage?.costMicros) ?? "—")
                        .help(AgentWords.exactCost(session.usage?.costMicros) ?? "")
                }
            }
            .foregroundStyle(palette.text)
            .padding(.vertical, Space.s2)
        }
        .scrollIndicators(.never)
        .task(id: session.id) { await model.followRoute(session.id) }
    }

    /// Where the session runs: the Session card's rows.
    private var facts: [(String, String)] {
        var f: [(String, String)] = [("Runner", model.runnerName(session.runner))]
        if let a = session.route?.account { f.append(("Account", model.accountNames[a] ?? "an account")) }
        f.append(("Tool", AgentWords.toolName(session.harness) + (session.model.map { " · \($0)" } ?? "")))
        f.append(("Folder", session.project ?? "Fresh folder"))
        if let b = session.branch { f.append(("Branch", b)) }
        return f
    }

    private func diff(_ path: String) -> [DiffLine] {
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

    /// One card of the side panel (Ahmed, 2026-11-15: separate cards, as on the landing page, in our components): its
    /// symbol and title, an optional count and one quiet action, then its content.
    private func section<C: View>(
        _ title: String, symbol: String, count: Int = 0, action: (String, () -> Void)? = nil,
        review: (() -> Void)? = nil, @ViewBuilder _ c: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    .frame(width: Space.s4).accessibilityHidden(true)
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(.isHeader)
                if count > 0 { CountBadge(count, tone: .quiet) }
                Spacer(minLength: 0)
                if let review {
                    Button("Review", action: review).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Review the changes (⇧⌘R)").keyHint(.review)
                }
                if let action {
                    Button(action.0, action: action.1).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Put \(action.0) in the message field (⇧⌘K)").keyHint(.compact)
                }
            }
            c()
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}
