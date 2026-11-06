import CoreUI
import SwiftUI

/// The content of each widget at each size, in the Apple widget style (Ahmed, 2026-11-05): no titles, the data is a
/// picture (bar gauges with an icon above, one short value under each), lots of air, centred.
struct WidgetBody: View {
    let kind: WidgetKind
    let size: WidgetSize
    @Bindable var shell: ShellModel

    var body: some View {
        content
            // Apple centres a widget's content.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
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

/// Gauges side by side, centred, as many as the widget is wide.
struct GaugeRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) { content }
            .frame(maxWidth: .infinity)
    }
}

/// Minutes as people say them: "45 min", "1 h 5 min".
func minutesText(_ m: Int) -> String {
    m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}

extension HomeSnapshot {
    fileprivate var totalSlots: Int { machines.reduce(0) { $0 + $1.slots } }
}

struct RunRows: View {
    let runs: [HomeSnapshot.Run]
    @Environment(\.corePalette) private var palette
    var body: some View {
        ForEach(runs) { r in
            HStack(spacing: Space.s2) {
                StatusDot(color: GlassInk.green, live: true)
                Text(r.tool).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                Text(r.name).foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(minutesText(r.minutes)).font(.system(size: MacTextSize.meta, design: .monospaced))
                    .foregroundStyle(GlassInk.secondary)
            }
            .font(.system(size: MacTextSize.body)).padding(.vertical, Space.s1)
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
        let needs = BarGauge(
            value: min(Double(waiting), 5) / 5, symbol: "hand.raised", tint: GlassInk.orange,
            caption: "\(waiting)", sub: "waiting")
        let running = BarGauge(
            value: Double(h.runningAgents) / Double(max(h.totalSlots, 1)), symbol: "play.fill", tint: GlassInk.blue,
            caption: "\(h.runningAgents)", sub: "running")
        let online = BarGauge(
            value: h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count), symbol: "server.rack",
            tint: GlassInk.green, caption: "\(h.machinesOnline)/\(h.machines.count)", sub: "online")
        VStack(spacing: Space.s4) {
            switch size {
            case .s: needs
            case .t:
                needs
                running
            default:
                GaugeRow {
                    needs
                    running
                    online
                }
                if size == .l || size == .x {
                    if let first = shell.bell.items.first(where: \.needsPerson) {
                        WidgetCard(title: first.title, sub: "\(waiting) waiting on you · Review") {
                            shell.bellOpen = true
                        }
                    }
                    RunRows(runs: Array(h.running.prefix(size == .x ? 6 : 3)))
                }
            }
        }
    }
}

