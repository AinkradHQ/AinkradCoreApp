import CoreUI
import SwiftUI

/// The content of each widget at each size, in the Apple widget style (Ahmed, 2026-11-05): no titles, the data is a
/// picture (ring gauges with an icon inside, one short value under each), lots of air, centred.
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

/// Rings side by side, centred, as many as the widget is wide.
struct RingRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) { content }
            .frame(maxWidth: .infinity)
    }
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
                StatusDot(color: WidgetInk.green, live: true)
                Text(r.tool).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                Text(r.name).foregroundStyle(WidgetInk.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(r.minutes) min").coreFont(size: MacTextSize.meta, design: .monospaced)
                    .foregroundStyle(WidgetInk.secondary)
            }
            .coreFont(size: MacTextSize.body).padding(.vertical, 3)
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
        let waiting = shell.waitingOnYou
        let needs = RingGauge(
            value: min(Double(waiting), 5) / 5, symbol: "hand.raised", tint: WidgetInk.orange,
            caption: "\(waiting)", sub: "waiting")
        let running = RingGauge(
            value: Double(h.runningAgents) / Double(max(h.totalSlots, 1)), symbol: "sparkles", tint: WidgetInk.blue,
            caption: "\(h.runningAgents)", sub: "running")
        let online = RingGauge(
            value: h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count), symbol: "server.rack",
            tint: WidgetInk.green, caption: "\(h.machinesOnline)/\(h.machines.count)", sub: "online")
        VStack(spacing: Space.s4) {
            switch size {
            case .s: needs
            case .t:
                needs
                running
            default:
                RingRow {
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
        let ring = RingGauge(
            value: min(Double(need.count), 5) / 5, symbol: "hand.raised", tint: WidgetInk.orange,
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
        let ring = RingGauge(
            value: Double(home.runningAgents) / Double(max(home.totalSlots, 1)), symbol: "sparkles",
            tint: WidgetInk.blue, caption: "\(home.runningAgents)", sub: "of \(home.totalSlots) slots")
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
        let ring = RingGauge(
            value: home.monthTokensUsed, symbol: "dollarsign", tint: WidgetInk.blue,
            caption: home.spendToday.formatted(.currency(code: "USD")), sub: "today")
        if size == .s || size == .t {
            VStack {
                ring
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: Space.s4) {
                ring.frame(width: 96)
                VStack(alignment: .leading, spacing: Space.s1) {
                    RollingNumber(value: home.monthTokensUsed * 100, format: { "\(Int($0))%" }, size: 30)
                    Text("of this month's tokens").coreFont(size: MacTextSize.body).foregroundStyle(
                        WidgetInk.secondary)
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
                RingGauge(
                    value: 0, symbol: "server.rack", tint: WidgetInk.blue, caption: "No machines", sub: "pair a runner"
                )
                .frame(maxWidth: size == .s ? .infinity : 110)
            } else {
                let rows = stride(from: 0, to: shown.count, by: per).map {
                    Array(shown[$0..<min($0 + per, shown.count)])
                }
                ForEach(rows.indices, id: \.self) { r in
                    RingRow {
                        ForEach(rows[r]) { m in
                            RingGauge(
                                value: m.online ? (m.load.last ?? 0) : 0,
                                symbol: m.os.hasPrefix("macOS") ? "laptopcomputer" : "server.rack",
                                tint: m.online ? WidgetInk.green : WidgetInk.secondary,
                                caption: m.online ? "\(m.loadPercent)%" : "Off",
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
            ("Todo", board.todo, "tray", WidgetInk.secondary), ("Doing", board.doing, "hammer", WidgetInk.blue),
            ("Review", board.review, "eye", WidgetInk.blue),
            ("Blocked", board.blocked, "exclamationmark.octagon", WidgetInk.orange),
            ("Done", board.done, "checkmark", WidgetInk.green),
        ]
        VStack(spacing: Space.s4) {
            if size == .s {
                RingGauge(
                    value: Double(board.blocked) / total, symbol: "exclamationmark.octagon",
                    tint: WidgetInk.orange,
                    caption: "\(board.blocked)", sub: "blocked")
            } else {
                RingRow {
                    ForEach(cols, id: \.0) { name, n, symbol, tint in
                        RingGauge(value: Double(n) / total, symbol: symbol, tint: tint, caption: "\(n)", sub: name)
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
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrived = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if home.events.isEmpty {
                RingGauge(
                    value: 0, symbol: "clock.arrow.circlepath", tint: WidgetInk.blue, caption: "No events", sub: "yet"
                )
                .frame(maxWidth: 110).frame(maxWidth: .infinity)
            }
            ForEach(Array(home.events.prefix(size == .m ? 2 : 8).enumerated()), id: \.element.id) { i, e in
                HStack(spacing: Space.s3) {
                    Image(systemName: e.symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(WidgetInk.primary)
                        .frame(width: 34, height: 34).background(WidgetInk.well, in: coreShape(Radius.control))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.text).coreFont(size: MacTextSize.headline, weight: .medium).lineLimit(1)
                        Text("\(e.source) · \(e.minutesAgo) min").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(WidgetInk.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .rise(arrived, i, reduce)
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
            RingGauge(
                value: shell.coreLink == .live ? 1 : 0.25, symbol: "heart.text.square",
                tint: tone == .run ? WidgetInk.green : tone == .warn ? WidgetInk.orange : palette.tone(tone).ink,
                caption: word, sub: alarms.isEmpty ? "no alarms" : "\(alarms.count) alarm")
        }
    }
}

struct ClockBody: View {
    let size: WidgetSize
    @Environment(\.homeLive) private var live
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
        TimelineView(homeTicks(60, live: live)) { ctx in
            VStack(alignment: big ? .leading : .center, spacing: 2) {
                Text(ctx.date, format: .dateTime.weekday(.wide)).coreFont(size: big ? 20 : 15, weight: .semibold)
                Text(ctx.date, format: .dateTime.month(.wide).day())
                    .coreFont(size: MacTextSize.body).foregroundStyle(WidgetInk.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
