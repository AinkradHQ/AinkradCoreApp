import CoreUI
import SwiftUI

/// Activity (API minor 101): the last two weeks as a chart of what Brain learned and tidied, then everything it did, by
/// day, in plain words. An older Core keeps the event list it has.
struct BrainActivityPage: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.coreAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if brain.calm.days == nil && !brain.calm.v101 {
            // An older Core: its event list, which carries its own title.
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    RoomBar(model: brain)
                    if brain.isSample || brain.service?.servesChanges == true {
                        ActivityTab(model: brain)
                    } else {
                        BrainComingLater(title: "Activity")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            days
        }
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "doc.text", title: "Activity",
                sub: "Everything Brain did, in plain words. Nothing happens here that you can’t see.")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let d = brain.calm.days {
                        chart(Array(d.days.prefix(14).reversed())).coreRise(shown, 0)
                        ForEach(Array(d.days.filter { !$0.events.isEmpty }.enumerated()), id: \.element.id) { i, day in
                            log(day).coreRise(shown, min(i + 1, 8))
                        }
                        if d.days.allSatisfy(\.events.isEmpty) {
                            Text("Nothing in the last two weeks.").coreFont(size: MacTextSize.body)
                                .foregroundStyle(GlassInk.secondary)
                        }
                    } else {
                        Text("Reading…").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { shown = true }
        .task { await brain.calm.loadDays() }
        .accessibilityIdentifier("brain-activity")
    }

    private func chart(_ days: [ActivityDaysWire.Day]) -> some View {
        let top = Double(max(days.map { $0.learned + $0.tidied }.max() ?? 1, 1))
        return VStack(alignment: .leading, spacing: Space.s3) {
            BrainCardHead(title: "The last two weeks") {
                HStack(spacing: Space.s3) {
                    key("Learned", GlassInk.accent(accent))
                    key("Tidied", GlassInk.accent(accent).opacity(0.45))
                }
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    let last = i == days.count - 1
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        bar(d.learned, top, GlassInk.accent(accent), i)
                        bar(d.tidied, top, GlassInk.accent(accent).opacity(0.45), i)
                        Text(last ? "Today" : Self.weekday(d.day))
                            .coreFont(size: MacTextSize.meta, weight: last ? .semibold : .regular)
                            .foregroundStyle(last ? GlassInk.primary : GlassInk.secondary)
                            .padding(.top, Space.s1)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(d.learned.formatted()) learned, \(d.tidied.formatted()) tidied")
                }
            }
            .frame(height: Space.s8 * 4)
            .accessibilityElement()
            .accessibilityLabel(
                "Learned \(days.reduce(0) { $0 + $1.learned }) and tidied \(days.reduce(0) { $0 + $1.tidied }) in two weeks"
            )
        }
        .padding(Space.s4).coreWell()
    }

    private func bar(_ n: Int, _ top: Double, _ fill: Color, _ i: Int) -> some View {
        coreShape(3).fill(fill)
            .frame(height: max(3, (Space.s8 * 3 - Space.s2) * CGFloat(Double(n) / top) * (shown ? 1 : 0.1)))
            .animation(Motion.calm(Motion.out(Motion.move), reduce).delay(Double(i) * 0.03), value: shown)
    }

    private func key(_ s: String, _ c: Color) -> some View {
        HStack(spacing: Space.s1) {
            coreShape(2).fill(c).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(s)
        }
    }

    private func log(_ d: ActivityDaysWire.Day) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(Self.dayTitle(d.day)).coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(GlassInk.secondary).accessibilityAddTraits(.isHeader)
            ForEach(Array(d.events.enumerated()), id: \.offset) { _, e in
                let w = ActivityWords.line(e)
                LearnedLine(symbol: w.symbol, line: w.line, meta: w.meta, forget: nil)
            }
        }
    }

    static func date(_ day: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: day)
    }

    static func weekday(_ day: String) -> String { date(day)?.formatted(.dateTime.weekday(.abbreviated)) ?? "" }

    static func dayTitle(_ day: String) -> String {
        guard let d = date(day) else { return day }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// What Brain did, in a sentence a person reads: "Learned 38 new things from 4 places".
enum ActivityWords {
    static func line(_ e: ActivityDaysWire.Event) -> (symbol: String, line: String, meta: String) {
        let rooms = e.rooms.isEmpty ? "All places" : e.rooms.joined(separator: ", ")
        let took = e.tookS.map { " · took \($0 < 60 ? "\($0) s" : "\($0 / 60) min")" } ?? ""
        let n = e.count.formatted()
        switch e.kind {
        case "learned":
            let from = e.rooms.count > 1 ? " from \(BrainWords.plural(e.rooms.count, "place", "places"))" : ""
            return ("sparkles", "Learned \(n) new \(e.count == 1 ? "thing" : "things")\(from)", rooms)
        case "tidied":
            return ("arrow.clockwise", "Tidied \(n) \(e.count == 1 ? "note" : "notes") into Knowledge", rooms + took)
        case "merged":
            return ("square.on.square", "Merged \(n) \(e.count == 1 ? "thing" : "things") it already knew", "Knowledge")
        case "overview":
            return (
                "doc.text",
                e.count == 1 && e.rooms.count == 1
                    ? "Wrote a fresh overview of \(e.rooms[0])"
                    : "Wrote \(BrainWords.plural(e.count, "overview", "overviews"))",
                "Places"
            )
        case "asked": return ("tray", "Asked you about \(n) \(e.count == 1 ? "thing" : "things")", rooms)
        case "imported":
            return (
                "square.and.arrow.down", "Learned from the imported history",
                "\(n) \(e.count == 1 ? "conversation" : "conversations") from \(BrainWords.plural(max(e.rooms.count, 1), "place", "places"))"
            )
        default: return ("circle.dashed", "\(e.kind.capitalized) · \(n)", rooms)
        }
    }
}
