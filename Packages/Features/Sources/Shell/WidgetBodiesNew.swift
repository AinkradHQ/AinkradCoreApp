import CoreUI
import SwiftUI

// The widgets added in 0.10 (E4-2): Approvals, Terminals, Projects and AI usage. Each size is its own layout, as in the
// 05-home mockup: small a glance, medium a list, wide a row of cards or a chart, large the detail. Data the Core does not
// report is left out, never shown as filler.

/// Approvals: allow or refuse a request without opening anything.
struct ApprovalsBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let items = shell.bell.items.filter { $0.kind == .approval }
        let badge: StateBadge? = items.isEmpty ? nil : StateBadge("\(items.count)", tone: .run, symbol: "hand.raised")
        VStack(alignment: .leading, spacing: Space.s2) {
            if items.isEmpty {
                WHead("checkmark.shield", "Approvals")
                WEmpty(symbol: "checkmark.circle", text: "Nothing to allow")
            } else {
                switch size {
                case .s:
                    WHead("checkmark.shield", "Approvals")
                    WFigure(value: Double(items.count), caption: "to allow")
                    Spacer(minLength: 0)
                    if let t = items.first?.time { WCaption("Oldest: \(t)") }
                case .m:
                    WHead("checkmark.shield", "Approvals") { badge }
                    if let first = items.first { ApprovalCard(item: first, stacked: false) }
                    if items.count > 1 { WCaption("\(items.count - 1) more waiting") }
                case .w:
                    WHead("checkmark.shield", "Approvals") { WCaption("\(items.count) waiting") }
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(items.prefix(2)) { ApprovalCard(item: $0, stacked: false) }
                    }
                case .l:
                    WHead("checkmark.shield", "Approvals") { WCaption("\(items.count) waiting") }
                    ForEach(items.prefix(3)) { ApprovalCard(item: $0, stacked: true) }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: items.map(\.id))
    }
}

/// One request: what it asks, who asks, and its Allow and Not now buttons (the item's own actions).
private struct ApprovalCard: View {
    let item: BellItem
    /// Buttons under the text (large) or beside it (medium and wide).
    let stacked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Space.s2) {
                    text
                    WActions(item: item)
                }
            } else {
                HStack(alignment: .center, spacing: Space.s3) {
                    text
                    Spacer(minLength: Space.s2)
                    WActions(item: item)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.row))
        .newRow(reduce)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(stacked ? 2 : 1)
            if let s = [item.sub, item.time].compactMap({ $0 }).joined(separator: " · ") as String?, !s.isEmpty {
                WCaption(s)
            }
        }
    }
}

/// A few lines of terminal text in a well, in the terminal's own monospaced face.
private struct WMono: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: MacTextSize.meta, design: .monospaced)).lineLimit(1)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// "Sandbox" is the Core's runner; "This Mac" is the runner inside the app. Always a word, never colour alone.
private struct PlaceTag: View {
    let fact: HomeSnapshot.TerminalFact
    var body: some View {
        Text(fact.place).coreFont(size: MacTextSize.meta, weight: .medium)
            .foregroundStyle(fact.onThisMac ? GlassInk.blue : GlassInk.secondary).lineLimit(1)
    }
}

