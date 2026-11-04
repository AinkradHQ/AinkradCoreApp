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
                StatusDot(color: palette.tone(.run).ink)
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
                WidgetHead(title: "Today")
                WidgetBig(value: "\(waiting)", caption: "waiting", small: true)
                Spacer(minLength: 0)
                Text("\(h.runningAgents) running").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            case .m:
                WidgetHead(title: "Today", sub: "\(h.coreName) · \(h.machinesOnline) of \(h.machines.count) online")
                needsCard
                Spacer(minLength: 0)
            case .t:
                WidgetHead(title: "Today")
                WidgetLabel("Needs you")
                WidgetBig(value: "\(waiting)", caption: "waiting", small: true)
                WidgetLabel("Running")
                if h.running.isEmpty { WidgetCalm("None.") } else { RunRows(runs: Array(h.running.prefix(3))) }
                Spacer(minLength: 0)
            case .l, .x:
                WidgetHead(
                    title: "Today", sub: "\(h.coreName) · \(h.machinesOnline) of \(h.machines.count) machines online")
                needsSection
                WidgetLabel("Running")
                if h.running.isEmpty { WidgetCalm("No agents running.") } else { RunRows(runs: h.running) }
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
            WidgetCalm("Nothing is waiting on you.")
        }
    }

    @ViewBuilder private var needsSection: some View {
        WidgetLabel("Needs you")
        if let first = shell.bell.items.first(where: \.needsPerson) {
            WidgetCard(title: first.title, sub: "\(shell.bell.waiting) waiting on you · Review") {
                shell.bellOpen = true
            }
        } else {
            WidgetCalm("Nothing is waiting on you.")
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
                WidgetHead(title: "Needs you")
                WidgetBig(value: "\(need.count)", caption: "waiting")
                Spacer(minLength: 0)
            default:
                WidgetHead(title: "Needs you", sub: need.isEmpty ? nil : "\(need.count) waiting on you")
                if need.isEmpty { WidgetCalm("Nothing is waiting on you.") }
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
                WidgetHead(title: "Running")
                WidgetBig(value: "\(home.runningAgents)", caption: "agents")
            } else {
                WidgetHead(title: "Running agents", sub: "\(home.runningAgents) working now")
                if home.running.isEmpty { WidgetCalm("No agents running.") }
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
            if size != .s { WidgetHead(title: "Agent spend") }
            Spacer(minLength: 0)
            Text(home.spendToday, format: .currency(code: "USD"))
                .font(.system(size: size == .s ? 28 : 38, weight: .semibold, design: .monospaced)).lineLimit(1)
                .minimumScaleFactor(0.6)
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
            WidgetHead(title: "Machines", sub: "\(home.machinesOnline) of \(home.machines.count) online")
            ForEach(size == .m ? Array(home.machines.prefix(2)) : home.machines) { m in
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        StatusDot(color: m.online ? palette.tone(.run).ink : palette.tone(.queue).ink)
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
    var body: some View {
        let cols: [(String, Int, Tone?)] = [
            ("Todo", board.todo, nil), ("Doing", board.doing, nil), ("Review", board.review, nil),
            ("Blocked", board.blocked, .warn), ("Done", board.done, nil),
        ]
        let top = max(cols.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(title: "Citadel board")
            if size == .s {
                WidgetBig(value: "\(board.blocked)", caption: "blocked", small: true)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .bottom, spacing: Space.s2) {
                    ForEach(cols, id: \.0) { name, n, tone in
                        VStack(spacing: Space.s1) {
                            Text("\(n)").font(.system(size: MacTextSize.title, weight: .semibold))
                                .foregroundStyle(tone.map { palette.tone($0).ink } ?? palette.text)
                            coreShape(5).fill(palette.track)
                                .frame(height: (size == .l ? 150 : 34))
                                .overlay(alignment: .bottom) {
                                    GeometryReader { g in
                                        coreShape(5).fill(tone.map { palette.tone($0).ink } ?? palette.primary)
                                            .frame(height: max(6, g.size.height * CGFloat(n) / CGFloat(top)))
                                            .frame(maxHeight: .infinity, alignment: .bottom)
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
    }
}

struct EventsBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            WidgetHead(title: "Recent events")
            ForEach(Array(home.events.prefix(size == .m ? 2 : 8))) { e in
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: e.symbol).font(.system(size: MacTextSize.meta))
                        .frame(width: 22, height: 22).background(palette.uDim, in: coreShape(7))
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
            }
            Spacer(minLength: 0)
        }
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
            WidgetHead(title: "Core health", sub: size == .s ? nil : shell.home.coreName)
            HStack(spacing: Space.s2) {
                StatusDot(color: palette.tone(state.1).ink)
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
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            VStack(alignment: .leading, spacing: Space.s1) {
                if size == .l { WidgetHead(title: "Clock") }
                Spacer(minLength: 0)
                if size == .t {
                    Text(ctx.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted))).font(
                        .system(size: 62, weight: .semibold))
                    Text(ctx.date, format: .dateTime.minute(.twoDigits)).font(.system(size: 62, weight: .semibold))
                } else {
                    Text(ctx.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: size == .l ? 56 : size == .s ? 38 : 44, weight: .semibold)).lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(
                    ctx.date,
                    format: size == .s ? .dateTime.weekday(.wide) : .dateTime.weekday(.wide).month(.wide).day()
                )
                .foregroundStyle(palette.text2)
                if size == .l { Spacer(minLength: 0) }
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Quick actions. Buttons use the one CoreUI button (ghost: glass edge, `u-dim` on hover, 0.97 press), tiles stack the icon over
/// the label in the wide size and list in the large one; they rise in one after another when the widget arrives.
struct QuickBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var arrived = false

    private func forcedHover(_ i: Int) -> CoreInteraction? {
        #if DEBUG
        return shell.debugForceQuickHover && i == 1 ? .hover : nil
        #else
        return nil
        #endif
    }

    private func run(_ id: String, _ title: String) {
        if let e = shell.launcher.entry(id) {
            e.run()
        } else {
            shell.showToast("\(title) arrives with its feature module.")
        }
    }

    var body: some View {
        let tiles: [(String, String, String)] = [
            ("agents.new", "New agent session", "play"), ("new-terminal", "New terminal", "terminal"),
            ("add-device", "Add device", "plus"),
        ]
        let wide = size == .m
        VStack(alignment: .leading, spacing: Space.s2) {
            if !wide { WidgetHead(title: "Quick actions") }
            let cols = wide ? [GridItem(.flexible(), spacing: 6), GridItem(.flexible())] : [GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                    Button {
                        run(t.0, t.1)
                    } label: {
                        label(t.2, t.1, wide: wide)
                    }
                    .buttonStyle(CoreButtonStyle(.secondary)).rise(arrived, i, reduce)
                    .environment(\.coreForcedInteraction, forcedHover(i))
                }
                Button {
                    shell.toggleLauncher()
                } label: {
                    label("magnifyingglass", "Launcher", wide: wide, key: "⌘K")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).rise(arrived, tiles.count, reduce)
            }
            if !wide { Spacer(minLength: 0) }
        }
        .frame(maxHeight: .infinity, alignment: wide ? .center : .top)
        .onAppear { arrived = true }
    }

    @ViewBuilder private func label(_ symbol: String, _ title: String, wide: Bool, key: String? = nil) -> some View {
        let icon = Image(systemName: symbol).font(.system(size: wide ? 14 : 13)).accessibilityHidden(true)
        let text = Text(title).font(.system(size: wide ? MacTextSize.meta : MacTextSize.body, weight: .medium))
            .lineLimit(1)
        if wide {
            VStack(spacing: 2) {
                icon
                HStack(spacing: Space.s1) {
                    text
                    if let key { Text(key).font(.system(size: MacTextSize.meta)).opacity(0.8) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        } else {
            HStack(spacing: Space.s2) {
                icon
                text
                if let key { CoreKeycap(key) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
        }
    }
}

extension View {
    /// `fx.stagger({ from: 'rise', gap: 40 })`: rises 10 pt and fades in, one after another. Reduce Motion: a 200 ms fade, no travel.
    func rise(_ shown: Bool, _ index: Int, _ reduce: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : coreMove(reduce, 10))
            .animation(
                (reduce ? Animation.easeOut(duration: 0.2) : Motion.out(Motion.move)).delay(
                    reduce ? 0 : Double(index) * 0.04),
                value: shown)
    }
}
