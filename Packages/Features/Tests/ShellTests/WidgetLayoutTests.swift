import Foundation
import Testing

@testable import Shell

struct WidgetLayoutTests {
    /// The Board widget is the sample world's (`CORE_DEMO=1`); these tests lay out the full set.
    init() { setenv("CORE_DEMO", "1", 1) }

    private func noOverlap(_ l: [WidgetItem]) -> Bool {
        for (i, a) in l.enumerated() {
            guard WidgetLayout.fits(a) else { return false }
            for b in l[(i + 1)...] where WidgetLayout.hit(a, b) { return false }
        }
        return true
    }

    @Test func standardLayoutIsValid() {
        let l = WidgetLayout.standard()
        #expect(l.items.count == 12)
        #expect(noOverlap(l.items))
    }

    @Test func movingPushesTheOthersAside() throws {
        var l = WidgetLayout.standard()
        let clock = try #require(l.items.first { $0.kind == .digital })
        let spend = try #require(l.items.first { $0.kind == .machines })
        let ok946 = l.move(clock.id, to: spend.x, spend.y)
        #expect(ok946)
        #expect(noOverlap(l.items))
        let moved = try #require(l.items.first { $0.id == clock.id })
        #expect(moved.x == spend.x && moved.y == spend.y)
        let pushed = try #require(l.items.first { $0.id == spend.id })
        #expect(pushed.x != spend.x || pushed.y != spend.y)
    }

    @Test func movingIsClampedToTheGrid() throws {
        var l = WidgetLayout.standard()
        let needs = try #require(l.items.first { $0.kind == .approvals })
        _ = l.move(needs.id, to: 99, 99)
        let t = try #require(l.items.first { $0.id == needs.id })
        #expect(t.x + t.size.cols <= WidgetLayout.cols && t.y + t.size.rows <= WidgetLayout.rows)
        #expect(noOverlap(l.items))
    }

    @Test func nudgeStopsAtTheEdge() throws {
        var l = WidgetLayout(items: [WidgetItem(kind: .clock, size: .s, x: 0, y: 0)])
        let id = l.items[0].id
        let ok6242 = l.nudge(id, dx: -1, dy: 0)
        #expect(!ok6242)
        let ok4790 = l.nudge(id, dx: 1, dy: 0)
        #expect(ok4790)
        #expect(l.items[0].x == 1)
    }

    @Test func resizeOnlyToSizesTheWidgetHas() throws {
        var l = WidgetLayout(items: [WidgetItem(kind: .clock, size: .m, x: 0, y: 0)])
        let id = l.items[0].id
        let ok6350 = l.resize(id, to: .x)
        #expect(!ok6350)
        let ok1198 = l.resize(id, to: .l)
        #expect(ok1198)
        #expect(l.items[0].size == .l)
    }

    @Test func resizeIsRefusedWhenThereIsNoRoom() {
        // A full desk of 1x1 widgets: growing one has nowhere to push the rest.
        var items: [WidgetItem] = []
        for y in stride(from: 0, to: WidgetLayout.rows, by: 2) {
            for x in stride(from: 0, to: WidgetLayout.cols, by: 2) {
                items.append(WidgetItem(kind: .clock, size: .s, x: x, y: y))
            }
        }
        var l = WidgetLayout(items: items)
        let before = l
        let ok96 = l.add(.clock, .s)
        #expect(ok96 == nil)
        let ok6402 = l.resize(items[0].id, to: .l)
        #expect(!ok6402)
        #expect(l == before)
    }

    @Test func addFindsTheFirstFreeCellOrASmallerSize() throws {
        var l = WidgetLayout.standard()
        let added = l.add(.core, .l)
        let a = try #require(added)
        #expect(noOverlap(l.items))
        #expect(a.size.area <= WidgetSize.l.area)
    }

    @Test func removeThenRestoreBringsItBack() throws {
        var l = WidgetLayout.standard()
        let board = try #require(l.items.first { $0.kind == .running })
        let removed = l.remove(board.id)
        let gone = try #require(removed)
        #expect(l.items.count == 11)
        let ok1904 = l.restore(gone)
        #expect(ok1904)
        #expect(l.items.contains { $0.id == board.id })
        #expect(noOverlap(l.items))
    }

