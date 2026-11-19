import CoreUI
import SwiftUI

// The existing widgets, each size its own layout as in `05-widgets.js`: small a glance, medium a list, wide a chart or
// a row of cards, large the detail. Figures the Core does not report are left out, never invented.

/// One row: a symbol, a title with a line under it, and something at the end.
struct WRow: View {
    let symbol: String
    let title: String
    var sub: String?
    var trailing: String?
    var tint: Color = GlassInk.blue
    var chevron = false
    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                if let sub { WCaption(sub) }
            }
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .accessibilityElement(children: .combine)
    }
}

/// Up to four figures side by side, each with its word and, when it has one, a bar.
struct WStats: View {
    struct Item: Identifiable {
        let id: String
        let value: String
        var warn = false
        var bar: Double?
    }
    let items: [Item]
    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            ForEach(items) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.value).coreFont(size: 22, weight: .bold)
                        .foregroundStyle(i.warn ? GlassInk.amberInk : GlassInk.primary).lineLimit(1)
                        .minimumScaleFactor(0.6)
                    WCaption(i.id)
                    if let b = i.bar { CoreMeter(b, low: i.warn, label: i.id) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private func money(_ x: Double) -> String { x.formatted(.currency(code: "USD")) }

// MARK: Running AI sessions

struct RunningBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let runs = shell.home.running
        VStack(alignment: .leading, spacing: Space.s2) {
            if runs.isEmpty {
                WHead("text.cursor", "AI sessions")
                WEmpty(symbol: "sparkles", text: "No AI sessions running")
            } else {
                let longest = Double(max(runs.map(\.minutes).max() ?? 1, 1))
                let chip = StateBadge("\(runs.count) running", tone: .done, symbol: "checkmark")
                switch size {
                case .s:
                    WHead("text.cursor", "AI sessions")
                    WFigure(value: Double(runs.count), caption: "running")
                    Spacer(minLength: 0)
                    WColumns(values: runs.prefix(7).map { Double($0.minutes) }).frame(height: 18)
                case .m:
                    WHead("text.cursor", "AI sessions") { chip }
                    ForEach(runs.prefix(3)) { r in
                        WRow(symbol: "sparkles", title: r.name, sub: r.tool, trailing: "\(r.minutes) min")
                            .newRow(reduce)
                    }
                case .w:
                    WHead("text.cursor", "AI sessions") { chip }
                    VStack(spacing: Space.s2) {
                        ForEach(runs.prefix(3)) { r in
                            HStack(spacing: Space.s3) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                    WCaption(r.tool)
                                }
                                .frame(width: 200, alignment: .leading)
                                // The bar runs from when it started to now, on one shared clock.
                                GeometryReader { g in
                                    let w = g.size.width * Double(r.minutes) / longest
                                    coreShape(3).fill(GlassInk.blue).frame(width: max(6, w), height: 6)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(height: 6)
                                .background(GlassInk.well, in: coreShape(3))
                                .accessibilityLabel("\(r.minutes) minutes")
                            }
                        }
                    }
                case .l:
                    WHead("text.cursor", "AI sessions") { chip }
                    if let f = runs.first {
                        WSub {
                            Text(f.name).coreFont(size: MacTextSize.body, weight: .semibold)
                                .foregroundStyle(GlassInk.primary)
                            WCaption("\(f.tool) · \(f.minutes) min")
                        }
                        .frame(maxHeight: 64)
                    }
                    ForEach(runs.dropFirst().prefix(4)) { r in
                        WRow(symbol: "sparkles", title: r.name, sub: r.tool, trailing: "\(r.minutes) min")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: runs.map(\.id))
    }
}

// MARK: AI spend

struct SpendBody: View {
    let home: HomeSnapshot
    let size: WidgetSize

    private var week: Double { home.spendByDay.suffix(7).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if home.monthSpend == 0 && home.spendToday == 0 && !home.spendByDay.contains(where: { $0 > 0 }) {
                WHead("creditcard", "AI spend")
                WEmpty(symbol: "creditcard", text: "No spend yet this month")
            } else {
                switch size {
                case .s:
                    WHead("creditcard", "AI spend")
                    WFigure(value: home.monthSpend, format: money, caption: "this month", size: 28)
                    Spacer(minLength: 0)
                    WCaption("\(money(home.spendToday)) today")
                case .m:
                    WHead("creditcard", "AI spend")
                    VStack(spacing: Space.s2) {
                        ForEach(
                            [("Today", home.spendToday), ("This week", week), ("This month", home.monthSpend)], id: \.0
                        ) { k in
                            HStack {
                                WCaption(k.0)
                                Spacer(minLength: Space.s2)
                                Text(money(k.1)).coreFont(size: MacTextSize.body, weight: .semibold)
                                    .foregroundStyle(GlassInk.primary).monospacedDigit()
                            }
                        }
                    }
                case .w:
                    HStack(alignment: .top, spacing: Space.s5) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            WCaption("This month")
                            RollingNumber(value: home.monthSpend, format: money, size: 32, ink: GlassInk.primary)
                            WCaption("\(money(home.spendToday)) today")
                        }
                        .frame(width: 190, alignment: .leading)
                        WColumns(values: Array(home.spendByDay.suffix(14)))
                    }
                case .l:
                    WHead("creditcard", "AI spend")
                    WFigure(value: home.monthSpend, format: money, caption: "this month", size: 32)
                    WColumns(values: Array(home.spendByDay.suffix(14))).frame(height: 56)
                    let top = max(home.monthSpend, 0.0001)
                    ForEach(
                        [("Today", home.spendToday), ("This week", week), ("This month", home.monthSpend)], id: \.0
                    ) { k in
                        WBarRow(label: k.0, value: money(k.1), fill: k.1 / top)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: Machines

struct MachinesBody: View {
    let home: HomeSnapshot
    let size: WidgetSize

    private func share(_ m: HomeSnapshot.Machine) -> Double {
        m.online ? (m.load.last ?? Double(m.used) / Double(max(m.slots, 1))) : 0
    }
    private func pct(_ m: HomeSnapshot.Machine) -> String { "\(Int((share(m) * 100).rounded()))%" }

    var body: some View {
        let ms = home.machines
        let chip = StateBadge("\(home.machinesOnline) of \(ms.count) up", tone: .done, symbol: "checkmark")
        VStack(alignment: .leading, spacing: Space.s2) {
            if ms.isEmpty {
                WHead("server.rack", "Machines")
                WEmpty(symbol: "server.rack", text: "No runners yet. Add one.")
            } else {
                switch size {
                case .s:
                    WHead("server.rack", "Machines")
                    HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                        RollingNumber(value: Double(home.machinesOnline), size: 38, ink: GlassInk.primary)
                        Text("of \(ms.count)").coreFont(size: 18, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    }
                    WCaption("up")
                    Spacer(minLength: 0)
                    WColumns(values: ms.prefix(5).map(share)).frame(height: 18)
                case .m:
                    WHead("server.rack", "Machines") { chip }
                    ForEach(ms.prefix(3)) { m in
                        WBarRow(label: m.id, value: m.online ? pct(m) : "Offline", fill: share(m))
                    }
                case .w:
                    WHead("server.rack", "Machines") { chip }
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(ms.prefix(5)) { m in
                            WSub {
                                if m.load.isEmpty { CoreMeter(share(m), label: m.id) } else { WColumns(values: m.load) }
                                Text(m.id).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                                    .foregroundStyle(GlassInk.primary)
                                WCaption(m.os)
                            }
                            .opacity(m.online ? 1 : 0.55)
                        }
                    }
                case .l:
                    WHead("server.rack", "Machines") { chip }
                    VStack(spacing: Space.s3) {
                        ForEach(ms.prefix(6)) { m in
                            WRow(
                                symbol: m.os.hasPrefix("macOS") ? "laptopcomputer" : "server.rack", title: m.id,
                                sub: m.online ? m.os : "\(m.os) · offline", trailing: m.online ? pct(m) : "Offline",
                                tint: m.online ? GlassInk.green : GlassInk.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: Needs you

struct NeedsBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let need = shell.bell.items.filter(\.needsPerson)
        let chip: StateBadge? = need.isEmpty ? nil : StateBadge("\(need.count)", tone: .warn, symbol: "hand.raised")
        VStack(alignment: .leading, spacing: Space.s2) {
            if need.isEmpty {
                WHead("bell", "Needs you")
                WEmpty(symbol: "checkmark.circle", text: "Nothing needs you")
            } else {
                switch size {
                case .s:
                    WHead("bell", "Needs you")
                    WFigure(value: Double(need.count), caption: "waiting")
                    Spacer(minLength: 0)
                    if let t = need.first?.time { WCaption("Oldest: \(t)") }
                case .m:
                    WHead("bell", "Needs you") { chip }
                    ForEach(need.prefix(2)) { n in
                        WRow(symbol: n.symbol, title: n.title, trailing: n.time, tint: GlassInk.amber).newRow(reduce)
                    }
                case .w:
                    WHead("bell", "Needs you")
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(need.prefix(3)) { n in
                            WSub {
                                Image(systemName: n.symbol).foregroundStyle(GlassInk.amber).accessibilityHidden(true)
                                Text(n.title).coreFont(size: MacTextSize.body, weight: .semibold)
                                    .foregroundStyle(GlassInk.primary).lineLimit(2)
                                WCaption([n.sub, n.time].compactMap { $0 }.joined(separator: " · "))
                            }
                        }
                    }
                case .l:
                    WHead("bell", "Needs you") { chip }
                    VStack(spacing: Space.s3) {
                        ForEach(need.prefix(5)) { n in
                            WRow(
                                symbol: n.symbol, title: n.title,
                                sub: [n.sub, n.time].compactMap { $0 }.joined(separator: " · "), tint: GlassInk.amber,
                                chevron: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: need.map(\.id))
    }
}

// MARK: Recent events

struct EventsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    private func when(_ e: HomeSnapshot.Event) -> String {
        e.minutesAgo < 1 ? "now" : e.minutesAgo < 60 ? "\(e.minutesAgo) min ago" : "\(e.minutesAgo / 60) h ago"
    }

    var body: some View {
        let ev = home.events
        VStack(alignment: .leading, spacing: Space.s2) {
            if ev.isEmpty {
                WHead("clock", "Events")
                WEmpty(symbol: "clock", text: "Nothing happened yet")
            } else {
                switch size {
                case .s:
                    WHead("clock", "Events")
                    if let e = ev.first {
                        Spacer(minLength: 0)
                        Text(e.text).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(
                            GlassInk.primary
                        )
                        .lineLimit(3)
                        WCaption(when(e))
                    }
                case .m:
                    WHead("clock", "Events")
                    ForEach(ev.prefix(3)) { e in WRow(symbol: e.symbol, title: e.text, sub: when(e)).newRow(reduce) }
                case .w:
                    WHead("clock", "Events")
                    HStack(alignment: .top, spacing: Space.s5) {
                        VStack(spacing: Space.s2) {
                            ForEach(ev.prefix(2)) { e in WRow(symbol: e.symbol, title: e.text, sub: when(e)) }
                        }
                        VStack(spacing: Space.s2) {
                            ForEach(ev.dropFirst(2).prefix(2)) { e in
                                WRow(symbol: e.symbol, title: e.text, sub: when(e))
                            }
                        }
                    }
                case .l:
                    WHead("clock", "Events")
                    VStack(spacing: Space.s3) {
                        ForEach(ev.prefix(6)) { e in
                            WRow(symbol: e.symbol, title: e.text, sub: "\(when(e)) · \(e.source)")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: ev.map(\.id))
    }
}

// MARK: Today

struct TodayBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize

    var body: some View {
        let h = shell.home
        let waiting = shell.waitingOnYou
        let down = h.machines.filter { !$0.online }
        let slots = max(h.totalSlots, 1)
        let chip: StateBadge? =
            down.isEmpty ? nil : StateBadge("\(down.count) down", tone: .warn, symbol: "exclamationmark.triangle")
        let up = "\(h.machinesOnline) of \(h.machines.count)"
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WHead("calendar", "Today")
                WFigure(value: Double(waiting), caption: "need you")
                Spacer(minLength: 0)
                WCaption("\(h.runningAgents) running")
            case .m:
                WHead("calendar", "Today")
                WStats(items: [
                    .init(id: "Need you", value: "\(waiting)", warn: waiting > 0),
                    .init(id: "Running", value: "\(h.runningAgents)"), .init(id: "Machines up", value: up),
                ])
            case .w:
                WHead("calendar", "Today") { chip }
                WStats(items: [
                    .init(id: "Need you", value: "\(waiting)", warn: waiting > 0, bar: min(Double(waiting), 5) / 5),
                    .init(id: "Running now", value: "\(h.runningAgents)", bar: Double(h.runningAgents) / Double(slots)),
                    .init(
                        id: "Machines up", value: up,
                        bar: h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count)),
                    .init(id: "Spent today", value: money(h.spendToday)),
                ])
            case .l:
                WHead("calendar", "Today")
                WStats(items: [
                    .init(id: "Need you", value: "\(waiting)", warn: waiting > 0),
                    .init(id: "Running", value: "\(h.runningAgents)"), .init(id: "Up", value: up),
                ])
                VStack(spacing: Space.s3) {
                    ForEach(shell.bell.items.filter(\.needsPerson).prefix(2)) { n in
                        WRow(symbol: n.symbol, title: n.title, sub: n.time, tint: GlassInk.amber)
                    }
                    ForEach(down.prefix(1)) { m in
                        WRow(symbol: "exclamationmark.triangle", title: "\(m.id) is offline", tint: GlassInk.amber)
                    }
                    ForEach(h.running.prefix(2)) { r in
                        WRow(symbol: "sparkles", title: r.name, sub: "Running, \(r.minutes) min", tint: GlassInk.green)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: Citadel board (sample world only)

struct BoardBody: View {
    let board: HomeSnapshot.Board
    let size: WidgetSize

    var body: some View {
        let cols: [(String, Int)] = [
            ("To do", board.todo), ("Doing", board.doing), ("Review", board.review), ("Done", board.done),
        ]
        let peak = Double(max(cols.map(\.1).max() ?? 1, 1))
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WHead("list.bullet.rectangle", "Board")
                WFigure(value: Double(board.doing), caption: "in progress")
            case .m:
                WHead("list.bullet.rectangle", "Board")
                WStats(items: [
                    .init(id: "To do", value: "\(board.todo)"), .init(id: "Doing", value: "\(board.doing)"),
                    .init(id: "Done", value: "\(board.done)"),
                ])
            case .w:
                WHead("list.bullet.rectangle", "Board")
                WStats(items: cols.map { .init(id: $0.0, value: "\($0.1)", bar: Double($0.1) / peak) })
            case .l:
                WHead("list.bullet.rectangle", "Board")
                ForEach(cols, id: \.0) { c in WBarRow(label: c.0, value: "\(c.1)", fill: Double(c.1) / peak) }
                if board.blocked > 0 { WCaption("\(board.blocked) blocked") }
                Spacer(minLength: 0)
            }
        }
    }
}
