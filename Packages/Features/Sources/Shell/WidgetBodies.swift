import CoreUI
import SwiftUI

/// The content of each widget at each macOS size (N9): small, medium, large and extra large each have their own layout with
/// more data, not the same layout with more room. A header with a blue symbol, one large figure, bars and Swift Charts; no
/// rings. What the Core does not report is said as "Not reported yet".
struct WidgetBody: View {
    let kind: WidgetKind
    let size: WidgetSize
    @Bindable var shell: ShellModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .today: TodayBody(shell: shell, size: size)
        case .needs: NeedsBody(shell: shell, size: size)
        case .running: RunningBody(shell: shell, size: size)
        case .spend: SpendBody(home: shell.home, size: size)
        case .machines: MachinesBody(home: shell.home, size: size)
        case .board: BoardBody(board: shell.home.board, size: size)
        case .events: EventsBody(home: shell.home, size: size)
        case .core: CoreBody(shell: shell, size: size)
        case .quick: QuickBody(shell: shell, size: size)
        case .clock: AnalogClockBody(size: size)
        case .digital: DigitalClockBody(size: size)
        }
    }
}

extension HomeSnapshot {
    var totalSlots: Int { machines.reduce(0) { $0 + $1.slots } }
}

/// One running agent: its name, how long, and a bar for the time (full at an hour).
struct WRunRow: View {
    let run: HomeSnapshot.Run
    var showTool = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Text(run.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s2)
                Text((showTool ? "\(run.tool) · " : "") + "\(run.minutes) min").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).monospacedDigit().lineLimit(1)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(GlassInk.primary)
            CoreMeter(min(Double(run.minutes) / 60, 1), label: "\(run.minutes) minutes")
        }
        .accessibilityElement(children: .combine)
    }
}

struct RunningBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let runs = shell.home.running
        let waiting = shell.waitingOnYou
        let needs: StateBadge? =
            waiting > 0 ? StateBadge("\(waiting) needs you", tone: .warn, symbol: "hand.raised") : nil
        VStack(alignment: .leading, spacing: Space.s2) {
            if runs.isEmpty {
                WHead("text.cursor", "AI sessions")
                WEmpty(symbol: "sparkles", text: "No AI sessions running")
            } else {
                switch size {
                case .s:
                    WHead("text.cursor", "AI sessions")
                    WFigure(value: Double(runs.count), caption: "running")
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s1) {
                        ForEach(runs.prefix(4)) { r in
                            CoreMeter(min(Double(r.minutes) / 60, 1), label: r.name).frame(maxWidth: .infinity)
                        }
                    }
                case .m:
                    WHead("text.cursor", "Running AI sessions") { needs }
                    HStack(alignment: .top, spacing: Space.s4) {
                        WFigure(value: Double(runs.count), caption: "running now").frame(width: 100)
                        list(runs.prefix(2), tool: false)
                    }
                case .l, .t:
                    WHead("text.cursor", "Running AI sessions") { needs }
                    WFigure(value: Double(runs.count), caption: "running")
                    list(runs.prefix(5), tool: true)
                    Spacer(minLength: 0)
                case .x:
                    WHead("text.cursor", "Running AI sessions")
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            HStack {
                                WFigure(value: Double(runs.count), caption: "running")
                                Spacer(minLength: 0)
                                needs
                            }
                            list(runs.prefix(5), tool: true)
                            Spacer(minLength: 0)
                        }
                        WSub {
                            WCaption("Work in the last 12 hours")
                            WGap(label: "Finished")
                            WGap(label: "Tokens")
                        }
                    }
                }
            }
        }
    }

    private func list(_ runs: ArraySlice<HomeSnapshot.Run>, tool: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(runs) { r in WRunRow(run: r, showTool: tool).newRow(reduce) }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: runs.map(\.id))
    }
}

