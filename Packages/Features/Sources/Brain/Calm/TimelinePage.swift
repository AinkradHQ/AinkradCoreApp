import CoreUI
import SwiftUI

/// Timeline: the last six months as a grid (darker means more happened), then what happened day by day.
struct TimelinePage: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { brain.calm }

    private static let weeks = 26

    var body: some View {
        let s = calm.summary("timeline")
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "clock", title: "Timeline", count: s?.count, sub: "What happened, and when",
                today: s?.today ?? 0)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    grid.coreRise(shown, 0)
                    if calm.records.isEmpty {
                        Text(calm.loading ? "Reading…" : "Nothing yet. Brain notes what happened as you work.")
                            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).padding(Space.s3)
                    }
                    ForEach(Array(days.enumerated()), id: \.element.day) { i, d in
                        day(d).coreRise(shown, min(i + 1, 8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { shown = true }
        .accessibilityIdentifier("brain-timeline")
    }

    private var grid: some View {
        let cells = heatBuckets(
            calm.records.compactMap { SyncWords.date($0.createdAt) }, now: Date(), slice: 86_400,
            count: Self.weeks * 7)
        return VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "The last six months") { Text("Darker means more happened") }
            HStack(spacing: 3) {
                ForEach(0..<Self.weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let v = cells[w * 7 + d]
                            coreShape(2)
                                .fill(v <= 0 ? palette.track : GlassInk.accent(accent).opacity(0.3 + 0.7 * v))
                                .frame(height: 11)
                                .opacity(shown ? 1 : 0)
                                .animation(
                                    Motion.calm(Motion.out(Motion.reveal), reduce).delay(Double(w) * 0.012),
                                    value: shown)
                        }
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(calm.records.count) events in the last six months")
        }
        .padding(Space.s4).coreWell()
    }

    private struct Day {
        let day: String
        let date: Date
        let rows: [BrainAreaRecordWire]
    }

    /// Newest day first, each day's events newest first.
    private var days: [Day] {
        let cal = Calendar.current
        let dated = calm.records.compactMap { r in SyncWords.date(r.createdAt).map { (r, $0) } }
        let byDay = Dictionary(grouping: dated) { cal.startOfDay(for: $0.1) }
        return byDay.keys.sorted(by: >).prefix(30).map { d in
            Day(
                day: d.ISO8601Format(), date: d,
                rows: byDay[d, default: []].sorted { $0.1 > $1.1 }.map(\.0))
        }
    }

    private func day(_ d: Day) -> some View {
        let today = Calendar.current.isDateInToday(d.date)
        return HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(today ? "Today" : d.date.formatted(.dateTime.weekday(.wide)))
                    .coreFont(size: MacTextSize.body, weight: .semibold)
                Text(
                    today
                        ? d.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
                        : d.date.formatted(.dateTime.day().month(.abbreviated))
                )
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            .frame(width: Space.s8 * 4, alignment: .leading)
            VStack(spacing: Space.s2) {
                ForEach(d.rows) { r in
                    HStack(alignment: .top, spacing: Space.s4) {
                        VStack(spacing: 0) {
                            coreShape(2).fill(GlassInk.accent(accent)).frame(width: 8, height: 8).padding(
                                .top, Space.s4)
                            Rectangle().fill(palette.track).frame(width: 1).frame(maxHeight: .infinity)
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text(r.body).coreFont(size: MacTextSize.body).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Space.s2) {
                                Text(
                                    SyncWords.date(r.createdAt).map {
                                        $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                                    } ?? ""
                                )
                                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                                PlaceChip(name: r.roomName)
                            }
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coreWell()
                    }
                }
            }
        }
    }
}
