import CoreUI
import Foundation
import SwiftUI

// The pictures of the Activity app (11b): the Core's own last day on Ops, the week as an hour-by-hour heatmap and per-kind bars
// on Audit, and "Happening now" from the Core's event stream. Every motion here has a finished still state under Reduce
// Motion, and none follows the pointer.

// MARK: - what the pictures are made of, as pure values

enum ActivityKind: String, CaseIterable, Identifiable {
    case sessions, terminals, devices, secrets, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: "AI sessions"
        case .terminals: "Terminals"
        case .devices: "Devices"
        case .secrets: "Secrets"
        case .updates: "Updates"
        }
    }
    var symbol: String {
        switch self {
        case .sessions: "sparkles"
        case .terminals: "terminal"
        case .devices: "laptopcomputer"
        case .secrets: "lock"
        case .updates: "arrow.down.circle"
        }
    }
    /// The audit action prefix a tap filters the list by; nil when the Core has no single prefix for the kind.
    var prefix: String? {
        switch self {
        case .sessions: "agent."
        case .terminals: "terminal."
        case .devices: "device."
        case .secrets: "secret."
        case .updates: nil
        }
    }
}

enum ActivityStats {
    /// `Today`, `Yesterday`, then the weekday, for the stat day `i` (0 is today).
    static func dayLabel(_ date: String, index i: Int) -> String {
        if i == 0 { return "Today" }
        if i == 1 { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    /// Cells 0...1 for a day, scaled by the busiest hour of all the days.
    static func cells(_ days: [AuditDayStat]) -> [[Double]] {
        let top = Double(max(days.flatMap(\.hours).max() ?? 0, 1))
        return days.map { $0.hours.map { Double($0) / top } }
    }

    /// Oldest first, for a trend line.
    static func series(_ days: [AuditDayStat], _ value: (AuditDayStat) -> Int) -> [Double] {
        days.reversed().map { Double(value($0)) }
    }

    /// Bars for one kind across the week, oldest first, 0...1 by the busiest day of that kind.
    static func bars(_ days: [AuditDayStat], _ kind: ActivityKind) -> [Double] {
        let counts = days.reversed().map { $0.count(kind.rawValue) }
        let top = Double(max(counts.max() ?? 0, 1))
        return counts.map { Double($0) / top }
    }

    /// The Core's readings of one kind, oldest first, with no gaps.
    static func readings(_ points: [OpsPoint], _ pick: (OpsPoint) -> Double?) -> [Double] { points.compactMap(pick) }
}

/// A line the stream brings in, worded for the person.
struct LiveEvent: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String
    let at: Date
}

enum LiveWords {
    /// What an event kind means in plain words; nil for the kinds that are not "happening now" news.
    static func entry(_ kind: String) -> (symbol: String, text: String)? {
        switch kind {
        case "agent.created", "agent.session.started", "agent.started": ("sparkles", "An AI session started")
        case "agent.ended", "agent.session.ended": ("sparkles", "An AI session finished")
        case "agent.approval_requested": ("hand.raised", "An AI session is waiting for you")
        case "terminal.opened": ("terminal", "A terminal opened")
        case "terminal.closed", "terminal.exited": ("terminal", "A terminal closed")
        case "runner.connected": ("server.rack", "A runner came online")
        case "runner.disconnected": ("server.rack", "A runner went offline")
        case "device.enrolled": ("laptopcomputer.and.iphone", "A device joined your Core")
        case "alarm.raised": ("exclamationmark.triangle", "Your Core raised a warning")
        case "alarm.cleared": ("checkmark.circle", "A warning cleared")
        case "secret.revealed": ("eye", "A secret was shown")
        case "secret.exported": ("square.and.arrow.up", "Your secrets were exported")
        default: nil
        }
    }

    static let keep = 20
    static let fresh: TimeInterval = 300
}

// MARK: - motion

/// Draws a chart in from the left once. Still and complete under Reduce Motion.
struct ChartReveal: ViewModifier {
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().frame(width: reduce || drawn ? g.size.width : 0)
                }
            }
            .onAppear {
                guard !drawn, !reduce else { return }
                withAnimation(Motion.out(1.2)) { drawn = true }
            }
    }
}

extension View {
    func chartReveal() -> some View { modifier(ChartReveal()) }
}

// MARK: - Audit: the week by hour

