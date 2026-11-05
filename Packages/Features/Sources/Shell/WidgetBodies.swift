import CoreUI
import SwiftUI

/// The content of each widget at each size (`widgets-set.js`: every size is its own composition, not a scaled copy).
struct WidgetBody: View {
    let kind: WidgetKind
    let size: WidgetSize
    @Bindable var shell: ShellModel

    var body: some View {
        switch kind {
        case .today: TodayBody(shell: shell, size: size)
        case .needs: NeedsBody(shell: shell, size: size)
        case .running: RunningBody(home: shell.home, size: size)
        case .spend: SpendBody(home: shell.home, size: size)
        case .machines: MachinesBody(home: shell.home, size: size)
        case .board: BoardBody(board: shell.home.board, size: size)
        case .events: EventsBody(home: shell.home, size: size)
        case .core: CoreBody(shell: shell, size: size)
        case .quick: QuickBody(shell: shell, size: size)
        case .clock: ClockBody(size: size)
        }
    }
}

private func slotsText(_ m: HomeSnapshot.Machine) -> String {
    m.online ? (m.used == 0 ? "Idle" : "\(m.used) of \(m.slots) slots") : "Offline"
}

struct RunRows: View {
    let runs: [HomeSnapshot.Run]
    @Environment(\.corePalette) private var palette
    var body: some View {
        ForEach(runs) { r in
            HStack(spacing: Space.s2) {
                StatusDot(color: palette.tone(.run).ink, live: true)
                Text(r.tool).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                Text(r.name).foregroundStyle(palette.text2).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(r.minutes) min").font(.system(size: MacTextSize.meta, design: .monospaced))
                    .foregroundStyle(palette.text2)
            }
            .font(.system(size: MacTextSize.body)).padding(.vertical, 3)
            .accessibilityElement(children: .combine)
        }
    }
}

