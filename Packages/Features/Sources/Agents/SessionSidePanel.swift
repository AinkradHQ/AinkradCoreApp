import CoreUI
import SwiftUI

/// The conversation's side panel (windows of 1300 pt and up, N42): files touched with their diffs, folder and branch, context
/// as a bar, cost per turn, the runner and the account. Under that width the same facts live in the Details strip.
struct SessionSidePanel: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @State private var openFile: String?
    @Environment(\.corePalette) private var palette

    var body: some View {
        let files = model.filesTouched(session.id)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                card("doc", "Files touched", count: files.count) {
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
                            .buttonStyle(ToolRowStyle()).help("\(f.path)\nShow or hide its diff")
                            if openFile == f.path { DiffBlock(lines: diff(f.path)).transition(.opacity) }
                        }
                    }
                }
                card("folder", "Folder and branch") {
                    row("Project", session.project ?? "Fresh folder")
                    if let b = session.branch { row("Branch", b, mono: true) }
                }
                card(
                    "chart.bar", "Context",
                    action: model.canWrite(session) ? ("/compact", { model.drafts[session.id] = "/compact " }) : nil
                ) {
                    let used = session.usage?.tokens ?? 0
                    let window = ContextWindow.tokens(model: session.model)
                    CoreMeter(min(1, Double(used) / Double(window)), label: "Context used")
                    Text("\(AgentWords.tokens(used)) of \(AgentWords.tokens(window)) tokens")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                }
                card("dollarsign", "Cost") {
                    let turns = model.turnCosts(session.id)
                    let top = max(turns.max() ?? 1, 1)
                    ForEach(Array(turns.enumerated()), id: \.offset) { i, c in
                        HStack(spacing: Space.s2) {
                            Text("Turn \(i + 1)").foregroundStyle(palette.text2).frame(
                                width: Space.s8 + Space.s4, alignment: .leading)
                            CoreMeter(Double(c) / Double(top), label: "Turn \(i + 1) cost")
                            Text(AgentWords.cost(c) ?? "").monospacedDigit()
                                .frame(width: Space.s8 * 2, alignment: .trailing)
                                .help(AgentWords.exactCost(c) ?? "")
                        }
                        .coreFont(size: MacTextSize.meta)
                    }
                    HStack {
                        Text("This session").fontWeight(.semibold)
                        Spacer()
                        Text(AgentWords.cost(session.usage?.costMicros) ?? "—").fontWeight(.semibold).monospacedDigit()
                            .help(AgentWords.exactCost(session.usage?.costMicros) ?? "")
                    }
                    .coreFont(size: MacTextSize.body)
                }
                card("server.rack", "Runner and account") {
                    row("Runner", model.runnerName(session.runner))
                    if let a = session.route?.account { row("Account", model.accountNames[a] ?? "an account") }
                    row("Tool", AgentWords.toolName(session.harness) + (session.model.map { " · \($0)" } ?? ""))
                }
            }
            .padding(.vertical, Space.s2)
        }
        .scrollIndicators(.never)
        .task(id: session.id) { await model.followRoute(session.id) }
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

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(k).foregroundStyle(palette.text2).frame(width: Space.s8 + Space.s6, alignment: .leading)
            Text(v).coreFont(size: MacTextSize.body, design: mono ? .monospaced : .default).lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .coreFont(size: MacTextSize.meta)
    }

    /// One inner card on the pane's glass: a plain well, a title row with an optional count and one quiet action.
    private func card<C: View>(
        _ symbol: String, _ title: String, count: Int = 0, action: (String, () -> Void)? = nil,
        @ViewBuilder _ c: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).foregroundStyle(palette.text2).accessibilityHidden(true)
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(.isHeader)
                CountBadge(count, tone: .quiet)
                Spacer(minLength: 0)
                if let action {
                    Button(action.0, action: action.1).buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .help("Put \(action.0) in the message field")
                }
            }
            c()
        }
        .foregroundStyle(palette.text)
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }
}
