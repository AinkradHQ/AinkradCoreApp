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
        #expect(l.items.count == 10)
        #expect(noOverlap(l.items))
    }

    @Test func movingPushesTheOthersAside() throws {
        var l = WidgetLayout.standard()
        let clock = try #require(l.items.first { $0.kind == .digital })
        let spend = try #require(l.items.first { $0.kind == .spend })
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
        let today = try #require(l.items.first { $0.kind == .today })
        _ = l.move(today.id, to: 99, 99)
        let t = try #require(l.items.first { $0.id == today.id })
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
        let board = try #require(l.items.first { $0.kind == .board })
        let removed = l.remove(board.id)
        let gone = try #require(removed)
        #expect(l.items.count == 9)
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
            #"{"v":2,"items":[{"t":"clock","s":"s","x":0,"y":0},{"t":"nope","s":"s","x":1,"y":0},{"t":"clock","s":"s","x":0,"y":0},{"t":"today","s":"x","x":15,"y":0},{"t":"quick","s":"t","x":2,"y":0}]}"#
        let d = try #require(WidgetLayout.decoded(Data(bad.utf8)))
        #expect(d.items.count == 1)  // unknown kind, overlap, off-grid and a size the widget lacks are all dropped
        #expect(WidgetLayout.decoded(Data("{\"v\":3,\"items\":[]}".utf8)) == nil)
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

    @Test func onlyTheDigitalClockIsTall() {
        #expect(WidgetSize.allCases.map(\.rawValue) == ["s", "m", "t", "l", "x"])
        #expect(WidgetKind.allCases.filter { $0.sizes.contains(.t) } == [.digital])
        #expect(WidgetKind.digital.sizes == [.m, .s, .t, .l] && WidgetKind.clock.sizes == [.s, .m, .l])
        #expect(WidgetSize.t.cols == 2 && WidgetSize.t.rows == 4)
        #expect(WidgetSize.x.cols == 8 && WidgetSize.x.rows == 4 && WidgetSize.m.cols == 4 && WidgetSize.s.rows == 2)
        #expect(WidgetSize.m.spoken == "Wide, 2 by 1" && WidgetSize.t.spoken == "Tall, 1 by 2")
        #expect(WidgetSize.allCases.map(\.short) == ["S", "W", "T", "L", "X"])
    }

    @Test func addingNeverGivesAWidgetASizeItLacks() {
        // Room for a 2 x 4 strip only: an analog clock asked for large must not fall back to tall.
        var items: [WidgetItem] = []
        for y in stride(from: 0, to: WidgetLayout.rows, by: 2) {
            for x in stride(from: 2, to: WidgetLayout.cols, by: 2) {
                items.append(WidgetItem(kind: .quick, size: .s, x: x, y: y))
            }
        }
        var l = WidgetLayout(items: items)
        let c = l.add(.clock, .l)
        #expect(c.map { WidgetKind.clock.sizes.contains($0.size) } ?? true)
        let d = l.add(.digital, .l)
        #expect(d?.size == .t || d?.size == .s)
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
        let board = try #require(shell.widgets.items.first { $0.kind == .board })
        shell.removeWidget(board.id)
        #expect(!ShellModel(defaults: d).widgets.items.contains { $0.kind == .board })
        shell.toast?.undo?()
        #expect(shell.widgets.items.contains { $0.kind == .board })
        shell.resizeWidget(try #require(shell.widgets.items.first { $0.kind == .digital }).id, to: .t)
        #expect(ShellModel(defaults: d).widgets.items.first { $0.kind == .digital }?.size == .t)
    }

    @Test func resetGoesBackToTheDefault() {
        let d = suite()
        let shell = ShellModel(defaults: d)
        shell.addWidget(.core, .s)
        shell.resetWidgets()
        #expect(shell.widgets == .standard() || shell.widgets.items.count == 10)
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
