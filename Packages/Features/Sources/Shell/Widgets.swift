import CoreUI
import SwiftUI

/// A Home widget: panel surface at a grid size, content by kind, a remove button while editing.
struct WidgetCard: View {
    let kind: WidgetKind
    @Bindable var shell: ShellModel
    let size: (cols: Int, rows: Int)
    @Environment(\.corePalette) private var palette

    var body: some View {
        let cell = ShellMetrics.widgetCell
        let gap = ShellMetrics.widgetGap
        content
            .padding(Space.s4)
            .frame(
                width: cell * CGFloat(size.cols) + gap * CGFloat(size.cols - 1),
                height: cell * CGFloat(size.rows) + gap * CGFloat(size.rows - 1), alignment: .topLeading
            )
            .corePanel(radius: Radius.panel, padding: 0)
            .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if shell.editingWidgets {
                    CoreIconButton(symbol: "xmark", label: "Remove \(kind.title)") { shell.removeWidget(kind) }
                        .padding(Space.s2)
                        .transition(.opacity)
                }
            }
            .coreAnimation(Motion.out(Motion.ui), value: shell.editingWidgets)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(kind.title)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .today: TodayWidget(shell: shell)
        case .clock: ClockWidget()
        case .spend: SpendWidget(home: shell.home)
        case .quick: QuickWidget(shell: shell)
        case .machines: MachinesWidget(home: shell.home)
        case .board: BoardWidget(board: shell.home.board)
        case .events: EventsWidget(home: shell.home)
        }
    }
}

private struct WidgetTitle: View {
    let title: String
    var sub: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let sub { Text(sub).foregroundStyle(palette.text2).font(.system(size: MacTextSize.body)) }
        }
    }
}

private struct Meter: View {
    let value: Double
    @Environment(\.corePalette) private var palette
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(Space.s1).fill(palette.track)
                coreShape(Space.s1).fill(palette.primary).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}

private struct SlotBar: View {
    let used: Int
    let slots: Int
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s1 / 2) {
            ForEach(0..<max(slots, 0), id: \.self) { i in
                coreShape(Space.s1).fill(i < used ? palette.primary : palette.track)
                    .frame(width: Space.s4, height: Space.s1)
            }
        }
        .accessibilityHidden(true)
    }
}

struct TodayWidget: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let h = shell.home
        VStack(alignment: .leading, spacing: Space.s3) {
            WidgetTitle(
                title: "Today", sub: "\(h.coreName) · \(h.machinesOnline) of \(h.machines.count) machines online")
            if let first = shell.bell.items.first(where: \.needsPerson) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Needs you").font(.system(size: MacTextSize.body, weight: .semibold))
                    Button {
                        shell.bellOpen = true
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(first.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                            Text("\(shell.bell.waiting) waiting on you · Review").font(.system(size: MacTextSize.meta))
                                .foregroundStyle(palette.text2)
                        }
                        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.glassCard, in: coreShape(Radius.row))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !h.running.isEmpty {
                Text("Running").font(.system(size: MacTextSize.body, weight: .semibold))
                ForEach(h.running) { r in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(palette.tone(.run).ink).accessibilityHidden(true)
                        Text(r.tool).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text(r.name).foregroundStyle(palette.text2).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(r.minutes) min").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    }
                    .font(.system(size: MacTextSize.body))
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Machines").font(.system(size: MacTextSize.body, weight: .semibold))
            ForEach(h.machines) { m in
                HStack {
                    Text(m.id).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(m.online ? (m.used == 0 ? "Idle" : "\(m.used) of \(m.slots) slots") : "Offline")
                        .foregroundStyle(palette.text2)
                    Spacer(minLength: 0)
                    SlotBar(used: m.used, slots: m.slots)
                }
                .font(.system(size: MacTextSize.body))
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ClockWidget: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: Space.s1) {
                Spacer(minLength: 0)
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: MacTextSize.large * 1.4, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(ctx.date, format: .dateTime.weekday(.wide)).foregroundStyle(palette.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct SpendWidget: View {
    let home: HomeSnapshot
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Spacer(minLength: 0)
            Text(home.spendToday, format: .currency(code: "USD")).font(
                .system(size: MacTextSize.large * 1.4, weight: .semibold))
            Text("today").foregroundStyle(palette.text2)
            Meter(value: home.monthTokensUsed)
            Text("\(Int(home.monthTokensUsed * 100))% of month tokens").font(.system(size: MacTextSize.meta))
                .foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct QuickWidget: View {
    @Bindable var shell: ShellModel
    var body: some View {
        let cols = [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible(), spacing: Space.s2)]
        LazyVGrid(columns: cols, spacing: Space.s2) {
            quick("New session", "play", id: "new-session")
            quick("Terminal", "terminal", id: "new-terminal")
            quick("Add device", "plus", id: "add-device")
            Button {
                shell.toggleLauncher()
            } label: {
                Label("Launcher", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(CoreButtonStyle(.prominent))
        }
    }
    private func quick(_ title: String, _ symbol: String, id: String) -> some View {
        Button {
            if let e = shell.launcher.entry(id) {
                e.run()
            } else {
                shell.showToast("\(title) arrives with its feature module.")
            }
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(CoreButtonStyle(.secondary))
    }
}

struct MachinesWidget: View {
    let home: HomeSnapshot
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            WidgetTitle(title: "Machines", sub: "\(home.machinesOnline) of \(home.machines.count) online")
            ForEach(home.machines) { m in
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack {
                        Text(m.id).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text(m.os).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        Spacer(minLength: 0)
                        Text(m.online ? "\(m.used) of \(m.slots) slots" : "Offline").font(
                            .system(size: MacTextSize.meta)
                        )
                        .foregroundStyle(palette.text2)
                    }
                    SlotBar(used: m.used, slots: m.slots)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }
}

struct BoardWidget: View {
    let board: HomeSnapshot.Board
    @Environment(\.corePalette) private var palette
    var body: some View {
        let cols: [(String, Int, Tone?)] = [
            ("Todo", board.todo, nil), ("Doing", board.doing, nil), ("Review", board.review, nil),
            ("Blocked", board.blocked, .warn), ("Done", board.done, nil),
        ]
        let top = max(cols.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetTitle(title: "Citadel board")
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(cols, id: \.0) { name, n, tone in
                    VStack(spacing: Space.s1) {
                        Text("\(n)").font(.system(size: MacTextSize.title, weight: .semibold))
                        coreShape(Radius.chip).fill(tone.map { palette.tone($0).ink } ?? palette.primary)
                            .frame(height: Space.s2 + Space.s6 * CGFloat(n) / CGFloat(top))
                        Text(name).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct EventsWidget: View {
    let home: HomeSnapshot
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetTitle(title: "Recent events")
            ForEach(home.events.prefix(2)) { e in
                HStack(spacing: Space.s2) {
                    Image(systemName: e.symbol).frame(width: MacSize.controlMd, height: MacSize.controlMd)
                        .background(palette.uDim, in: coreShape(Radius.control)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.text).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                        Text("\(e.source) · \(e.minutesAgo) min").font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
