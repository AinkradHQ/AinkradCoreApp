// LoreWeek — the Today card at the top of the navigator: the open day's week as seven days, a mark under each day
// that has a note. A click opens that day; ⌘[ ⌘] move a day and the week follows.
import CoreKit
import CoreUI
import Foundation
import SwiftUI

@MainActor enum LoreWeek {
    /// The seven day keys (`YYYY-MM-DD`) of the week holding `key`, from the calendar's first weekday.
    static func days(of key: String, calendar: Calendar = .current) -> [String] {
        guard let d = LoreModel.date(key),
            let start = calendar.dateInterval(of: .weekOfYear, for: d)?.start
        else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map(LoreModel.key)
    }

    /// The days with a daily note in the list.
    static func written(_ notes: [LoreNote]) -> Set<String> {
        Set(notes.filter { $0.kind == "daily" && !$0.trashed }.compactMap(\.day))
    }

    /// Minutes to read `words` at 200 a minute; at least 1 when there is anything to read.
    static func readingMinutes(_ words: Int) -> Int { words == 0 ? 0 : max(1, (words + 199) / 200) }
}

/// Today, the month, and the week strip. A well: the one card in the navigator.
struct LoreWeekCard: View {
    let model: LoreModel
    var cursor = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false
    /// A new week arrives from the side it lies on (1: later, -1: earlier), then settles at 0.
    @State private var arrive: CGFloat = 0
    /// The open day's mark moves between days as one lit shape.
    @Namespace private var openDay

    var body: some View {
        let shown = model.day ?? model.todayKey
        let week = LoreWeek.days(of: shown)
        let written = LoreWeek.written(model.sideNotes)
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                Task { await model.openDay(model.todayKey) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("Today").coreFont(size: MacTextSize.title, weight: .semibold)
                    Spacer(minLength: Space.s2)
                    Text(month(shown)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(LoreKeys.today.help)
            .accessibilityLabel("Go to today")
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { key in
                    LoreDayCell(
                        key: key, today: key == model.todayKey, open: key == model.day,
                        written: written.contains(key), mark: openDay, glide: !reduce
                    ) { Task { await model.openDay(key) } }
                }
            }
            .offset(x: coreMove(reduce, arrive * Space.s6))
            .opacity(1 - abs(arrive) * 0.8)
            .animation(Motion.calm(.spring(duration: 0.32, bounce: 0), reduce), value: model.day)
            .onChange(of: week.first) { old, new in
                guard let old, let new, old != new else { return }
                arrive = new > old ? 1 : -1
                Task { @MainActor in withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { arrive = 0 } }
            }
        }
        .padding(Space.s3)
        .coreWell(radius: Radius.cardMac, active: cursor || hover)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week")
    }

    private func month(_ key: String) -> String {
        LoreModel.date(key)?.formatted(.dateTime.month(.wide).year()) ?? ""
    }
}

/// One day of the strip: the weekday's letter, the day's number, and a small mark when it has a note.
private struct LoreDayCell: View {
    let key: String
    let today: Bool
    let open: Bool
    let written: Bool
    let mark: Namespace.ID
    let glide: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hover = false

    var body: some View {
        let date = LoreModel.date(key) ?? Date()
        Button(action: action) {
            VStack(spacing: Space.s1) {
                Text(date.formatted(.dateTime.weekday(.narrow))).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
                Text(date.formatted(.dateTime.day())).coreFont(size: MacTextSize.body, weight: today ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(today ? palette.primary : GlassInk.primary)
                // The note mark: a small rounded square (no circles), kept in place when empty so nothing shifts.
                RoundedRectangle(cornerRadius: 1.5).fill(open ? palette.primary : GlassInk.secondary)
                    .frame(width: Space.s1, height: Space.s1).opacity(written ? 1 : 0)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.s2)
            .background(hover && !open ? GlassInk.well : .clear, in: coreShape(Radius.control))
            .background {
                if open {
                    // One id glides from day to day; under Reduce Motion each day has its own, so it fades.
                    coreShape(Radius.control).fill(GlassInk.wellHover)
                        .matchedGeometryEffect(id: glide ? "open" : key, in: mark)
                        .transition(.opacity)
                }
            }
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help(date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (written ? "" : ", no note yet"))
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(written ? "Has a note" : "No note")
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}
