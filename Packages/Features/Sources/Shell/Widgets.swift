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
            .padding(ShellMetrics.widgetGap)
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

/// The prototype's status dot: a small rounded square (never a circle). The word beside it says the same thing.
struct StatusDot: View {
    let color: Color
    var body: some View {
        coreShape(Space.s1 / 2 + Space.s1 / 2).fill(color).frame(width: Space.s2, height: Space.s2).accessibilityHidden(
            true)
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
        HStack(spacing: Space.s1) {
            ForEach(0..<max(slots, 0), id: \.self) { i in
                coreShape(Space.s1).fill(i < used ? palette.primary : palette.track)
                    .frame(width: Space.s4, height: Space.s2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Host load as a thin line, newest on the right.
private struct Sparkline: View {
    let values: [Double]
    @Environment(\.corePalette) private var palette
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(
                        x: g.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: g.size.height * (1 - CGFloat(min(max(v, 0), 1))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(palette.primary, style: StrokeStyle(lineWidth: Space.s1 / 2, lineCap: .round, lineJoin: .round))
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
                Text("Needs you").font(.system(size: MacTextSize.body, weight: .semibold))
                Button {
                    shell.bellOpen = true
                } label: {
                    HStack(spacing: Space.s3) {
                        StatusDot(color: palette.primary)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(first.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                                .multilineTextAlignment(.leading)
                            Text("\(shell.bell.waiting) waiting on you · Review").font(.system(size: MacTextSize.meta))
                                .foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.glassCard, in: coreShape(Radius.row))
                }
                .buttonStyle(.plain)
            }
            if !h.running.isEmpty {
                Text("Running").font(.system(size: MacTextSize.body, weight: .semibold))
                ForEach(h.running) { r in
                    HStack(spacing: Space.s2) {
                        StatusDot(color: palette.tone(.run).ink)
                        Text(r.tool).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text(r.name).foregroundStyle(palette.text2).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(r.minutes) min").font(.system(size: MacTextSize.meta, design: .monospaced))
                            .foregroundStyle(palette.text2)
                    }
                    .font(.system(size: MacTextSize.body))
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Machines").font(.system(size: MacTextSize.body, weight: .semibold))
            ForEach(h.machines) { m in
                HStack(spacing: Space.s2) {
                    StatusDot(color: m.online ? palette.tone(.run).ink : palette.tone(.queue).ink)
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
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            VStack(alignment: .leading, spacing: Space.s1) {
                Spacer(minLength: 0)
                Text(ctx.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: MacTextSize.large * 2.2, weight: .semibold)).monospacedDigit()
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
            Text(home.spendToday, format: .currency(code: "USD"))
                .font(.system(size: MacTextSize.large * 1.5, weight: .bold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("today").foregroundStyle(palette.text2)
            Meter(value: home.monthTokensUsed)
            Spacer(minLength: Space.s2)
            Text("\(Int(home.monthTokensUsed * 100))% of month tokens").font(.system(size: MacTextSize.meta))
                .foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 2 x 2 tall tiles, icon above the label. Launcher is the one prominent tile.
struct QuickWidget: View {
    @Bindable var shell: ShellModel
    var body: some View {
        Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
            GridRow {
                quick("New agent session", "play", id: "new-session")
                quick("New terminal", "terminal", id: "new-terminal")
            }
            GridRow {
                quick("Add device", "plus", id: "add-device")
                QuickTile(title: "Launcher", symbol: "magnifyingglass", keycap: "⌘K", prominent: true) {
                    shell.toggleLauncher()
                }
            }
        }
    }
    private func quick(_ title: String, _ symbol: String, id: String) -> some View {
        QuickTile(title: title, symbol: symbol) {
            if let e = shell.launcher.entry(id) {
                e.run()
            } else {
                shell.showToast("\(title) arrives with its feature module.")
            }
        }
    }
}

private struct QuickTile: View {
    let title: String
    let symbol: String
    var keycap: String?
    var prominent = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s1) {
                Image(systemName: symbol).font(.system(size: MacTextSize.title, weight: .medium)).accessibilityHidden(
                    true)
                HStack(spacing: Space.s1) {
                    Text(title).font(.system(size: MacTextSize.meta, weight: .medium)).lineLimit(1)
                    if let keycap { Text(keycap).font(.system(size: MacTextSize.meta)).opacity(0.8) }
                }
            }
            .foregroundStyle(prominent ? palette.btnInk : palette.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill, in: coreShape(Radius.control))
            .overlay { if !prominent { coreShape(Radius.control).strokeBorder(palette.glassCardEdge, lineWidth: 1) } }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.control, palette: palette)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(keycap.map { "\(title), \($0)" } ?? title)
    }

    private var fill: Color {
        prominent
            ? (hovering ? palette.btnPrimaryHover : palette.btnPrimary) : (hovering ? palette.uDimHover : palette.uDim)
    }
}

struct MachinesWidget: View {
    let home: HomeSnapshot
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            WidgetTitle(title: "Machines", sub: "\(home.machinesOnline) of \(home.machines.count) online")
            ForEach(home.machines) { m in
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        StatusDot(color: m.online ? palette.tone(.run).ink : palette.tone(.queue).ink)
                        Text(m.id).font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text(m.os).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(m.online ? "\(m.used) of \(m.slots) slots" : "Offline").font(
                            .system(size: MacTextSize.meta)
                        )
                        .foregroundStyle(palette.text2)
                    }
                    HStack(spacing: Space.s2) {
                        SlotBar(used: m.used, slots: m.slots)
                        Sparkline(values: m.load).frame(height: Space.s4)
                        Text("\(m.loadPercent)%").font(.system(size: MacTextSize.body, design: .monospaced))
                            .frame(minWidth: Space.s8, alignment: .trailing)
                    }
                    .padding(.leading, Space.s4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(m.id), \(m.online ? "\(m.used) of \(m.slots) slots, load \(m.loadPercent) percent" : "offline")")
            }
            Spacer(minLength: 0)
            if let secs = home.loadSampleSeconds {
                Text("Host load, sampled here every \(secs) s").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2)
            }
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
