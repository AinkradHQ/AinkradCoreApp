import CoreUI
import Observation
import SwiftUI

public enum BellKind: String, Sendable, CaseIterable { case approval, alarm, runner, event }

public struct BellAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let primary: Bool
    public let run: @MainActor () -> Void
    public init(_ label: String, primary: Bool = false, run: @escaping @MainActor () -> Void) {
        self.label = label
        self.primary = primary
        self.run = run
    }
}

/// `Mac.bell.add({ id, kind, title, sub, time, actions })`.
public struct BellItem: Identifiable {
    public let id: String
    public let kind: BellKind
    public let title: String
    public let sub: String?
    public let time: String?
    public let actions: [BellAction]
    public init(
        id: String, kind: BellKind, title: String, sub: String? = nil, time: String? = nil, actions: [BellAction] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sub = sub
        self.time = time
        self.actions = actions
    }
    var needsPerson: Bool { kind == .approval || kind == .alarm }
    var symbol: String {
        switch kind {
        case .approval: "lock.shield"
        case .alarm: "exclamationmark.triangle"
        case .runner: "server.rack"
        case .event: "checkmark"
        }
    }
    var kindLabel: String {
        switch kind {
        case .approval: "Approval"
        case .alarm: "Alarm"
        case .runner: "Runner"
        case .event: "Event"
        }
    }
}

@MainActor @Observable
public final class BellRegistry {
    public private(set) var items: [BellItem] = []
    public init() {}
    public func add(_ item: BellItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
    }
    public func remove(_ id: String) { items.removeAll { $0.id == id } }
    public func removeAll() { items = [] }
    public var count: Int { items.count }
    public var waiting: Int { items.filter(\.needsPerson).count }
}

private enum BellTab: String, CaseIterable, Hashable { case all, approvals, alerts, runners }

/// The groups of `shell-glance.js`: read by who acts, agents first because their approvals expire soonest.
private enum BellGroup: String, CaseIterable {
    case agents, alerts, citadel, approvals, activity
    var title: String {
        switch self {
        case .agents: "AI sessions"
        case .alerts: "Alerts"
        case .citadel: "Citadel"
        case .approvals: "Approvals"
        case .activity: "Activity"
        }
    }
    var hint: String? { self == .agents ? "Need Touch ID" : nil }
    static func of(_ i: BellItem) -> BellGroup {
        if i.id.hasPrefix("agents.") { return .agents }
        if i.id.hasPrefix("citadel-") { return .citadel }
        switch i.kind {
        case .alarm, .runner: return .alerts
        case .approval: return .approvals
        case .event: return .activity
        }
    }
}

/// The bell glance (`shell-glance.js` notes): "Home Core" and what waits on you, four tabs with counts, collapsible groups, cards
/// with their actions on the right, and a Runners tab. It drops from the bell; Reduce Motion fades instead.
struct BellGlance: View {
    @Bindable var shell: ShellModel
    @State private var tab: BellTab = .all
    @State private var shut: Set<BellGroup> = []
    @State private var arrived = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private func inTab(_ i: BellItem) -> Bool {
        switch tab {
        case .all: true
        case .approvals: i.kind == .approval
        case .alerts: i.kind != .approval
        case .runners: false
        }
    }

