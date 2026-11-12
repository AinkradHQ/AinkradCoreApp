import CoreUI
import SwiftUI

/// Allow and Deny on a waiting item, from the actions the item carries (the primary one is blue).
private struct WActions: View {
    let item: BellItem
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(item.actions.sorted { $0.primary && !$1.primary }) { a in
                Button(a.label == "Approve" ? "Allow" : a.label) { a.run() }
                    .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary, size: .small))
            }
        }
    }
}

struct NeedsBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let need = shell.bell.items.filter(\.needsPerson)
        let badge: StateBadge? =
            need.isEmpty ? nil : StateBadge("\(need.count) waiting", tone: .warn, symbol: "hand.raised")
        VStack(alignment: .leading, spacing: Space.s2) {
            if need.isEmpty {
                WHead("bell", "Needs you")
                WEmpty(symbol: "checkmark.circle", text: "Nothing needs you")
            } else {
                switch size {
                case .s:
                    WHead("bell", "Needs you")
                    WFigure(value: Double(need.count), caption: "waiting for you")
                    Spacer(minLength: 0)
                    if let t = need.first?.time { WCaption("Oldest: \(t)") }
                case .m:
                    WHead("bell", "Needs you") { badge }
                    ForEach(need.prefix(2)) { n in row(n) }
                case .l:
                    WHead("bell", "Needs you") { badge }
                    ForEach(need.prefix(3)) { n in card(n) }
                    Spacer(minLength: 0)
                case .x:
                    WHead("bell", "Needs you") { badge }
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(spacing: Space.s2) { ForEach(need.prefix(3)) { n in card(n) } }
                        WSub {
                            WCaption("What it asks")
                            if let first = need.first {
                                Text(first.title).coreFont(size: MacTextSize.body, weight: .semibold)
                                    .foregroundStyle(WidgetInk.primary)
                                if let s = first.sub { WCaption(s) }
                            }
                        }
                    }
                }
            }
        }
        .animation(Motion.calm(.smooth(duration: 0.4), reduce), value: need.map(\.id))
    }

    private func row(_ n: BellItem) -> some View {
        Button {
            shell.bellOpen = true
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: n.symbol).foregroundStyle(GlassInk.amber).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(n.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    if let s = n.sub { WCaption(s) }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(WidgetInk.primary)
            .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
            .background(WidgetInk.well, in: coreShape(Radius.control + 2))
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain).newRow(reduce)
    }

    private func card(_ n: BellItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(n.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s2)
                if let t = n.time { WCaption(t) }
            }
            if let s = n.sub { WCaption(s) }
            WActions(item: n)
        }
        .foregroundStyle(WidgetInk.primary)
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(WidgetInk.well, in: coreShape(Radius.control + 4))
        .newRow(reduce)
    }
}

struct EventsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let ev = home.events
        VStack(alignment: .leading, spacing: Space.s2) {
            if ev.isEmpty {
                WHead("clock", "Recent events")
                WEmpty(symbol: "clock", text: "Nothing happened yet")
            } else {
                switch size {
                case .s:
                    WHead("clock", "Latest")
                    if let e = ev.first {
                        Spacer(minLength: 0)
                        Image(systemName: e.symbol).font(.system(size: 22)).foregroundStyle(WidgetInk.blue)
                            .accessibilityHidden(true)
                        Text(e.text).coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(WidgetInk.primary).lineLimit(2)
                        WCaption("\(when(e)) · \(e.source)")
                    }
                case .m:
                    WHead("clock", "Recent events")
                    list(ev.prefix(3))
                case .l:
                    WHead("clock", "Recent events")
                    list(ev.prefix(7))
                    Spacer(minLength: 0)
                case .x:
                    WHead("clock", "Recent events")
                    HStack(alignment: .top, spacing: Space.s5) {
                        list(ev.prefix(5))
                        list(ev.dropFirst(5).prefix(5))
                    }
                }
            }
        }
    }

    private func when(_ e: HomeSnapshot.Event) -> String { e.minutesAgo < 1 ? "now" : "\(e.minutesAgo) min" }

    private func list(_ ev: ArraySlice<HomeSnapshot.Event>) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(ev) { e in
                HStack(spacing: Space.s2) {
                    Image(systemName: e.symbol).foregroundStyle(WidgetInk.blue).frame(width: 16)
                        .accessibilityHidden(true)
                    Text(e.text).coreFont(size: MacTextSize.body).lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text(when(e)).coreFont(size: MacTextSize.meta).foregroundStyle(WidgetInk.secondary)
                        .monospacedDigit()
                }
                .foregroundStyle(WidgetInk.primary)
                .accessibilityElement(children: .combine).newRow(reduce)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Motion.calm(.smooth(duration: 0.4), reduce), value: ev.map(\.id))
    }
}