struct SpendBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.corePalette) private var palette

    private var money: (Double) -> String { { $0.formatted(.currency(code: "USD")) } }
    private var week: [Double] { Array(home.spendByDay.suffix(7)) }
    private var weekLabels: [String] {
        let cal = Calendar.current
        return (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            return String(d.formatted(.dateTime.weekday(.narrow)))
        }
    }
    private var tightest: String { "\(Int((home.monthTokensUsed * 100).rounded()))% of the tightest limit" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if home.monthSpend == 0 && home.spendToday == 0 && week.allSatisfy({ $0 == 0 }) {
                WHead("dollarsign", "Spend")
                WEmpty(symbol: "dollarsign", text: "No spend yet this month")
            } else {
                switch size {
                case .s:
                    WHead("dollarsign", "Spend")
                    WFigure(value: home.monthSpend, format: money, caption: "this month", size: 28)
                    Spacer(minLength: 0)
                    CoreMeter(home.monthTokensUsed, label: "Tokens used this month")
                    WCaption(tightest)
                case .m:
                    WHead("dollarsign", "AI spend")
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            WFigure(value: home.monthSpend, format: money, caption: "this month", size: 28)
                            CoreMeter(home.monthTokensUsed, label: "Tokens used this month")
                        }
                        .frame(width: 130)
                        WColumns(values: week, labels: weekLabels)
                    }
                case .l, .t:
                    WHead("dollarsign", "AI spend")
                    HStack(alignment: .firstTextBaseline) {
                        WFigure(value: home.monthSpend, format: money, caption: "this month", size: 28)
                        Spacer(minLength: 0)
                    }
                    CoreMeter(home.monthTokensUsed, label: "Tokens used this month")
                    WCaption(tightest)
                    WSub {
                        WCaption("Last 7 days")
                        WColumns(values: week, labels: weekLabels)
                    }
                    WGap(label: "Spend by account")
                case .x:
                    WHead("dollarsign", "AI spend")
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            WFigure(value: home.monthSpend, format: money, caption: "this month", size: 28)
                            CoreMeter(home.monthTokensUsed, label: "Tokens used this month")
                            WCaption(tightest)
                            WBarRow(label: "Today", value: money(home.spendToday), fill: today)
                            WGap(label: "Spend by account")
                            Spacer(minLength: 0)
                        }
                        WSub {
                            WCaption("Last 30 days")
                            WColumns(values: home.spendByDay)
                            if let (i, v) = busiest { WCaption("Busiest day: \(day(i)) · \(money(v))") }
                        }
                    }
                }
            }
        }
    }

    private var today: Double {
        let peak = home.spendByDay.max() ?? 0
        return peak > 0 ? min(home.spendToday / peak, 1) : 0
    }
    private var busiest: (Int, Double)? {
        guard let m = home.spendByDay.enumerated().max(by: { $0.element < $1.element }), m.element > 0 else {
            return nil
        }
        return (m.offset, m.element)
    }
    private func day(_ i: Int) -> String {
        let back = home.spendByDay.count - 1 - i
        let d = Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date()
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// One runner: its name, state, agents in use, a bar for the slots and its load line.
struct WMachineRow: View {
    let machine: HomeSnapshot.Machine
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: machine.os.hasPrefix("macOS") ? "laptopcomputer" : "server.rack")
                    .foregroundStyle(GlassInk.blue).accessibilityHidden(true)
                Text(machine.id).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                WRunnerBadge(machine: machine)
                Spacer(minLength: Space.s2)
                Text("\(machine.used) of \(machine.slots) AI sessions").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(GlassInk.primary)
            HStack(spacing: Space.s3) {
                CoreMeter(
                    machine.slots > 0 ? Double(machine.used) / Double(machine.slots) : 0,
                    low: machine.used >= machine.slots && machine.slots > 0, label: "AI session slots in use")
                if machine.load.count > 1 {
                    WLine(values: machine.load).frame(width: 80, height: 22)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MachinesBody: View {
    let home: HomeSnapshot
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let ms = home.machines
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
                        Text("of \(ms.count)").coreFont(size: 18, weight: .semibold).foregroundStyle(
                            GlassInk.secondary)
                    }
                    WCaption("online")
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s1) {
                        ForEach(ms.prefix(6)) { m in
                            coreShape(3).fill(tint(m)).frame(height: 6).frame(maxWidth: .infinity)
                        }
                    }
                case .m:
                    WHead("server.rack", "Machines") { WCaption("\(home.machinesOnline) of \(ms.count) online") }
                    rows(ms.prefix(2))
                case .l, .t:
                    WHead("server.rack", "Machines") { WCaption("\(home.machinesOnline) of \(ms.count) online") }
                    rows(ms.prefix(4))
                    Spacer(minLength: 0)
                case .x:
                    WHead("server.rack", "Machines") { WCaption("\(home.machinesOnline) of \(ms.count) online") }
                    HStack(alignment: .top, spacing: Space.s4) {
                        rows(ms.prefix(4))
                        WSub {
                            WCaption("Load, last hour")
                            ForEach(ms.filter { $0.load.count > 1 }.prefix(2)) { m in
                                WCaption(m.id)
                                WLine(values: m.load, tint: m.online ? GlassInk.blue : GlassInk.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tint(_ m: HomeSnapshot.Machine) -> Color {
        switch HomeSnapshot.state(m) {
        case .online: GlassInk.green
        case .busy: GlassInk.amber
        case .offline: GlassInk.track
        }
    }

    private func rows(_ ms: ArraySlice<HomeSnapshot.Machine>) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(ms) { m in WMachineRow(machine: m) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