    private var all: [BellItem] { shell.bell.items }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications").coreFont(size: MacTextSize.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                summary.foregroundStyle(palette.text2)
            }
            CoreSegmented(
                "Notification filter",
                segments: [
                    // One word each, no counts: every group below carries its own count, and a count squeezed "Approvals" to "Approv…".
                    CoreSegment(BellTab.all, "All"), CoreSegment(.approvals, "Approvals"),
                    CoreSegment(.alerts, "Alerts"), CoreSegment(.runners, "Runners"),
                ], selection: $tab, fill: true)
            // As tall as what it holds; past the cap the list scrolls.
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
            }
        }
        .padding(Space.s4)
        .coreFrame(radius: Radius.pane, part: .popups)
        .frame(width: ShellMetrics.bellWidth)
        .coreAnimation(Motion.out(Motion.ui), value: all.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notifications")
        .scaleEffect(arrived || reduce ? 1 : 0.96, anchor: .topTrailing)
        .opacity(arrived ? 1 : 0)
        .offset(y: arrived ? 0 : coreMove(reduce, -10))
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(0.3), value: arrived)
        .onAppear { arrived = true }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if tab == .runners { runners } else { groups }
        }
        .padding(.horizontal, 2)
    }

    private var summary: some View {
        let w = shell.waitingOnYou
        let alerts = shell.alertsOnYou
        let running = shell.home.runningAgents
        return
            (w == 0
            ? Text("Nothing waiting on you")
            : Text("\(w) waiting on you").fontWeight(.semibold).foregroundStyle(palette.text))
            + Text(alerts > 0 ? " · \(alerts) \(alerts == 1 ? "alert" : "alerts")" : "")
            + Text(" · \(running) \(running == 1 ? "AI session" : "AI sessions") running")
    }

    @ViewBuilder private var groups: some View {
        let shown = all.filter(inTab)
        ForEach(Array(BellGroup.allCases.enumerated()), id: \.element) { idx, g in
            let rows = shown.filter { BellGroup.of($0) == g }
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Button {
                        withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) {
                            if shut.contains(g) { shut.remove(g) } else { shut.insert(g) }
                        }
                    } label: {
                        HStack(spacing: Space.s1) {
                            Image(systemName: "chevron.forward").font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(shut.contains(g) ? 0 : 90)).frame(width: 12)
                            Text(g.title).coreFont(size: MacTextSize.body, weight: .semibold)
                                .foregroundStyle(palette.text)
                            CountBadge(rows.count, tone: g == .agents || g == .approvals ? .needsYou : .quiet)
                            if let h = g.hint {
                                Text(h).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(palette.text2).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(shut.contains(g) ? "collapsed" : "expanded")
                    if !shut.contains(g) {
                        ForEach(rows) { item in
                            BellCard(item: item) { $0.run() }
                                .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -Space.s2))))
                        }
                    }
                }
                .rise(arrived, idx + 1, reduce)
            }
        }
        if shown.isEmpty { empty }
    }

    /// Nothing here: the gallery's state card.
    private var empty: some View {
        CoreStateCard(
            symbol: tab == .approvals ? "checkmark.seal" : "bell",
            title: tab == .approvals ? "Nothing needs your approval" : "You're all caught up",
            line: tab == .approvals
                ? "When an AI session asks to do something, it waits here for you."
                : "Approvals and alerts from your Core show up here."
        )
        .transition(.opacity)
    }

    @ViewBuilder private var runners: some View {
        ForEach(shell.home.machines) { m in
            CoreRow(
                m.id, subtitle: !m.online ? "Offline" : m.used == 0 ? "Idle" : "\(m.used) of \(m.slots) running",
                symbol: "server.rack"
            ) {
                StateBadge(m.online ? "Online" : "Offline", tone: m.online ? .run : .queue, symbol: "circle")
            }
        }
    }
}

/// One notification: the gallery's card with an icon tile, the words, and its actions under them.
private struct BellCard: View {
    let item: BellItem
    let perform: (BellAction) -> Void
    @Environment(\.corePalette) private var palette

    /// Needs you is amber, an alarm red, the rest quiet: the colour is on the tile only.
    private var hue: Color {
        switch item.kind {
        case .approval: GlassInk.amber
        case .alarm: GlassInk.red
        case .runner, .event: GlassInk.slate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                IconTile(item.symbol, hue: hue, size: MacSize.controlLg)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(item.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.s2)
                        if let time = item.time {
                            Text(time).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        }
                    }
                    if let sub = item.sub {
                        Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(2)
                    }
                }
            }
            if !item.actions.isEmpty {
                HStack(spacing: Space.s2) {
                    Spacer(minLength: 0)
                    ForEach(item.actions) { a in
                        Button(a.label) { perform(a) }
                            .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary, size: .small))
                    }
                }
            }
        }
        .padding(Space.s3)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kindLabel): \(item.title)")
    }
}
