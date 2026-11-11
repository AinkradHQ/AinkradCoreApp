import Charts
import CoreUI
import SwiftUI

/// Building blocks of the macOS-style widgets (N9): a header with a blue symbol, a darker well for a chart or list, and
/// Swift Charts for columns and load lines. Bars and charts animate to new values; Reduce Motion cross-fades instead.
struct WHead<Trailing: View>: View {
    let symbol: String
    let title: String
    let trailing: Trailing
    init(_ symbol: String, _ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: Space.s1 + 2) {
            Image(systemName: symbol).foregroundStyle(WidgetInk.blue).accessibilityHidden(true)
            Text(title).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            trailing
        }
        .coreFont(size: MacTextSize.meta + 1, weight: .semibold).foregroundStyle(WidgetInk.secondary)
    }
}

extension WHead where Trailing == EmptyView {
    init(_ symbol: String, _ title: String) {
        self.symbol = symbol
        self.title = title
        self.trailing = EmptyView()
    }
}

/// A figure and the word under it: the number rolls to every new value.
struct WFigure: View {
    let value: Double
    var format: (Double) -> String = { String(Int($0)) }
    let caption: String
    var size: CGFloat = 38
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RollingNumber(value: value, format: format, size: size, ink: WidgetInk.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(caption).coreFont(size: MacTextSize.body).foregroundStyle(WidgetInk.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A recessed area inside a widget for a chart or a second list.
struct WSub<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WidgetInk.well, in: coreShape(14))
    }
}

struct WCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(WidgetInk.secondary).lineLimit(1)
    }
}

/// Nothing to show yet: a quiet symbol and one line.
struct WEmpty: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(WidgetInk.secondary)
            Text(text).coreFont(size: MacTextSize.body).foregroundStyle(WidgetInk.secondary).multilineTextAlignment(
                .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A figure the Core does not report yet, said as such.
struct WGap: View {
    let label: String
    var body: some View {
        HStack {
            Text(label).coreFont(size: MacTextSize.body, weight: .medium)
            Spacer(minLength: Space.s2)
            Text("Not reported yet").coreFont(size: MacTextSize.meta).foregroundStyle(WidgetInk.secondary)
        }
        .foregroundStyle(WidgetInk.primary)
        .accessibilityElement(children: .combine)
    }
}

/// One labelled bar: label and value on one line, the bar under it.
struct WBarRow: View {
    let label: String
    let value: String
    let fill: Double
    var tint: Color = WidgetInk.blue
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Text(label).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(value).coreFont(size: MacTextSize.meta).foregroundStyle(WidgetInk.secondary).monospacedDigit()
                    .lineLimit(1).contentTransition(.numericText())
            }
            .foregroundStyle(WidgetInk.primary)
            Meter(value: fill, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Columns, newest last and highlighted: a Swift Chart, so a changed value slides the column to its new height.
struct WColumns: View {
    let values: [Double]
    var labels: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        VStack(spacing: Space.s1) {
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                BarMark(x: .value("Day", i), y: .value("Amount", v), width: .ratio(0.72))
                    .foregroundStyle(i == values.count - 1 ? WidgetInk.blue : WidgetInk.blue.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartXScale(domain: -0.5...(Double(max(values.count, 1)) - 0.5))
            .chartYScale(domain: 0...max(values.max() ?? 1, 0.0001))
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .animation(Motion.calm(.smooth(duration: 0.4), reduce), value: values)
            if !labels.isEmpty {
                HStack {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                        Text(l).frame(maxWidth: .infinity)
                    }
                }
                .coreFont(size: 10).foregroundStyle(WidgetInk.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A load line over a soft area, 0...1, newest at the right.
struct WLine: View {
    let values: [Double]
    var tint: Color = WidgetInk.blue
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("Time", i), y: .value("Load", v))
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", i), y: .value("Load", v)).foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: 0...1).chartXAxis(.hidden).chartYAxis(.hidden)
        .animation(Motion.calm(.smooth(duration: 0.4), reduce), value: values)
        .accessibilityHidden(true)
    }
}

extension View {
    /// New rows slide in from the top with a fade; under Reduce Motion they only fade.
    func newRow(_ reduce: Bool) -> some View {
        transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
}

extension HomeSnapshot {
    /// Spend per day from cost events, oldest first, the last entry being `now`'s day. Events older than `days` are ignored.
    public static func spendDays(
        _ events: [(at: Date, micros: Int64)], now: Date, days: Int = 30, calendar: Calendar = .current
    ) -> [Double] {
        let today = calendar.startOfDay(for: now)
        var out = [Double](repeating: 0, count: days)
        for e in events {
            let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.at), to: today).day ?? Int.max
            if d >= 0, d < days { out[days - 1 - d] += Double(e.micros) / 1_000_000 }
        }
        return out
    }

    public static func monthSpend(
        _ events: [(at: Date, micros: Int64)], now: Date, calendar: Calendar = .current
    ) -> Double {
        events.filter { calendar.isDate($0.at, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + Double($1.micros) / 1_000_000 }
    }

    enum RunnerState { case online, busy, offline }
    static func state(_ m: Machine) -> RunnerState {
        !m.online ? .offline : (m.slots > 0 && m.used >= m.slots ? .busy : .online)
    }
}

/// A runner's state as a badge: symbol and word, never colour alone.
struct WRunnerBadge: View {
    let machine: HomeSnapshot.Machine
    var body: some View {
        switch HomeSnapshot.state(machine) {
        case .online: StateBadge("Online", tone: .done, symbol: "checkmark")
        case .busy: StateBadge("Busy", tone: .warn, symbol: "gauge.with.dots.needle.67percent")
        case .offline: StateBadge("Offline", tone: .queue, symbol: "moon.zzz")
        }
    }
}