    @Test func insertFromTheGalleryMakesRoom() throws {
        var l = WidgetLayout(items: [
            WidgetItem(kind: .clock, size: .s, x: 0, y: 0), WidgetItem(kind: .spend, size: .m, x: 4, y: 0),
        ])
        let n = WidgetItem(kind: .running, size: .l, x: 0, y: 0)
        let ok5535 = l.insert(n, at: 0, 0)
        #expect(ok5535)
        #expect(noOverlap(l.items))
        #expect(l.items.contains { $0.id == n.id && $0.x == 0 && $0.y == 0 })
    }

    @Test func savedLayoutRoundTripsAndDropsBadRows() throws {
        let l = WidgetLayout.standard()
        let data = try #require(l.encoded())
        let back = try #require(WidgetLayout.decoded(data))
        #expect(
            back.items.map { [$0.kind.rawValue, $0.size.rawValue, "\($0.x)", "\($0.y)"] }
                == l.items.map { [$0.kind.rawValue, $0.size.rawValue, "\($0.x)", "\($0.y)"] })
        let bad =
            #"{"v":3,"items":[{"t":"clock","s":"s","x":0,"y":0},{"t":"nope","s":"s","x":1,"y":0},{"t":"clock","s":"s","x":0,"y":0},{"t":"today","s":"x","x":15,"y":0},{"t":"quick","s":"zz","x":2,"y":0}]}"#
        let d = try #require(WidgetLayout.decoded(Data(bad.utf8)))
        #expect(d.items.count == 1)  // unknown kind, overlap, off-grid and a size the widget lacks are all dropped
        #expect(WidgetLayout.decoded(Data("{\"v\":5,\"items\":[]}".utf8)) == nil)
        #expect(WidgetLayout.decoded(Data("garbage".utf8)) == nil)
    }

    @Test func aSavedV1LayoutMovesToTheNewGrid() throws {
        // v1: an 8 x 5 grid with the removed tall size and the old extra large.
        let old =
            #"{"v":1,"items":[{"t":"today","s":"x","x":0,"y":0},{"t":"clock","s":"s","x":0,"y":3},{"t":"machines","s":"t","x":6,"y":0},{"t":"events","s":"l","x":6,"y":2},{"t":"quick","s":"m","x":0,"y":4}]}"#
        let l = try #require(WidgetLayout.decoded(Data(old.utf8)))
        #expect(l.items.count == 5)
        #expect(noOverlap(l.items))
        let today = try #require(l.items.first { $0.kind == .today })
        #expect(today.size == .l && today.x == 0 && today.y == 0)  // old extra large is large
        let machines = try #require(l.items.first { $0.kind == .machines })
        #expect(machines.size == .s && machines.x == 12)  // the tall size is gone: small
        #expect(WidgetSize.migrated("t") == .s && WidgetSize.migrated("m") == .m && WidgetSize.migrated("q") == nil)
        let events = try #require(l.items.first { $0.kind == .events })
        #expect(events.size == .l && events.y + events.size.rows <= WidgetLayout.rows)
    }

    private func onGreeting(_ i: WidgetItem) -> Bool {
        let r = WidgetLayout.reserved
        return i.x < r.x + r.cols && r.x < i.x + i.size.cols && i.y < r.y + r.rows && r.y < i.y + i.size.rows
    }

    @Test func theGridIs16By12AndTheBottomRowTakesAWidget() {
        #expect(WidgetLayout.cols == 16 && WidgetLayout.rows == 12)
        var l = WidgetLayout(items: [])
        let a = l.insert(WidgetItem(kind: .clock, size: .s, x: 0, y: 10), at: 0, 10)
        #expect(a && l.items[0].y == 10)
        #expect(DeskGrid.origin(0, 11).y + DeskGrid.frameSize(.s).height / 2 <= 900 - DeskGrid.bottom + 60)
        #expect(DeskGrid.origin(0, 10).y + DeskGrid.frameSize(.s).height <= 900 - DeskGrid.bottom + 0.001)
    }

    @Test func noWidgetCanCoverTheGreeting() throws {
        #expect(!WidgetLayout.standard().items.contains(where: onGreeting))
        #expect(!WidgetLayout.fits(WidgetItem(kind: .clock, size: .s, x: 4, y: 2)))
        #expect(!WidgetLayout.fits(WidgetItem(kind: .clock, size: .l, x: 6, y: 0)))
        #expect(WidgetLayout.fits(WidgetItem(kind: .clock, size: .m, x: 4, y: 4)))
        #expect(WidgetLayout.fits(WidgetItem(kind: .clock, size: .m, x: 4, y: 0)))
        // Moving, nudging, resizing, adding and dropping all stay off it.
        var l = WidgetLayout.standard()
        let needs = try #require(l.items.first { $0.kind == .needs })
        l.move(needs.id, to: 6, 2)
        #expect(!l.items.contains(where: onGreeting))
        let added = l.add(.clock, .s)
        let c = try #require(added)
        #expect(!onGreeting(c))
        var edge = WidgetLayout(items: [WidgetItem(kind: .clock, size: .s, x: 3, y: 2)])
        let nudged = edge.nudge(edge.items[0].id, dx: 1, dy: 0)
        #expect(!nudged)
        let ok = edge.resize(edge.items[0].id, to: .l)  // 4 x 4 at (3, 2) would cover it: it moves clear or is refused
        #expect(!ok || !edge.items.contains(where: onGreeting))
        var d = WidgetLayout(items: [])
        d.insert(WidgetItem(kind: .spend, size: .l, x: 5, y: 1), at: 5, 1)
        #expect(!d.items.contains(where: onGreeting))
        // Undo of a removal puts it back clear of the greeting too.
        var r = WidgetLayout.standard()
        let removed = r.remove(r.items[0].id)
        let gone = try #require(removed)
        r.restore(WidgetItem(id: gone.id, kind: gone.kind, size: gone.size, x: 5, y: 2))
        #expect(!r.items.contains(where: onGreeting))
    }

    @Test func aSavedV2LayoutMovesToTheNewGridKeepingEveryWidget() throws {
        // A 16 x 8 desk the person arranged: one widget sits where the greeting now is, one at the old bottom.
        let old =
            #"{"v":2,"items":[{"t":"clock","s":"s","x":0,"y":0},{"t":"spend","s":"l","x":6,"y":1},{"t":"core","s":"m","x":0,"y":6},{"t":"quick","s":"s","x":15,"y":7}]}"#
        let l = try #require(WidgetLayout.decoded(Data(old.utf8)))
        #expect(l.items.count == 4, "nothing is lost")
        #expect(noOverlap(l.items) && !l.items.contains(where: onGreeting))
        #expect(l.items.first { $0.kind == .clock }.map { $0.x == 0 && $0.y == 0 } == true)
        // The untouched old default becomes the new default; garbage-sized input never crashes.
        let std = WidgetLayout.standard()
        let was =
            #"{"v":2,"items":[{"t":"running","s":"m","x":0,"y":0},{"t":"spend","s":"l","x":4,"y":0},{"t":"machines","s":"m","x":8,"y":0},{"t":"digital","s":"s","x":12,"y":0},{"t":"quick","s":"s","x":14,"y":0},{"t":"needs","s":"m","x":0,"y":2},{"t":"events","s":"m","x":8,"y":2},{"t":"core","s":"m","x":12,"y":2},{"t":"board","s":"m","x":0,"y":4}]}"#
        let n = try #require(WidgetLayout.decoded(Data(was.utf8)))
        #expect(n.items.map(\.kind) == std.items.map(\.kind) && !n.items.contains(where: onGreeting))
        #expect(
            WidgetLayout.decoded(Data(#"{"v":2,"items":[{"t":"clock","s":"s","x":99,"y":-5}]}"#.utf8))?.items.count == 1
        )
    }

    @Test func thereAreFourSizesAndEveryWidgetHasAllOfThem() {
        #expect(WidgetSize.allCases.map(\.rawValue) == ["s", "m", "w", "l"])
        #expect(WidgetKind.allCases.allSatisfy { Set($0.sizes) == Set(WidgetSize.allCases) })
        #expect(WidgetSize.s.cols == 2 && WidgetSize.s.rows == 2 && WidgetSize.m.cols == 4 && WidgetSize.m.rows == 2)
        #expect(WidgetSize.w.cols == 8 && WidgetSize.w.rows == 2 && WidgetSize.l.cols == 4 && WidgetSize.l.rows == 4)
        #expect(WidgetSize.w.spoken == "Wide, 8 by 2")
        #expect(WidgetSize.allCases.map(\.short) == ["S", "M", "W", "L"])
    }

    @Test func aV3DeskKeepsItsPlaceWithTheTallAndExtraLargeSizesMigrated() throws {
        // The old tall becomes small; the old 8 x 4 extra large becomes the wide 8 x 2 in the same corner.
        let old =
            #"{"v":3,"items":[{"t":"digital","s":"t","x":0,"y":0},{"t":"spend","s":"x","x":8,"y":4}]}"#
        let l = try #require(WidgetLayout.decoded(Data(old.utf8)))
        #expect(l.items.first { $0.kind == .digital }?.size == .s)
        let spend = try #require(l.items.first { $0.kind == .spend })
        #expect(spend.size == .w && spend.x == 8 && spend.y == 4)
        #expect(WidgetSize.migrated("x", from: 1) == .l && WidgetSize.migrated("x", from: 3) == .w)
    }

    @Test func anUntouchedV3DeskBecomesTheNewDefault() throws {
        let was =
            #"{"v":3,"items":[{"t":"running","s":"m","x":0,"y":0},{"t":"machines","s":"m","x":4,"y":0},{"t":"events","s":"m","x":8,"y":0},{"t":"digital","s":"s","x":12,"y":0},{"t":"quick","s":"s","x":14,"y":0},{"t":"needs","s":"m","x":0,"y":2},{"t":"core","s":"m","x":12,"y":2},{"t":"spend","s":"l","x":12,"y":4}]}"#
        let got = try #require(WidgetLayout.decoded(Data(was.utf8)))
        func key(_ l: WidgetLayout) -> [String] { l.items.map { "\($0.kind) \($0.size) \($0.x) \($0.y)" } }
        #expect(key(got) == key(.standard()))
    }

    @Test func theNewWidgetsAreTaggedAndGroupedLikeTheMockup() {
        let new = WidgetKind.allCases.filter(\.isNew)
        #expect(new.count == 8)
        #expect(WidgetKind.weather.category == "Utilities" && WidgetKind.terminals.category == "Work")
        #expect(WidgetKind.brain.launch == "brain" && WidgetKind.todaynote.launch == "lore")
        #expect(WidgetKind.terminals.launch == "terminals" && WidgetKind.projects.launch == "projects")
    }

    @Test func aTodayNoteReadsItsChecklistAndATickWritesBackOnlyThatLine() throws {
        let text = "# Review day\nWalk the screens.\n\n- [x] Plan\n- [ ] Reply\n* [ ] Wallpaper\n"
        let n = try #require(HomeSnapshot.NoteFact.parse(text, id: "n1", rev: 3))
        #expect(n.title == "Review day" && n.paragraph == "Walk the screens.")
        #expect(n.todos.map(\.text) == ["Plan", "Reply", "Wallpaper"] && n.doneCount == 1)
        #expect(
            HomeSnapshot.NoteFact.toggling(text, todo: 1)
                == "# Review day\nWalk the screens.\n\n- [x] Plan\n- [x] Reply\n* [ ] Wallpaper\n")
        #expect(HomeSnapshot.NoteFact.toggling(text, todo: 0)?.contains("- [ ] Plan") == true)
        #expect(HomeSnapshot.NoteFact.toggling(text, todo: 9) == nil)
        #expect(HomeSnapshot.NoteFact.parse("  \n") == nil)
    }

    @Test func weatherReadsTheOpenMeteoAnswer() throws {
        let json = """
            {"current":{"temperature_2m":20.6,"weather_code":3,"wind_speed_10m":7.4},
             "hourly":{"time":["2030-01-01T10:00","2030-01-01T11:00"],"temperature_2m":[21.2,22.4],"weather_code":[0,61]},
             "daily":{"time":["2030-01-01"],"weather_code":[3],"temperature_2m_max":[24.4],"temperature_2m_min":[13.5]}}
            """
        let zone = TimeZone(identifier: "UTC")!
        let r = try WeatherReport.parse(
            Data(json.utf8), now: Date(timeIntervalSince1970: 1_893_492_000), zone: zone)  // 2030-01-01 10:00 UTC
        #expect(r.temp == 21 && r.code == 3 && r.wind == 7 && r.hours.count == 2 && r.days.first?.high == 24)
        #expect(WeatherReport.look(61).symbol == "cloud.rain" && WeatherReport.look(0).words == "Sunny")
    }

    @Test func gridMathSnapsToCells() {
        let o = DeskGrid.origin(2, 1)
        let c = DeskGrid.cell(at: CGPoint(x: o.x + 20, y: o.y - 30), size: .s)
        #expect(c.x == 2 && c.y == 1)
        let far = DeskGrid.cell(at: CGPoint(x: 5000, y: 5000), size: .l)
        #expect(far.x == WidgetLayout.cols - 4 && far.y == WidgetLayout.rows - 4)
    }
}