struct CoreBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize

    private var state: (word: String, tone: Tone, symbol: String) {
        switch shell.coreLink {
        case .live: ("OK", .done, "checkmark")
        case .connecting, .reconnecting: ("Reconnecting", .warn, "arrow.triangle.2.circlepath")
        case .offline: ("Offline", .fail, "exclamationmark.triangle")
        case .none: ("Not connected", .queue, "minus")
        }
    }

    var body: some View {
        let s = state
        let alarms = shell.bell.items.filter { $0.kind == .alarm }.count
        let h = shell.home
        let ratio = h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count)
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WHead("heart.text.square", "Core")
                HStack(spacing: Space.s2) {
                    Image(systemName: s.symbol).font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(s.tone == .done ? WidgetInk.green : GlassInk.amber)
                        .contentTransition(.symbolEffect(.replace)).accessibilityHidden(true)
                    Text(s.word).coreFont(size: 28, weight: .bold).foregroundStyle(WidgetInk.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                WCaption(alarms == 0 ? "No alarms" : "\(alarms) alarm" + (alarms == 1 ? "" : "s"))
            case .m:
                WHead("heart.text.square", "Core health") { StateBadge(s.word, tone: s.tone, symbol: s.symbol) }
                HStack(alignment: .top, spacing: Space.s5) {
                    stat("Certificate", h.health?.certificate ?? "Not reported yet")
                    stat("Backup", h.health?.backupAge(now: Date()) ?? "Not reported yet")
                    stat("Runners", "\(h.machinesOnline) of \(h.machines.count)")
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                WCaption(h.health.map { "Core \($0.version) · up \($0.uptime)" } ?? h.coreName)
            default:
                WHead("heart.text.square", "Core health") { StateBadge(s.word, tone: s.tone, symbol: s.symbol) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.tone == .done ? "Healthy" : s.word).coreFont(size: 34, weight: .bold)
                        .foregroundStyle(WidgetInk.primary)
                    WCaption(h.health.map { "\(h.coreName) · version \($0.version) · up \($0.uptime)" } ?? h.coreName)
                }
                if size == .x {
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(spacing: Space.s3) { bars(alarms: alarms, ratio: ratio, h: h) }
                        WSub {
                            WCaption("Answer time")
                            WGap(label: "Last hour")
                            WGap(label: "Errors today")
                        }
                    }
                } else {
                    bars(alarms: alarms, ratio: ratio, h: h)
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: shell.coreLink)
    }

    @ViewBuilder private func bars(alarms: Int, ratio: Double, h: HomeSnapshot) -> some View {
        WBarRow(
            label: "Runners online", value: "\(h.machinesOnline) of \(h.machines.count)", fill: ratio,
            tint: WidgetInk.green)
        WBarRow(
            label: "Alarms", value: alarms == 0 ? "None" : "\(alarms)", fill: min(Double(alarms) / 5, 1),
            tint: GlassInk.amber)
        if let c = h.health?.certificate, let health = h.health {
            WBarRow(
                label: "Certificate", value: c + (health.certDaysLeft ?? 0 > 0 ? " left" : ""),
                fill: health.certificateShare, tint: health.certificateLow ? GlassInk.amber : WidgetInk.green)
        } else {
            WGap(label: "Certificate")
        }
        if let b = h.health?.backup(now: Date()), let at = h.health?.lastBackupAt {
            WBarRow(
                label: "Backup", value: b, fill: max(0, 1 - Date().timeIntervalSince(at) / (2 * 86_400)),
                tint: WidgetInk.green)
        } else {
            WGap(label: "Backup")
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WCaption(k)
            Text(v).coreFont(size: 20, weight: .bold).foregroundStyle(WidgetInk.primary).lineLimit(1)
                .minimumScaleFactor(0.6).contentTransition(.numericText())
        }
    }
}

