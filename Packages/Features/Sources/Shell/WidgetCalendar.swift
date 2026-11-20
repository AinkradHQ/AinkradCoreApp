import CoreUI
import EventKit
import Foundation
import SwiftUI

/// Your next events from the Mac's calendars (EventKit). The permission is asked when the widget first shows on Home,
/// never before: the gallery preview uses made-up events.
@MainActor @Observable
public final class CalendarProvider {
    public static let shared = CalendarProvider()
    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let start: Date
        public let allDay: Bool
    }
    public enum State: Equatable {
        case idle, denied
        case ready([Item])
    }
    public private(set) var state: State = .idle
    private let store = EKEventStore()

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// The next event today or later, when Calendar is already allowed.
    public var next: Item? {
        guard case .ready(let items) = state else { return nil }
        return items.first { $0.start >= Date() }
    }

    /// Reads the calendar only if it is already allowed: never asks. For widgets that merely show the next event.
    public func peek() {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { reload() }
    }

    public func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: reload()
        case .notDetermined:
            Task {
                let ok = (try? await store.requestFullAccessToEvents()) ?? false
                if ok { reload() } else { state = .denied }
            }
        default: state = .denied
        }
    }

    private func reload() {
        let from = Calendar.current.startOfDay(for: Date())
        guard let to = Calendar.current.date(byAdding: .day, value: 32, to: from) else { return }
        let found = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
        state = .ready(
            found.sorted { $0.startDate < $1.startDate }.map {
                Item(
                    id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate,
                    allDay: $0.isAllDay)
            })
    }
}

struct CalendarBody: View {
    @Environment(\.coreAccent) private var paneAccent
    let size: WidgetSize
    @Environment(\.widgetPreview) private var preview
    @State private var picked: Date?
    private let provider = CalendarProvider.shared

    private var sample: [CalendarProvider.Item] {
        let d = Calendar.current.startOfDay(for: Date())
        return [(10.5, "Design review"), (13, "Lunch with Sam"), (16, "Plan the release")].map { h, t in
            .init(id: t, title: t, start: d.addingTimeInterval(h * 3600), allDay: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if preview {
                content(sample)
            } else {
                switch provider.state {
                case .ready(let items): content(items)
                case .denied:
                    WHead("calendar", "Calendar")
                    WEmpty(
                        symbol: "calendar.badge.exclamationmark",
                        text: "Allow calendars for Ainkrad in System Settings, Privacy")
                case .idle:
                    WHead("calendar", "Calendar")
                    WEmpty(symbol: "calendar", text: "Reading your calendar")
                }
            }
        }
        .task { if !preview { provider.start() } }
    }

    private func on(_ items: [CalendarProvider.Item], _ day: Date) -> [CalendarProvider.Item] {
        items.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private func row(_ e: CalendarProvider.Item) -> some View {
        HStack(spacing: Space.s3) {
            Text(e.allDay ? "All day" : e.start.formatted(.dateTime.hour().minute()))
                .coreFont(size: MacTextSize.meta, weight: .medium).monospacedDigit()
                .foregroundStyle(GlassInk.accent(paneAccent)).frame(width: 52, alignment: .leading)
            Text(e.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(GlassInk.primary).accessibilityElement(children: .combine)
    }

    private func list(_ es: [CalendarProvider.Item], _ n: Int, empty: String = "Nothing today") -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if es.isEmpty { WCaption(empty) }
            ForEach(es.prefix(n)) { row($0) }
        }
    }

    /// Seven days from Monday of this week; the picked day shows its events below.
    private func week(_ items: [CalendarProvider.Item]) -> some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let today = cal.startOfDay(for: Date())
        let sel = picked ?? today
        return HStack(spacing: Space.s1) {
            ForEach(0..<7, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: start) ?? start
                Button {
                    picked = d
                } label: {
                    VStack(spacing: 0) {
                        WCaption(d.formatted(.dateTime.weekday(.abbreviated)))
                        Text(d.formatted(.dateTime.day())).coreFont(size: MacTextSize.body, weight: .semibold)
                            .foregroundStyle(
                                cal.isDate(d, inSameDayAs: sel) ? GlassInk.accent(paneAccent) : GlassInk.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        cal.isDate(d, inSameDayAs: sel) ? GlassInk.wellEdge : .clear, in: coreShape(Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month()))
                .overlay(alignment: .bottom) {
                    if !on(items, d).isEmpty {
                        coreShape(1.5).fill(GlassInk.accent(paneAccent)).frame(width: 12, height: 3)
                    }
                }
            }
        }
    }

    /// The month as weeks of days; a day with an event carries a small mark.
    private func month(_ items: [CalendarProvider.Item]) -> some View {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 2) {
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 18) }
            ForEach(1...n, id: \.self) { day in
                let d = cal.date(byAdding: .day, value: day - 1, to: first) ?? first
                let today = cal.isDateInToday(d)
                Text("\(day)").coreFont(size: MacTextSize.meta, weight: today ? .bold : .regular).monospacedDigit()
                    .foregroundStyle(today ? GlassInk.accent(paneAccent) : GlassInk.primary)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .overlay(alignment: .bottom) {
                        if !on(items, d).isEmpty {
                            coreShape(1).fill(GlassInk.accent(paneAccent)).frame(width: 8, height: 2)
                        }
                    }
                    .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month()))
            }
        }
    }

    @ViewBuilder private func content(_ items: [CalendarProvider.Item]) -> some View {
        let today = on(items, Date())
        let upcoming = items.filter { $0.start >= Date() || $0.allDay }
        switch size {
        case .s:
            Spacer(minLength: 0)
            WCaption(Date().formatted(.dateTime.weekday(.wide)))
            Text(Date().formatted(.dateTime.day())).font(.system(size: 38, weight: .semibold))
                .foregroundStyle(GlassInk.primary)
            WCaption(
                upcoming.first.map { "\($0.title), \($0.start.formatted(.dateTime.hour().minute()))" } ?? "Nothing next"
            )
        case .m:
            WHead("calendar", "Calendar")
            list(upcoming, 3, empty: "Nothing coming up")
        case .w:
            WHead("calendar", "Calendar") { WCaption(today.isEmpty ? "Nothing today" : "\(today.count) today") }
            week(items)
            list(on(items, picked ?? Date()), 2)
        case .l:
            WHead("calendar", Date().formatted(.dateTime.month(.wide)))
            month(items)
            list(upcoming, 3, empty: "Nothing coming up")
            Spacer(minLength: 0)
        }
    }
}