/// Terminals: the list, with a live look at the last lines of the ones this Mac has open.
struct TerminalsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let ts = home.terminals
        VStack(alignment: .leading, spacing: Space.s2) {
            if ts.isEmpty {
                WHead("terminal", "Terminals")
                WEmpty(symbol: "terminal", text: "No terminals open")
            } else {
                switch size {
                case .s:
                    WHead("terminal", "Terminals")
                    WFigure(value: Double(ts.count), caption: "open")
                    Spacer(minLength: 0)
                    let mac = ts.filter(\.onThisMac).count
                    if mac > 0 { WCaption("\(mac) on this Mac") }
                case .m:
                    WHead("terminal", "Terminals")
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(ts.prefix(2)) { t in
                            HStack(spacing: Space.s2) {
                                Text(t.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                PlaceTag(fact: t)
                                Spacer(minLength: Space.s2)
                                if let l = t.lines.last {
                                    Text(l).font(.system(size: MacTextSize.meta, design: .monospaced))
                                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                                }
                            }
                            .foregroundStyle(GlassInk.primary)
                            .accessibilityElement(children: .combine).newRow(reduce)
                        }
                    }
                case .w:
                    WHead("terminal", "Terminals") { WCaption("\(ts.count) open") }
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(ts.prefix(3)) { t in thumb(t, lines: 3) }
                    }
                case .l:
                    WHead("terminal", "Terminals") { WCaption("\(ts.count) open") }
                    ForEach(groups(ts), id: \.0) { place, list in
                        WCaption(place)
                        ForEach(list.prefix(2)) { t in thumb(t, lines: 2) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: ts.map(\.id))
    }

    /// By place, this Mac last.
    private func groups(_ ts: [HomeSnapshot.TerminalFact]) -> [(String, [HomeSnapshot.TerminalFact])] {
        let by = Dictionary(grouping: ts, by: \.place)
        return by.keys.sorted { ($0 == "This Mac" ? 1 : 0, $0) < ($1 == "This Mac" ? 1 : 0, $1) }.map {
            ($0, by[$0] ?? [])
        }
    }

    private func thumb(_ t: HomeSnapshot.TerminalFact, lines: Int) -> some View {
        WSub {
            HStack(spacing: Space.s2) {
                Text(t.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s1)
                PlaceTag(fact: t)
            }
            .foregroundStyle(GlassInk.primary)
            if t.lines.isEmpty {
                WCaption("Open it to see its screen here")
            } else {
                WMono(lines: Array(t.lines.suffix(lines)))
            }
        }
        .newRow(reduce)
    }
}

/// Projects: what is open and which AI sessions work in it.
struct ProjectsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var ordered: [HomeSnapshot.ProjectFact] {
        home.projects.sorted {
            ($0.sessions, $0.updatedAt ?? .distantPast) > ($1.sessions, $1.updatedAt ?? .distantPast)
        }
    }

    private func sessions(_ n: Int) -> String {
        n == 0 ? "No sessions running" : n == 1 ? "1 session running" : "\(n) sessions running"
    }

    var body: some View {
        let ps = ordered
        VStack(alignment: .leading, spacing: Space.s2) {
            if ps.isEmpty {
                WHead("folder", "Projects")
                WEmpty(symbol: "folder", text: "No projects yet")
            } else {
                switch size {
                case .s:
                    WHead("folder", "Projects")
                    if let p = ps.first {
                        Spacer(minLength: 0)
                        Text(p.name).coreFont(size: MacTextSize.title, weight: .semibold)
                            .foregroundStyle(GlassInk.primary).lineLimit(2)
                        WCaption(sessions(p.sessions))
                    }
                case .m:
                    WHead("folder", "Projects")
                    VStack(spacing: Space.s3) {
                        ForEach(ps.prefix(3)) { p in
                            HStack(spacing: Space.s2) {
                                Text(p.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                Spacer(minLength: Space.s2)
                                WCaption(
                                    p.sessions == 0 ? "Idle" : p.sessions == 1 ? "1 session" : "\(p.sessions) sessions")
                            }
                            .foregroundStyle(GlassInk.primary).accessibilityElement(children: .combine)
                        }
                    }
                case .w:
                    WHead("folder", "Projects")
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(ps.prefix(3)) { p in
                            WSub {
                                Text(p.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                    .foregroundStyle(GlassInk.primary)
                                WCaption(sessions(p.sessions))
                            }
                        }
                    }
                case .l:
                    WHead("folder", "Projects")
                    VStack(spacing: Space.s3) {
                        ForEach(ps.prefix(5)) { p in
                            HStack(spacing: Space.s3) {
                                Image(systemName: "folder")
                                    .foregroundStyle(p.sessions > 0 ? GlassInk.blue : GlassInk.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                    WCaption(detail(p))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(GlassInk.primary).accessibilityElement(children: .combine)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func detail(_ p: HomeSnapshot.ProjectFact) -> String {
        let s = p.sessions == 0 ? "Idle" : p.sessions == 1 ? "1 session" : "\(p.sessions) sessions"
        guard let at = p.updatedAt else { return s }
        return "\(s) · changed \(at.formatted(.relative(presentation: .named)))"
    }
}

/// AI usage: how much of each plan is used (the tightest limit of each provider's accounts).
struct AIUsageBody: View {
    let home: HomeSnapshot
    let size: WidgetSize

    /// "anthropic" reads "Claude"; any other provider is its own name with a capital.
    static func name(_ provider: String) -> String {
        switch provider.lowercased() {
        case "anthropic", "claude": "Claude"
        case "openai", "codex": "Codex"
        case "google", "gemini": "Gemini"
        default: provider.prefix(1).uppercased() + provider.dropFirst()
        }
    }

    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    var body: some View {
        let us = home.usage.sorted { $0.share > $1.share }
        let top = us.first?.share ?? 0
        VStack(alignment: .leading, spacing: Space.s2) {
            if us.isEmpty {
                WHead("chart.bar", "AI usage")
                WEmpty(symbol: "chart.bar", text: "No plan limits reported yet")
            } else {
                switch size {
                case .s:
                    WHead("chart.bar", "AI usage")
                    WFigure(value: top * 100, format: { "\(Int($0))%" }, caption: "of the tightest plan")
                    Spacer(minLength: 0)
                    CoreMeter(top, low: top > 0.8, label: "Tightest plan used")
                case .m:
                    WHead("chart.bar", "AI usage")
                    rows(us.prefix(3))
                case .w:
                    WHead("chart.bar", "AI usage")
                    HStack(alignment: .top, spacing: Space.s6) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            WFigure(
                                value: top * 100, format: { "\(Int($0))%" }, caption: "of the tightest plan", size: 32)
                            if let r = soonest(us) {
                                WCaption("Resets \(r.formatted(.relative(presentation: .named)))")
                            }
                        }
                        .frame(width: 190, alignment: .leading)
                        if home.spendByDay.contains(where: { $0 > 0 }) {
                            // The chart is what the AI sessions cost each day (the Core's cost events, newest 100).
                            VStack(alignment: .leading, spacing: Space.s1) {
                                WColumns(values: home.spendByDay)
                                HStack {
                                    WCaption("30 days ago")
                                    Spacer(minLength: 0)
                                    WCaption("Spend per day, today")
                                }
                            }
                        } else {
                            rows(us.prefix(3))
                        }
                    }
                case .l:
                    WHead("chart.bar", "AI usage")
                    WFigure(value: top * 100, format: { "\(Int($0))%" }, caption: "of the tightest plan", size: 32)
                    if let r = soonest(us) { WCaption("Resets \(r.formatted(.relative(presentation: .named)))") }
                    rows(us.prefix(6))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func soonest(_ us: [HomeSnapshot.UsageFact]) -> Date? {
        us.compactMap(\.resetsAt).filter { $0 > Date() }.min()
    }

    private func rows(_ us: ArraySlice<HomeSnapshot.UsageFact>) -> some View {
        VStack(spacing: Space.s3) {
            ForEach(us) { u in
                WBarRow(label: Self.name(u.provider), value: pct(u.share), fill: u.share, low: u.share > 0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
