import Foundation
import SwiftUI
import Testing

@testable import Shell

@MainActor
struct LauncherV2Tests {
    private func entry(_ id: String, action: Bool = false) -> LauncherEntry {
        LauncherEntry(id: id, title: id, sub: "about \(id)", isAction: action) {}
    }

    private let cal = Calendar(identifier: .gregorian)
    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func usageCountsRecencyAndTimeOfDay() {
        var u = LauncherUsage()
        for d in 1...5 { u.record("often", at: at(d, 9), calendar: cal) }
        u.record("once", at: at(5, 9), calendar: cal)
        let now = at(6, 9)
        #expect(u.score("often", at: now, calendar: cal) > u.score("once", at: now, calendar: cal))
        #expect(u.score("never", at: now, calendar: cal) == 0)
        // The same habit scores lower at the wrong hour.
        #expect(u.score("often", at: at(6, 21), calendar: cal) < u.score("often", at: now, calendar: cal))
        // And lower once it is old.
        #expect(u.score("often", at: at(28, 9), calendar: cal) < u.score("often", at: now, calendar: cal))
        #expect(u.reason("often", at: now, calendar: cal) == "Usually at this hour")
        #expect(u.reason("once", at: at(5, 9).addingTimeInterval(1200), calendar: cal) == "Opened 20 min ago")
    }

    @Test func usageForgetsTheLeastUsefulPastTheLimit() {
        var u = LauncherUsage()
        for _ in 1...5 { u.record("keeper", at: at(1, 9), calendar: cal) }
        for i in 0..<(LauncherUsage.limit + 20) { u.record("e\(i)", at: at(1, 9), calendar: cal) }
        #expect(u.stats.count == LauncherUsage.limit && u.stats["keeper"] != nil)
    }

    @Test func picksAreSixUsedFirstThenAppsInOrderAndUsageSurvivesALaunch() {
        let suite = UserDefaults(suiteName: "launcher-v2-\(UUID())")!
        let reg = LauncherRegistry()
        reg.attach(suite)
        for id in ["a", "b", "c", "d", "e", "f", "g", "h"] { reg.register(entry(id)) }
        reg.refreshPicks(at: at(6, 9))
        #expect(reg.picks.map(\.id) == ["a", "b", "c", "d", "e", "f"])
        reg.remember("h", at: at(6, 9))
        reg.remember("h", at: at(6, 9))
        reg.remember("g", at: at(6, 9))
        #expect(reg.picks.count == 6 && Array(reg.picks.map(\.id).prefix(2)) == ["h", "g"])
        let again = LauncherRegistry()
        again.attach(suite)
        for id in ["a", "b", "g", "h"] { again.register(entry(id)) }
        again.refreshPicks()
        #expect(again.picks.first?.id == "h")
        #expect(again.usage.stats["h"]?.count == 2)
    }

    @Test func anOldIdOpensTheEntryThatReplacedIt() {
        let reg = LauncherRegistry()
        reg.register(entry("machines"))
        reg.aliases["runners"] = "machines"
        #expect(reg.entry("runners")?.id == "machines" && reg.entry("devices") == nil)
    }

    @Test func actionsAndSessionsAreNeverFilledIntoTheDefaultPicks() {
        let reg = LauncherRegistry()
        reg.register(entry("go", action: true))
        reg.register(entry("agents.s-1"))
        reg.register(entry("app"))
        reg.refreshPicks()
        #expect(reg.picks.map(\.id) == ["app"])
    }

    @Test func browseKeepsGroupsCollapsedUntilOpened() {
        let es = [entry("app"), entry("agents.s-1"), entry("agents.s-2"), entry("go", action: true)]
        let closed = LauncherLines.browse(entries: es, picks: [], open: nil)
        #expect(closed.count == 3 && closed.allSatisfy(\.isGroup))
        let open = LauncherLines.browse(entries: es, picks: [], open: .sessions)
        #expect(open.count == 5)
    }

    @Test func resultsGroupWithTheBestGroupFirst() {
        let es = [entry("terminal"), entry("agents.s-term"), entry("Terminal tricks"), entry("go", action: true)]
        let lines = LauncherLines.results(Fuzzy.rank(es, query: "term", recents: []))
        #expect(lines.count == 3)
        #expect(lines.first?.heading == LauncherSection.apps.title)
    }

    /// Apps lead even when a session or note matches the words better (Ahmed, 2026-11-22).
    @Test func appsLeadEvenWhenAnotherHitScoresHigher() {
        let es = [
            entry("brain"), entry("agents.s-brain import"), entry("note-brain"), entry("brain dump", action: true),
        ]
        let lines = LauncherLines.results(
            Fuzzy.rank(es, query: "brain import", recents: [])
                + Fuzzy.rank(es, query: "brain", recents: []).filter { $0.entry.id == "brain" })
        #expect(lines.first?.heading == LauncherSection.apps.title)
    }

