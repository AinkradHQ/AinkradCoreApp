import CoreUI
import SwiftUI

/// The conversation's side panel (windows of 1300 pt and up, N42): files touched with their diffs, folder and branch, context
/// as a bar, cost per turn, the runner and the account. Under that width the same facts live in the Details strip.
struct SessionSidePanel: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @State private var openFile: String?
    /// The context window the bar is drawn against. ponytail: one size for every model until the Core reports the real one.
    static let contextTokens: Int64 = 200_000

    var body: some View {
        let files = model.filesTouched(session.id)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                card("doc", "Files touched", badge: files.isEmpty ? nil : "\(files.count)") {
                    if files.isEmpty {
                        Text("Nothing changed yet.").foregroundStyle(GlassInk.secondary)
                    } else {
                        ForEach(files) { f in
                            Button {
                                openFile = openFile == f.path ? nil : f.path
                            } label: {
                                HStack(spacing: Space.s2) {
                                    Text(f.name).coreFont(size: MacTextSize.body, design: .monospaced).lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: Space.s2)
                                    Text("+\(f.added)").foregroundStyle(GlassInk.green)
                                    Text(f.created ? "new" : "−\(f.removed)").foregroundStyle(
                                        f.created ? GlassInk.green : GlassInk.red)
                                }
                                .coreFont(size: MacTextSize.meta).monospacedDigit().contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help(f.path)
                            if openFile == f.path { DiffBlock(lines: diff(f.path)) }
                        }
                        Text("Click a file to see its diff").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
                card("folder", "Folder and branch") {
                    row("Project", session.project ?? "Fresh folder")
                    if let b = session.branch { row("Branch", b, mono: true) }
                    if !files.isEmpty { row("Status", "\(files.count) file\(files.count == 1 ? "" : "s") changed") }
                }
                card("chart.bar", "Context") {
                    let used = session.usage?.tokens ?? 0
                    ProgressBar(value: min(1, Double(used) / Double(Self.contextTokens)))
                    Text("\(AgentWords.tokens(used)) of \(AgentWords.tokens(Self.contextTokens)) tokens used")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                card("dollarsign", "Cost") {
                    let turns = model.turnCosts(session.id)
                    let top = max(turns.max() ?? 1, 1)
                    ForEach(Array(turns.enumerated()), id: \.offset) { i, c in
                        HStack(spacing: Space.s2) {
                            Text("Turn \(i + 1)").foregroundStyle(GlassInk.secondary).frame(
                                width: 48, alignment: .leading)
                            ProgressBar(value: Double(c) / Double(top))
                            Text(AgentWords.cost(c) ?? "").monospacedDigit().frame(width: 64, alignment: .trailing)
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
            Text(k).foregroundStyle(GlassInk.secondary).frame(width: 54, alignment: .leading)
            Text(v).coreFont(size: MacTextSize.body, design: mono ? .monospaced : .default).lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .coreFont(size: MacTextSize.meta)
    }

    private func card<C: View>(_ symbol: String, _ title: String, badge: String? = nil, @ViewBuilder _ c: () -> C)
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).foregroundStyle(GlassInk.secondary)
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                if let badge {
                    Text(badge).coreFont(size: MacTextSize.meta).padding(.horizontal, Space.s2)
                        .background(GlassInk.well, in: coreShape(4))
                }
            }
            c()
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }
}

/// A flat progress bar, rounded rectangle ends (no rings).
struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(3).fill(GlassInk.track)
                coreShape(3).fill(GlassInk.blue).frame(width: max(3, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