/// Three bars, not three rings: what waits for you, what runs, how many machines are up.
struct TodayBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize

    var body: some View {
        let h = shell.home
        let waiting = shell.waitingOnYou
        let rows: [(String, String, Double, Double, Color)] = [
            ("Waiting for you", "\(waiting)", Double(waiting), min(Double(waiting), 5) / 5, GlassInk.amber),
            (
                "AI sessions running", "\(h.runningAgents) of \(h.totalSlots)", Double(h.runningAgents),
                Double(h.runningAgents) / Double(max(h.totalSlots, 1)), WidgetInk.blue
            ),
            (
                "Machines online", "\(h.machinesOnline) of \(h.machines.count)", Double(h.machinesOnline),
                h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count), WidgetInk.green
            ),
        ]
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WHead("calendar", "Today")
                WFigure(value: Double(h.runningAgents), caption: "AI sessions running")
                Spacer(minLength: 0)
                Meter(value: rows[1].3)
            case .m:
                WHead("calendar", "Today")
                VStack(spacing: Space.s3) {
                    ForEach(rows, id: \.0) { r in WBarRow(label: r.0, value: r.1, fill: r.3, tint: r.4) }
                }
            default:
                WHead("calendar", "Today")
                if size == .x {
                    HStack(alignment: .top, spacing: Space.s4) {
                        big(rows)
                        WSub {
                            WCaption("Spend this week")
                            WColumns(values: Array(h.spendByDay.suffix(7)))
                            WCaption(
                                "Today \(h.spendToday.formatted(.currency(code: "USD")))")
                        }
                    }
                } else {
                    big(rows)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func big(_ rows: [(String, String, Double, Double, Color)]) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ForEach(rows, id: \.0) { r in
                VStack(alignment: .leading, spacing: Space.s1) {
                    WCaption(r.0)
                    RollingNumber(value: r.2, size: 28, ink: WidgetInk.primary)
                    Meter(value: r.3, tint: r.4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct BoardBody: View {
    let board: HomeSnapshot.Board
    let size: WidgetSize

    var body: some View {
        let total = Double(max(board.todo + board.doing + board.review + board.blocked + board.done, 1))
        let cols: [(String, Int, Color)] = [
            ("To do", board.todo, WidgetInk.secondary), ("In progress", board.doing, WidgetInk.blue),
            ("In review", board.review, WidgetInk.blue), ("Blocked", board.blocked, GlassInk.amber),
            ("Done", board.done, WidgetInk.green),
        ]
        VStack(alignment: .leading, spacing: Space.s2) {
            WHead("list.bullet.rectangle", size == .s ? "Board" : "Citadel board")
            switch size {
            case .s:
                WFigure(value: Double(board.doing), caption: "in progress")
                Spacer(minLength: 0)
                WCaption("\(board.todo) to do · \(board.done) done")
            case .m, .l:
                VStack(spacing: Space.s3) {
                    ForEach(size == .m ? Array(cols.prefix(3)) : cols, id: \.0) { c in
                        WBarRow(label: c.0, value: "\(c.1)", fill: Double(c.1) / total, tint: c.2)
                    }
                }
                Spacer(minLength: 0)
            case .x:
                HStack(alignment: .top, spacing: Space.s3) {
                    ForEach(cols, id: \.0) { c in
                        WSub {
                            WCaption(c.0)
                            RollingNumber(value: Double(c.1), size: 28, ink: WidgetInk.primary)
                            Meter(value: Double(c.1) / total, tint: c.2)
                        }
                    }
                }
            }
        }
    }
}