struct TodayBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.corePalette) private var palette

    var body: some View {
        let h = shell.home
        let waiting = shell.bell.waiting
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WidgetHead(title: "Today", symbol: "sun.max")
                WidgetBig(value: "\(waiting)", caption: "waiting", small: true)
                Spacer(minLength: 0)
                Text("\(h.runningAgents) running").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            case .m:
                WidgetHead(
                    title: "Today", sub: "\(h.coreName) · \(h.machinesOnline) of \(h.machines.count) online",
                    symbol: "sun.max")
                needsCard
                Spacer(minLength: 0)
            case .t:
                WidgetHead(title: "Today", symbol: "sun.max")
                WidgetLabel("Needs you")
                WidgetBig(value: "\(waiting)", caption: "waiting", small: true)
                WidgetLabel("Running")
                if h.running.isEmpty {
                    WidgetCalm("None.", symbol: "moon.zzz")
                } else {
                    RunRows(runs: Array(h.running.prefix(3)))
                }
                Spacer(minLength: 0)
            case .l, .x:
                WidgetHead(
                    title: "Today", sub: "\(h.coreName) · \(h.machinesOnline) of \(h.machines.count) machines online",
                    symbol: "sun.max")
                needsSection
                WidgetLabel("Running")
                if h.running.isEmpty {
                    WidgetCalm("No agents running.", symbol: "moon.zzz")
                } else {
                    RunRows(runs: h.running)
                }
                if size == .x {
                    WidgetLabel("Machines")
                    ForEach(h.machines) { m in
                        HStack(spacing: Space.s2) {
                            StatusDot(color: m.online ? palette.tone(.run).ink : palette.tone(.queue).ink)
                            Text(m.id).font(.system(size: MacTextSize.headline, weight: .semibold))
                            Text(slotsText(m)).foregroundStyle(palette.text2)
                            Spacer(minLength: 0)
                            SlotBar(used: m.used, slots: m.slots)
                        }
                        .font(.system(size: MacTextSize.body)).padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var needsCard: some View {
        if let first = shell.bell.items.first(where: \.needsPerson) {
            WidgetCard(title: first.title, sub: "\(shell.bell.waiting) waiting on you · Review", compact: true) {
                shell.bellOpen = true
            }
        } else {
            WidgetCalm("Nothing is waiting on you.", symbol: "checkmark.seal")
        }
    }

    @ViewBuilder private var needsSection: some View {
        WidgetLabel("Needs you")
        if let first = shell.bell.items.first(where: \.needsPerson) {
            WidgetCard(title: first.title, sub: "\(shell.bell.waiting) waiting on you · Review") {
                shell.bellOpen = true
            }
        } else {
            WidgetCalm("Nothing is waiting on you.", symbol: "checkmark.seal")
        }
    }
}

struct NeedsBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    var body: some View {
        let need = shell.bell.items.filter(\.needsPerson)
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WidgetHead(title: "Needs you", symbol: "hand.raised")
                WidgetBig(value: "\(need.count)", caption: "waiting")
                Spacer(minLength: 0)
            default:
                WidgetHead(
                    title: "Needs you", sub: need.isEmpty ? nil : "\(need.count) waiting on you", symbol: "hand.raised")
                if need.isEmpty { WidgetCalm("Nothing is waiting on you.", symbol: "checkmark.seal") }
                ForEach(Array(need.prefix(size == .m ? 1 : size == .t ? 3 : 4))) { n in
                    WidgetCard(title: n.title, sub: n.sub ?? "Review", compact: size == .m) { shell.bellOpen = true }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RunningBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if size == .s {
                WidgetHead(title: "Running", symbol: "sparkles")
                WidgetBig(value: "\(home.runningAgents)", caption: "agents")
            } else {
                WidgetHead(title: "Running agents", sub: "\(home.runningAgents) working now", symbol: "sparkles")
                if home.running.isEmpty { WidgetCalm("No agents running.", symbol: "moon.zzz") }
                RunRows(runs: Array(home.running.prefix(size == .m ? 2 : 8)))
            }
            Spacer(minLength: 0)
        }
    }
}

struct SpendBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let pct = Int(home.monthTokensUsed * 100)
        VStack(alignment: .leading, spacing: Space.s1) {
            if size != .s { WidgetHead(title: "Agent spend", symbol: "dollarsign.circle") }
            Spacer(minLength: 0)
            RollingNumber(
                value: home.spendToday, format: { $0.formatted(.currency(code: "USD")) }, size: size == .s ? 28 : 38,
                design: .monospaced)
            Text("today").foregroundStyle(palette.text2)
            Meter(value: home.monthTokensUsed).padding(.vertical, Space.s1)
            Text("\(pct)% of month tokens").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            if size != .s { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MachinesBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(
                title: "Machines", sub: "\(home.machinesOnline) of \(home.machines.count) online", symbol: "server.rack"
            )
            if home.machines.isEmpty {
                WidgetCalm("No machines yet. A runner shows up here once it pairs.", symbol: "server.rack")
            }
            ForEach(size == .m ? Array(home.machines.prefix(2)) : home.machines) { m in
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        StatusDot(color: m.online ? palette.tone(.run).ink : palette.tone(.queue).ink, live: m.online)
                        Text(m.id).font(.system(size: MacTextSize.headline, weight: .semibold))
                        if size == .l {
                            Text(m.os).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: 0)
                        Text(m.online ? "\(m.used) of \(m.slots) slots" : "Offline")
                            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    }
                    HStack(spacing: Space.s2) {
                        SlotBar(used: m.used, slots: m.slots)
                        if size != .t { Sparkline(values: m.load).frame(height: Space.s4) } else { Spacer() }
                        Text("\(m.loadPercent)%").font(.system(size: MacTextSize.body, design: .monospaced))
                            .foregroundStyle(palette.text2).frame(minWidth: Space.s8, alignment: .trailing)
                    }
                    .padding(.leading, Space.s4)
                }
                .padding(.vertical, size == .l ? 4 : 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(m.id), \(m.online ? "\(m.used) of \(m.slots) slots, load \(m.loadPercent) percent" : "offline")")
            }
            Spacer(minLength: 0)
            if let secs = home.loadSampleSeconds, size != .m {
                Text("Host load, sampled here every \(secs) s").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2)
            }
        }
    }
}