@MainActor
struct HomePrefsTests {
    init() { setenv("CORE_DEMO", "1", 1) }

    private func suite() -> UserDefaults {
        let name = "test.home.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func nameIsCleanedAndSaved() {
        let d = suite()
        let p = UserProfile(defaults: d)
        #expect(!p.hasName)
        p.set("  Sam \nsecond line")
        #expect(p.name == "Sam")
        #expect(UserProfile(defaults: d).name == "Sam")
        p.set(String(repeating: "x", count: 80))
        #expect(p.name.count == 40)
    }

    @Test func layoutEditsPersistAndUndoRestores() throws {
        let d = suite()
        let shell = ShellModel(defaults: d)
        let run = try #require(shell.widgets.items.first { $0.kind == .running })
        shell.removeWidget(run.id)
        #expect(!ShellModel(defaults: d).widgets.items.contains { $0.kind == .running })
        shell.toast?.undo?()
        #expect(shell.widgets.items.contains { $0.kind == .running })
        shell.resizeWidget(try #require(shell.widgets.items.first { $0.kind == .quick }).id, to: .s)
        #expect(ShellModel(defaults: d).widgets.items.first { $0.kind == .quick }?.size == .s)
    }

    @Test func resetGoesBackToTheDefault() {
        let d = suite()
        let shell = ShellModel(defaults: d)
        shell.addWidget(.core, .s)
        shell.resetWidgets()
        #expect(shell.widgets == .standard() || shell.widgets.items.count == 12)
    }
}

struct WidgetDataTests {
    @Test func spendDaysBucketsCostEventsByDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13 UTC
        let day: TimeInterval = 86_400
        let ev: [(at: Date, micros: Int64)] = [
            (now, 2_000_000), (now.addingTimeInterval(-60), 1_000_000), (now.addingTimeInterval(-day), 500_000),
            (now.addingTimeInterval(-40 * day), 9_000_000),
        ]
        let d = HomeSnapshot.spendDays(ev, now: now, days: 7, calendar: cal)
        #expect(d.count == 7 && d[6] == 3 && d[5] == 0.5 && d.reduce(0, +) == 3.5)  // the 40-day-old event is ignored
        #expect(HomeSnapshot.monthSpend(ev, now: now, calendar: cal) == 3.5)
    }

    @Test func runnerStates() {
        typealias M = HomeSnapshot.Machine
        #expect(HomeSnapshot.state(M(id: "a", os: "x", online: false, slots: 2, used: 0)) == .offline)
        #expect(HomeSnapshot.state(M(id: "a", os: "x", online: true, slots: 2, used: 2)) == .busy)
        #expect(HomeSnapshot.state(M(id: "a", os: "x", online: true, slots: 2, used: 1)) == .online)
    }

    @Test func galleryActsOnlyOnASingleCopy() {
        var l = WidgetLayout(items: [])
        #expect(l.onlyCopy(of: .digital) == nil)
        let first = l.add(.digital, .s)
        #expect(first != nil && l.onlyCopy(of: .digital)?.id == first?.id)
        #expect(l.add(.digital, .s) != nil)
        #expect(l.onlyCopy(of: .digital) == nil)
    }
}
