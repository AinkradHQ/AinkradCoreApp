import CoreUI
import SwiftUI

/// What the tools did: calls, failures and tool time, then calls by kind with failures in red. With more than one
/// turn, a switch shows one turn at a time ("Turn 3") or all of them.
struct ActivityCard: View {
    let entries: [TranscriptEntry]
    /// The turn shown, from 1; nil is every turn.
    @State private var turn: Int?

    var body: some View {
        let turns = Self.turns(entries)
        let shown = turn.flatMap { $0 <= turns.count ? turns[$0 - 1] : nil } ?? entries
        let steps = shown.compactMap(ToolStep.init)
        let failed = steps.filter { $0.ok == false }.count
        let secs = Double(steps.compactMap(\.ms).reduce(0, +)) / 1000
        let kinds = ToolStep.Kind.allCases.map { k in (k, steps.filter { $0.kind == k }) }.filter { !$0.1.isEmpty }
        let top = max(kinds.map(\.1.count).max() ?? 1, 1)
        SideCard(
            id: "activity", title: "Activity", foldedAtFirst: true, count: "\(steps.count) tools",
            summary: "\(failed) failed · \(coreDecimal(secs, 1)) s"
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if turns.count > 1 {
                    CoreSelect(nil, selection: $turn, options: options(turns))
                        .help("Show the tools of one turn, or of all of them")
                }
                HStack(spacing: Space.s4) {
                    figure("\(steps.count)", "calls")
                    figure("\(failed)", "failed")
                    figure("\(coreDecimal(secs, 1)) s", "tool time")
                }
                if let t = turn.flatMap({ Self.tokens(turns[safe: $0 - 1] ?? []) }) {
                    Text("\(AgentWords.tokens(t)) tokens this turn")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
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

    private func options(_ turns: [[TranscriptEntry]]) -> [CoreSelectOption<Int?>] {
        let running = turns.last.map { !$0.contains(where: Self.ends) } ?? false
        return [CoreSelectOption(nil, "All turns")]
            + turns.indices.map { i in
                CoreSelectOption(i + 1, "Turn \(i + 1)" + (running && i == turns.count - 1 ? " · running" : ""))
            }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).foregroundStyle(SessionInk.text)
                .monospacedDigit()
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
        }
    }

    nonisolated static func ends(_ e: TranscriptEntry) -> Bool {
        if case .turnEnded = e.kind { true } else { false }
    }

    /// The transcript cut into turns, each ending at its "turn ended" entry. A running turn (tools after the last
    /// end) is the last one; an empty tail is not a turn.
    nonisolated static func turns(_ entries: [TranscriptEntry]) -> [[TranscriptEntry]] {
        var out: [[TranscriptEntry]] = []
        var now: [TranscriptEntry] = []
        for e in entries {
            now.append(e)
            if ends(e) {
                out.append(now)
                now = []
            }
        }
        if now.contains(where: { ToolStep($0) != nil }) { out.append(now) }
        return out
    }

    /// A finished turn's tokens (in and out), from the usage that closes it; nil while it runs.
    nonisolated static func tokens(_ turn: [TranscriptEntry]) -> Int64? {
        for e in turn.reversed() { if case .turnEnded(_, let t) = e.kind { return t } }
        return nil
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

extension Array {
    fileprivate subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
