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

private enum BellTab: String, CaseIterable, Hashable { case all, approvals, alerts }

/// The bell glance: header with what waits on you, tabs, items grouped by who must act.
struct BellGlance: View {
    @Bindable var shell: ShellModel
    @State private var tab: BellTab = .all
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var items: [BellItem] {
        shell.bell.items.filter {
            switch tab {
            case .all: true
            case .approvals: $0.kind == .approval
            case .alerts: $0.kind == .alarm || $0.kind == .runner
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Home Core").font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(
                    .isHeader)
                Text(summary).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
            }
            CoreSegmented(
                "Notification filter",
                segments: [
                    CoreSegment(BellTab.all, "All \(shell.bell.count)"),
                    CoreSegment(.approvals, "Approvals \(shell.bell.items.filter { $0.kind == .approval }.count)"),
                    CoreSegment(
                        .alerts, "Alerts \(shell.bell.items.filter { $0.kind == .alarm || $0.kind == .runner }.count)"),
                ], selection: $tab)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(items) { item in
                        BellCard(item: item) { act in
                            act.run()
                        }
                        .transition(.opacity.combined(with: .offset(y: coreMove(reduce, -Space.s2))))
                    }
                    if items.isEmpty {
                        Text(tab == .approvals ? "Nothing is waiting for your approval." : "No notifications.")
                            .foregroundStyle(palette.text2).padding(Space.s3)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(width: ShellMetrics.bellWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .coreAnimation(Motion.out(Motion.ui), value: shell.bell.items.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notifications")
        .transition(.opacity.combined(with: .offset(x: coreMove(reduce, Space.s6))))
    }

    private var summary: String {
        let w = shell.bell.waiting
        let waiting = w == 0 ? "Nothing waiting on you" : "\(w) waiting on you"
        let running = shell.home.runningAgents
        return "\(waiting) · \(running) \(running == 1 ? "agent" : "agents") running"
    }
}

private struct BellCard: View {
    let item: BellItem
    let perform: (BellAction) -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: item.symbol).font(.system(size: MacTextSize.body))
                .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                .background(palette.uDim, in: coreShape(Radius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Spacer(minLength: Space.s2)
                    if let time = item.time {
                        Text(time).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    }
                }
                if let sub = item.sub { Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2) }
                if !item.actions.isEmpty {
                    HStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        ForEach(item.actions) { a in
                            Button(a.label) { perform(a) }
                                .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary, size: .small))
                        }
                    }
                    .padding(.top, Space.s1)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kindLabel): \(item.title)")
    }
}