struct NeedsBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let need = shell.bell.items.filter(\.needsPerson)
        let ring = BarGauge(
            value: min(Double(need.count), 5) / 5, symbol: "hand.raised", tint: GlassInk.orange,
            caption: "\(need.count)", sub: need.isEmpty ? "all clear" : "waiting")
        VStack(alignment: .leading, spacing: Space.s3) {
            if size == .s || size == .t {
                ring
            } else {
                HStack(alignment: .top, spacing: Space.s4) {
                    ring.frame(width: 96)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        ForEach(Array(need.prefix(size == .m ? 1 : 4))) { n in
                            WidgetCard(title: n.title, sub: n.sub ?? "Review", compact: size == .m) {
                                shell.bellOpen = true
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RunningBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let ring = BarGauge(
            value: Double(home.runningAgents) / Double(max(home.totalSlots, 1)), symbol: "play.fill",
            tint: GlassInk.blue, caption: "\(home.runningAgents)", sub: "of \(home.totalSlots) slots")
        VStack(alignment: .leading, spacing: Space.s3) {
            if size == .s || size == .t {
                ring
            } else {
                HStack(alignment: .top, spacing: Space.s4) {
                    ring.frame(width: 96)
                    VStack(alignment: .leading, spacing: 0) {
                        RunRows(runs: Array(home.running.prefix(size == .m ? 2 : 8)))
                    }
                }
            }
        }
    }
}

struct SpendBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        // One quantity in the gauge and its caption: the share of this month's tokens. Today's dollars sit beside it.
        let gauge = BarGauge(
            value: home.monthTokensUsed, symbol: "dollarsign", tint: GlassInk.blue,
            caption: "\(Int((home.monthTokensUsed * 100).rounded()))%", sub: "of this month's tokens")
        if size == .s || size == .t {
            VStack {
                gauge
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: Space.s4) {
                gauge.frame(width: 96)
                VStack(alignment: .leading, spacing: Space.s1) {
                    RollingNumber(
                        value: home.spendToday, format: { $0.formatted(.currency(code: "USD")) },
                        size: MacTextSize.large * 1.5)
                    Text("spent today").font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The Batteries layout: one ring per machine, its load, the machine's icon inside, name and percent under it.
struct MachinesBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let per = size == .s ? 1 : size == .m ? 4 : size == .t ? 2 : 4
        let shown = Array(home.machines.prefix(size == .l || size == .x ? 8 : per))
        VStack(spacing: Space.s4) {
            if shown.isEmpty {
                BarGauge(
                    value: 0, symbol: "server.rack", tint: GlassInk.blue, caption: "No machines", sub: "pair a runner"
                )
                .frame(maxWidth: size == .s ? .infinity : 110)
            } else {
                let rows = stride(from: 0, to: shown.count, by: per).map {
                    Array(shown[$0..<min($0 + per, shown.count)])
                }
                ForEach(rows.indices, id: \.self) { r in
                    GaugeRow {
                        ForEach(rows[r]) { m in
                            BarGauge(
                                value: m.online ? (m.load.last ?? 0) : 0,
                                symbol: m.os.hasPrefix("macOS") ? "laptopcomputer" : "server.rack",
                                tint: m.online ? GlassInk.green : GlassInk.secondary,
                                caption: m.online ? "\(m.loadPercent)%" : "Offline",
                                sub: m.id)
                        }
                    }
                }
            }
        }
    }
}

struct BoardBody: View {
    let board: HomeSnapshot.Board
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let total = Double(max(board.todo + board.doing + board.review + board.blocked + board.done, 1))
        let cols: [(String, Int, String, Color)] = [
            ("To do", board.todo, "tray", GlassInk.secondary), ("Doing", board.doing, "hammer", GlassInk.blue),
            ("Review", board.review, "eye", GlassInk.blue),
            ("Blocked", board.blocked, "exclamationmark.octagon", GlassInk.orange),
            ("Done", board.done, "checkmark", GlassInk.green),
        ]
        VStack(spacing: Space.s4) {
            if size == .s {
                BarGauge(
                    value: Double(board.blocked) / total, symbol: "exclamationmark.octagon",
                    tint: GlassInk.orange,
                    caption: "\(board.blocked)", sub: "blocked")
            } else {
                GaugeRow {
                    ForEach(cols, id: \.0) { name, n, symbol, tint in
                        BarGauge(value: Double(n) / total, symbol: symbol, tint: tint, caption: "\(n)", sub: name)
                    }
                }
            }
        }
    }
}

struct EventsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    @State private var arrived = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if home.events.isEmpty {
                BarGauge(
                    value: 0, symbol: "clock.arrow.circlepath", tint: GlassInk.blue, caption: "No events", sub: "yet"
                )
                .frame(maxWidth: 110).frame(maxWidth: .infinity)
            }
            ForEach(Array(home.events.prefix(size == .m ? 2 : 8).enumerated()), id: \.element.id) { i, e in
                HStack(spacing: Space.s3) {
                    Image(systemName: e.symbol).font(.system(size: MacTextSize.body, weight: .semibold))
                        .foregroundStyle(GlassInk.primary)
                        .frame(width: MacSize.controlLg, height: MacSize.controlLg).background(
                            GlassInk.well, in: coreShape(Radius.control)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.text).font(.system(size: MacTextSize.headline, weight: .medium)).lineLimit(1)
                        Text("\(e.source) · \(minutesText(e.minutesAgo))").font(.system(size: MacTextSize.meta))
                            .foregroundStyle(GlassInk.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .coreRise(arrived, i)
            }
        }
        .onAppear { arrived = true }
    }
}

struct CoreBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        let (word, tone): (String, Tone) =
            switch shell.coreLink {
            case .live: ("Connected", .run)
            case .connecting, .reconnecting: ("Reconnecting", .warn)
            case .offline: ("Offline", .fail)
            case .none: ("Not connected", .queue)
            }
        let alarms = shell.bell.items.filter { $0.kind == .alarm }
        VStack {
            BarGauge(
                value: shell.coreLink == .live ? 1 : 0, symbol: "heart.text.square",
                tint: tone == .run ? GlassInk.green : tone == .warn ? GlassInk.orange : palette.tone(tone).ink,
                caption: word,
                sub: alarms.isEmpty ? "no alarms" : alarms.count == 1 ? "1 alarm" : "\(alarms.count) alarms")
        }
    }
}

struct ClockBody: View {
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    /// The macOS clock widget: the dial is the widget. Wider sizes put the day and date beside or under it.
    var body: some View {
        switch size {
        case .s:
            // The dial nearly fills the widget, a thin glass rim around it (macOS).
            AnalogClock().padding(-Space.s2).frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VStack(alignment: big ? .leading : .center, spacing: 0) {
                Text(ctx.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: big ? MacTextSize.large : MacTextSize.title, weight: .semibold))
                Text(ctx.date, format: .dateTime.month(.wide).day())
                    .font(.system(size: MacTextSize.body)).foregroundStyle(GlassInk.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