    @Test func tabJumpsBetweenGroupsAndWraps() {
        let es = [entry("app"), entry("agents.s-1"), entry("go", action: true)]
        let lines = LauncherLines.browse(entries: es, picks: [], open: .apps)
        // apps header, app item, sessions header, actions header
        #expect(LauncherLines.nextGroup(lines, from: 0, step: 1) == 2)
        #expect(LauncherLines.nextGroup(lines, from: 3, step: 1) == 0)
        #expect(LauncherLines.nextGroup(lines, from: 0, step: -1) == 3)
        #expect(LauncherLines.nextGroup([lines[0]], from: 0, step: 1) == nil)
    }

    @Test func usageBonusBreaksTiesInSearch() {
        let es = [entry("Terminals"), entry("Terminal tricks")]
        let plain = Fuzzy.rank(es, query: "term", recents: [])
        let boosted = Fuzzy.rank(es, query: "term", recents: [], usage: ["Terminal tricks": 8])
        #expect(plain.first?.entry.id == "Terminals" || plain.first?.entry.id == "Terminal tricks")
        #expect(boosted.first?.entry.id == "Terminal tricks")
    }
}

@MainActor
struct LauncherGridTests {
    private func pick(_ id: String) -> LauncherLine {
        .pick(LauncherPick(entry: LauncherEntry(id: id, title: id) {}, reason: ""))
    }
    private func group(_ s: LauncherSection) -> LauncherLine { .group(s, count: 1, open: false) }

    @Test func picksMoveInTwoDimensionsAndLeaveTheGridDownwards() {
        // five picks (3 rows: 0 1 / 2 3 / 4) then two groups
        let l = (0..<5).map { pick("p\($0)") } + [group(.apps), group(.sessions)]
        #expect(LauncherLines.move(l, from: 0, .right) == 1)
        #expect(LauncherLines.move(l, from: 1, .right) == nil)
        #expect(LauncherLines.move(l, from: 1, .left) == 0)
        #expect(LauncherLines.move(l, from: 0, .left) == nil)
        #expect(LauncherLines.move(l, from: 1, .down) == 3)
        #expect(LauncherLines.move(l, from: 3, .down) == 5)  // no cell below: on to the first group
        #expect(LauncherLines.move(l, from: 2, .down) == 4)
        #expect(LauncherLines.move(l, from: 3, .up) == 1)
        #expect(LauncherLines.move(l, from: 0, .up) == 6)  // wraps to the last line
    }

    @Test func fromTheFirstGroupUpGoesBackToTheLastRowOfPicks() {
        let l = (0..<5).map { pick("p\($0)") } + [group(.apps), group(.sessions)]
        #expect(LauncherLines.move(l, from: 5, .up) == 4)
        #expect(LauncherLines.move(l, from: 5, .left) == nil)
        #expect(LauncherLines.move(l, from: 6, .down) == 0)
        let six = (0..<6).map { pick("p\($0)") } + [group(.apps)]
        #expect(LauncherLines.move(six, from: 6, .up) == 4)
    }

    @Test func fallbacksAreOfferedByModulesAndTakeTheWords() {
        let reg = LauncherRegistry()
        var got = ""
        reg.registerFallback(
            LauncherFallback(id: "ask", symbol: "sparkles", title: { "Ask AI about “\($0)”" }) { got = $0 })
        reg.registerFallback(LauncherFallback(id: "ask", symbol: "sparkles", title: { "Ask \($0)" }) { got = $0 })
        #expect(reg.fallbacks.count == 1 && reg.fallbacks[0].title("x") == "Ask x")
        reg.fallbacks[0].run("hello")
        #expect(got == "hello")
    }

    @Test func notesBelongToTheirOwnGroup() {
        let e = LauncherEntry(id: "note-n_1", title: "Weekly plan") {}
        #expect(
            LauncherSection.of(e) == .notes
                && LauncherSection.of(LauncherEntry(id: "project-3", title: "x") {}) == .projects)
        #expect(LauncherSection.of(LauncherEntry(id: "terminal-t", title: "x") {}) == .terminals)
    }
}

@MainActor
struct OpenBesideTests {
    private func spec(_ id: String, full: Bool = false) -> PaneSpec {
        PaneSpec(id: id, title: id, symbol: "square", fullScreenOnly: full) { EmptyView() }
    }

    @Test func plainOpenSwitchesToTheWorkspaceItIsIn() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        shell.openPane(spec("a"))
        #expect(shell.spaceIndex == 0 && shell.allPanes.count == 2 && shell.spaces.count == 2)
    }

    @Test func openBesideMovesItNextToTheCurrentAppWhenItFits() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        shell.openPane(spec("b"))  // third workspace, b alone
        shell.switchSpace(to: 0)
        shell.openBeside = true
        shell.openPane(spec("b"))
        #expect(shell.panes.map(\.id) == ["a", "b"] && shell.spaces.count == 2 && shell.activePane == "b")
    }

    @Test func openBesideGoesToANewWorkspaceWhenItDoesNotFit() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        shell.switchSpace(to: 0)
        shell.openBeside = true
        shell.openPane(spec("design", full: true))
        // design is full-screen-only and `a` is here: it gets a workspace of its own, which is where it already was.
        #expect(shell.panes.map(\.id) == ["design"] && shell.allPanes.count == 2)
        #expect(shell.spaces.count == 2)
    }
}
