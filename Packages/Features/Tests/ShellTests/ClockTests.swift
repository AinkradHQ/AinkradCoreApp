import Foundation
import Testing

@testable import Shell

@MainActor
struct ClockTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 10:09:37.4 UTC.
    private let at = Date(timeIntervalSince1970: 1_700_000_000 - 1_700_000_000.truncatingRemainder(dividingBy: 86_400))
        .addingTimeInterval(10 * 3600 + 9 * 60 + 37.4)

    @Test func reduceMotionTurnsSmoothIntoTicking() {
        #expect(SecondHand.smooth.shown(reduceMotion: false) == .smooth)
        #expect(SecondHand.smooth.shown(reduceMotion: true) == .ticking)
        #expect(SecondHand.smooth.shown(reduceMotion: false, live: false) == .ticking)
        #expect(SecondHand.ticking.shown(reduceMotion: false) == .ticking)
        #expect(SecondHand.off.shown(reduceMotion: true) == .off)
    }

    @Test func handAngles() {
        let smooth = ClockFace.angles(at, calendar: utc, hand: .smooth)
        #expect(abs(smooth.hour - (10 + 9.0 / 60) * 30) < 0.001)
        #expect(abs(smooth.second - 37.4 * 6) < 0.01)
        #expect(abs(smooth.minute - (9 + 37.4 / 60) * 6) < 0.01)
        let tick = ClockFace.angles(at, calendar: utc, hand: .ticking)
        #expect(tick.second == 37 * 6)
        // With the second hand off, the minute hand moves once a minute.
        #expect(ClockFace.angles(at, calendar: utc, hand: .off).minute == 9 * 6)
    }

    @Test func timeText() {
        let t = ClockFace.time(at, calendar: utc, h24: true)
        #expect(t.hours == "10" && t.minutes == "09" && t.seconds == "37")
        let early = ClockFace.time(at.addingTimeInterval(-3600), calendar: utc, h24: true)
        #expect(early.hours == "09")
        let pm = ClockFace.time(at.addingTimeInterval(4 * 3600), calendar: utc, h24: false)
        #expect(pm.hours == "2")
        #expect(ClockFace.time(at.addingTimeInterval(-10 * 3600), calendar: utc, h24: false).hours == "12")
    }

    @Test func placesAndCities() {
        #expect(ClockFace.city(TimeZone(identifier: "Africa/Cairo")!) == "Cairo")
        #expect(ClockFace.city(TimeZone(identifier: "America/New_York")!) == "New York")
        let cairo = ClockFace.places(home: TimeZone(identifier: "Africa/Cairo")!)
        #expect(cairo.map(\.name) == ["Cairo", "UTC"] && cairo[0].note == "home")
        #expect(ClockFace.places(home: TimeZone(identifier: "UTC")!).count == 1)
    }

    @Test func prefsPersist() throws {
        let name = "test.clock.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let p = ClockPrefs(defaults: d)
        #expect(p.secondHand == .smooth && !p.showsSeconds)
        p.secondHand = .off
        p.showsSeconds = true
        let back = ClockPrefs(defaults: d)
        #expect(back.secondHand == .off && back.showsSeconds)
    }

    @Test func galleryPutsTheClocksFirstAndListsEveryWidget() {
        #expect(Array(WidgetGallery.order.prefix(2)) == [.digital, .clock])
        #expect(Set(WidgetGallery.order) == Set(WidgetKind.allCases))
        #expect(WidgetKind.clock.title == "Analog clock" && WidgetKind.digital.title == "Digital clock")
    }

    @Test func minuteTicksLandOnTheMinute() {
        let d = Date(timeIntervalSinceReferenceDate: 3 * 3600 + 7 * 60 + 41.5)
        #expect(HomeSchedule.boundary(d, 60).timeIntervalSinceReferenceDate == 3 * 3600 + 7 * 60)
        #expect(HomeSchedule.boundary(d, 1).timeIntervalSinceReferenceDate == 3 * 3600 + 7 * 60 + 41)
        let next = HomeSchedule(seconds: 60, live: true).entries(from: d, mode: .normal).prefix(2).map { $0 }
        let minute: TimeInterval = 3 * 3600 + 7 * 60
        #expect(next.map(\.timeIntervalSinceReferenceDate) == [minute, minute + 60])
    }
}