struct BoardBody: View {
    let board: HomeSnapshot.Board
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The bars grow from the floor one after another when the widget arrives.
    @State private var grown = false
    var body: some View {
        let cols: [(String, Int, Tone?)] = [
            ("Todo", board.todo, nil), ("Doing", board.doing, nil), ("Review", board.review, nil),
            ("Blocked", board.blocked, .warn), ("Done", board.done, nil),
        ]
        let top = max(cols.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(title: "Citadel board", symbol: "square.grid.3x3.topleft.filled")
            if size == .s {
                WidgetBig(value: "\(board.blocked)", caption: "blocked", small: true)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .bottom, spacing: Space.s2) {
                    ForEach(Array(cols.enumerated()), id: \.element.0) { idx, col in
                        let (name, n, tone) = col
                        VStack(spacing: Space.s1) {
                            RollingNumber(
                                value: Double(n), size: MacTextSize.title,
                                ink: tone.map { palette.tone($0).ink } ?? palette.text)
                            coreShape(5).fill(palette.track)
                                .frame(height: (size == .l ? 150 : 34))
                                .overlay(alignment: .bottom) {
                                    GeometryReader { g in
                                        let ink = tone.map { palette.tone($0).ink } ?? palette.primary
                                        coreShape(5)
                                            .fill(
                                                LinearGradient(
                                                    colors: [ink, ink.opacity(0.55)], startPoint: .top,
                                                    endPoint: .bottom)
                                            )
                                            .shadow(color: ink.opacity(0.5), radius: 4)
                                            .frame(
                                                height: grown ? max(6, g.size.height * CGFloat(n) / CGFloat(top)) : 0
                                            )
                                            .frame(maxHeight: .infinity, alignment: .bottom)
                                            .animation(
                                                reduce
                                                    ? .easeOut(duration: 0.2)
                                                    : .spring(duration: 0.7, bounce: 0.3).delay(Double(idx) * 0.08),
                                                value: grown)
                                    }
                                }
                            Text(name).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { grown = true }
    }
}

struct EventsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrived = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(title: "Recent events", symbol: "clock.arrow.circlepath")
            if home.events.isEmpty { WidgetCalm("Nothing has happened yet.", symbol: "sparkles") }
            ForEach(Array(home.events.prefix(size == .m ? 2 : 8).enumerated()), id: \.element.id) { i, e in
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: e.symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .frame(width: 26, height: 26).coreGlass(radius: Radius.control, interactive: false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.text).font(.system(size: MacTextSize.headline, weight: .medium)).lineLimit(
                            size == .m ? 1 : 2)
                        Text("\(e.source) · \(e.minutesAgo) min").font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2)
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
                .rise(arrived, i, reduce)
            }
            Spacer(minLength: 0)
        }
        .onAppear { arrived = true }
    }
}

struct CoreBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    private var state: (String, Tone) {
        switch shell.coreLink {
        case .live: ("Connected", .run)
        case .connecting, .reconnecting: ("Reconnecting", .warn)
        case .offline: ("Offline", .fail)
        case .none: ("Not connected", .queue)
        }
    }
    var body: some View {
        let alarms = shell.bell.items.filter { $0.kind == .alarm }
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(title: "Core health", sub: size == .s ? nil : shell.home.coreName, symbol: "heart.text.square")
            HStack(spacing: Space.s2) {
                StatusDot(color: palette.tone(state.1).ink, live: shell.coreLink == .live)
                Text(state.0).font(.system(size: size == .s ? 15 : 20, weight: .semibold))
            }
            .padding(.top, Space.s1)
            if size != .s {
                Text(alarms.isEmpty ? "No alarms" : "\(alarms.count) alarm raised")
                    .font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
            }
            if size == .l {
                WidgetLabel("Alarms")
                if alarms.isEmpty { WidgetCalm("Nothing raised.") }
                ForEach(alarms) { a in Text(a.title).font(.system(size: MacTextSize.body)).padding(.vertical, 2) }
            } else if size == .m, let a = alarms.first {
                Text(a.title).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ClockBody: View {
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    /// The macOS clock widget: the dial is the widget. Wider sizes put the day and date beside or under it.
    var body: some View {
        switch size {
        case .s:
            AnalogClock().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .m:
            HStack(spacing: Space.s4) {
                AnalogClock()
                dateText(big: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            VStack(spacing: Space.s3) {
                AnalogClock().frame(maxWidth: .infinity)
                dateText(big: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dateText(big: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            VStack(alignment: big ? .leading : .center, spacing: 2) {
                Text(ctx.date, format: .dateTime.weekday(.wide)).font(.system(size: big ? 20 : 15, weight: .semibold))
                Text(ctx.date, format: .dateTime.month(.wide).day())
                    .font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