struct AuditHeatmap: View {
    @Bindable var model: AuditModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let days = model.stats
        let cells = ActivityStats.cells(days)
        let hour = Calendar.current.component(.hour, from: Date())
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("This week, hour by hour").coreFont(size: MacTextSize.headline, weight: .semibold)
                Spacer(minLength: 0)
                Text("Busier is brighter").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            axis
            ForEach(Array(days.enumerated()), id: \.element.id) { r, day in
                Button {
                    model.selectedDay = r
                } label: {
                    HStack(spacing: Space.s3) {
                        Text(ActivityStats.dayLabel(day.date, index: r)).coreFont(
                            size: MacTextSize.meta, weight: r == model.selectedDay ? .semibold : .regular
                        )
                        .foregroundStyle(r == model.selectedDay ? palette.text : palette.text2)
                        .frame(width: Space.s8 * 2, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(0..<24, id: \.self) { c in
                                HeatCell(
                                    level: cells[r][c], future: r == 0 && c > hour, now: r == 0 && c == hour,
                                    delay: Double(c) * 0.016 + Double(r) * 0.04
                                )
                                .help(r == 0 && c > hour ? "Not yet" : "\(c):00 · \(day.hours[c]) actions")
                            }
                        }
                        Text("\(day.total)").coreFont(size: MacTextSize.meta).monospacedDigit()
                            .foregroundStyle(palette.text2).frame(width: Space.s8 + Space.s4, alignment: .trailing)
                    }
                    .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
                    .background(r == model.selectedDay ? palette.uDimHover : .clear, in: coreShape(Radius.control))
                    .contentShape(coreShape(Radius.control))
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.995, hoverFill: true))
                .accessibilityLabel(
                    "\(ActivityStats.dayLabel(day.date, index: r)), \(day.total) actions"
                )
                .accessibilityAddTraits(r == model.selectedDay ? .isSelected : [])
            }
        }
        .padding(Space.s3)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audit-heatmap")
    }

    private var axis: some View {
        HStack(spacing: Space.s3) {
            Color.clear.frame(width: Space.s8 * 2, height: 1)
            HStack {
                ForEach(["0:00", "6:00", "12:00", "18:00", "24:00"], id: \.self) { t in
                    Text(t)
                    if t != "24:00" { Spacer(minLength: 0) }
                }
            }
            Color.clear.frame(width: Space.s8 + Space.s4, height: 1)
        }
        .padding(.horizontal, Space.s2)
        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        .accessibilityHidden(true)
    }
}

private struct HeatCell: View {
    let level: Double
    let future: Bool
    let now: Bool
    let delay: Double
    @State private var shown = false
    @State private var breathe = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        coreShape(3)
            .fill(fill)
            .frame(maxWidth: .infinity).frame(height: Space.s5 - 2)
            .opacity(now && breathe && !reduce ? 0.45 : 1)
            .scaleEffect(shown || reduce ? 1 : 0.6)
            .opacity(shown || reduce ? 1 : 0)
            .onAppear {
                guard !reduce else { return }
                withAnimation(Motion.out(Motion.ui).delay(delay)) { shown = true }
                if now {
                    withAnimation(.easeInOut(duration: Motion.tick).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                }
            }
    }

    private var fill: Color {
        if future { return palette.track.opacity(0.4) }
        if now { return palette.text }
        return palette.primary.opacity(0.06 + 0.74 * level)
    }
}

// MARK: - Audit: by kind

struct AuditKindBars: View {
    @Bindable var model: AuditModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let days = model.stats
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("By kind, last \(days.count) days").coreFont(size: MacTextSize.headline, weight: .semibold)
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(Array(ActivityKind.allCases.enumerated()), id: \.element.id) { i, kind in
                    let on = kind.prefix != nil && model.filter.kind == kind.prefix
                    Button {
                        guard let p = kind.prefix else { return }
                        model.filter.kind = on ? "" : p
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            HStack(spacing: Space.s2) {
                                IconTile(kind.symbol, hue: GlassInk.blue, size: 24)
                                Text(kind.title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(days.reduce(0) { $0 + $1.count(kind.rawValue) })")
                                    .coreFont(size: MacTextSize.headline, weight: .semibold).monospacedDigit()
                            }
                            KindBarRow(
                                values: ActivityStats.bars(days, kind),
                                selected: days.count - 1 - model.selectedDay)
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? palette.uDimHover : GlassInk.well, in: coreShape(Radius.cardMac))
                        .contentShape(coreShape(Radius.cardMac))
                    }
                    .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, scale: 0.97, hoverFill: true))
                    .disabled(kind.prefix == nil)
                    .help(kind.prefix == nil ? kind.title : "Show only \(kind.title.lowercased())")
                    .modifier(RiseIn(index: i + 3))
                    .accessibilityLabel(
                        "\(kind.title), \(days.reduce(0) { $0 + $1.count(kind.rawValue) }) in \(days.count) days"
                    )
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("audit-kinds")
    }
}

private struct KindBarRow: View {
    let values: [Double]
    let selected: Int
    @State private var grown = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                coreShape(3).fill(i == selected ? palette.primary : palette.track)
                    .frame(maxWidth: .infinity).frame(height: max(3, 34 * v))
                    .scaleEffect(y: reduce || grown ? 1 : 0.05, anchor: .bottom)
                    .animation(
                        reduce ? nil : Motion.out(Motion.reveal).delay(Double(values.count - 1 - i) * 0.055),
                        value: grown)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .onAppear { grown = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Happening now

struct LiveNow: View {
    let events: [LiveEvent]
    @Environment(\.corePalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let fresh = events.filter { ctx.date.timeIntervalSince($0.at) < LiveWords.fresh }.prefix(4)
            if !fresh.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(Array(fresh.enumerated()), id: \.element.id) { i, e in
                        LiveRow(event: e, index: i, now: ctx.date)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct LiveRow: View {
    let event: LiveEvent
    let index: Int
    let now: Date
    @State private var up = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(event.symbol, hue: GlassInk.blue, size: 30)
                .offset(y: up && !reduce ? -2 : 0)
            Text(event.text).coreFont(size: MacTextSize.body, weight: .medium)
            Spacer(minLength: 0)
            Text(now.timeIntervalSince(event.at) < 15 ? "Just now" : AdminWords.time(event.at))
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.uDimHover, in: coreShape(Radius.cardMac))
        .modifier(RiseIn(index: index))
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true).delay(Double(index) * 1.4)) {
                up = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
