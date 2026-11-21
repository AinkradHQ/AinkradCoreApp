import SwiftUI
import Testing

@testable import Shell

/// The placement rule (Ahmed, 2026-11-21): a new app joins the active workspace while every pane keeps its minimum width and
/// height, side by side first, then stacked; only when it cannot does it get a workspace of its own.
@MainActor
struct WorkspaceFitTests {
    private func spec(_ id: String, w: CGFloat? = nil, h: CGFloat? = nil, full: Bool = false) -> PaneSpec {
        PaneSpec(id: id, title: id, symbol: "square", minWidth: w, minHeight: h, fullScreenOnly: full) { EmptyView() }
    }

    private func shell(_ w: CGFloat, _ h: CGFloat) -> ShellModel {
        let s = ShellModel()
        s.workspaceWidth = w
        s.workspaceHeight = h
        return s
    }

    // MacBook Air full screen: 1470 x 956, less the 12 pt insets and the 52 pt top bar.
    private let air = CGSize(width: 1446, height: 892)
    // A 2560 x 1440 display.
    private let big = CGSize(width: 2536, height: 1376)

    @Test func oneToThreeDefaultAppsShareTheAirsWorkspaceTheFourthGetsItsOwn() {
        let s = shell(air.width, air.height)
        for id in ["a", "b", "c"] { s.openPane(spec(id)) }  // 3 x 460 + 2 x 12 = 1404 <= 1446
        #expect(s.spaces.count == 1 && s.panes.map(\.id) == ["a", "b", "c"])
        s.openPane(spec("d"))  // 1876 wide side by side; stacked needs 2 x 560 + 12 = 1132 > 892 tall
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["d"] && s.spaceIndex == 1 && s.activePane == "d")
    }

    @Test func onTheAirAFourthListAppStacksAndASeventhGetsAWorkspace() {
        let s = shell(air.width, air.height)
        let list = ShellMetrics.listPaneMinHeight
        for id in ["sessions", "terminals", "brain"] { s.openPane(spec(id, h: list)) }
        s.openPane(spec("session-1", h: list))  // no room beside; stacked: (892 - 12) / 2 = 440 >= 400
        #expect(s.spaces.count == 1 && s.panes.map(\.id) == ["sessions", "terminals", "brain", "session-1"])
        for id in ["session-2", "session-3"] { s.openPane(spec(id, h: list)) }  // two per column, three columns
        #expect(s.spaces.count == 1 && s.panes.count == 6)
        s.openPane(spec("session-4", h: list))  // a third row: 3 x 400 + 24 = 1224 > 892
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["session-4"])
    }

    @Test func aListAppDoesNotStackUnderAnAppThatNeedsTheFullHeight() {
        let s = shell(air.width, air.height)
        s.openPane(spec("machines", w: 880))  // 560 tall: cannot share its column on the Air
        s.openPane(spec("sessions", h: ShellMetrics.listPaneMinHeight))
        s.openPane(spec("terminals", h: ShellMetrics.listPaneMinHeight))  // 880 + 460 + 460 + 24 > 1446: under sessions
        #expect(s.spaces.count == 1 && s.panes.map(\.id) == ["machines", "sessions", "terminals"])
    }

    @Test func noAppIsShorterThanTheListMinimum() {
        #expect(spec("x", h: 100).minHeight == ShellMetrics.listPaneMinHeight && spec("y").minHeight == 560)
    }

    @Test func aTallScreenStacksTheAppThatDoesNotFitSideBySide() {
        let s = shell(big.width, big.height)
        s.openPane(spec("machines", w: 880))
        s.openPane(spec("accounts", w: 860))
        s.openPane(spec("activity", w: 760))  // 880 + 860 + 760 + 24 = 2524 <= 2536
        #expect(s.spaces.count == 1)
        s.openPane(spec("terminals", w: 560))  // no room beside: it goes under the biggest tile
        #expect(s.spaces.count == 1 && s.panes.count == 4)
        guard case .split(.horizontal, _, let columns)? = s.tree.root else { return #expect(Bool(false)) }
        #expect(columns.count == 3)
        #expect(s.panes.map(\.id) == ["machines", "terminals", "accounts", "activity"])
    }

    @Test func fourAppsStackTwoByTwoAndAFifthThatCannotKeepItsHeightGetsAWorkspace() {
        let s = shell(1200, 1200)
        for id in ["a", "b", "c", "d"] { s.openPane(spec(id)) }
        // Two columns of 460; three would need 1404. Stacked: 2 x 560 + 12 = 1132 <= 1200 tall.
        #expect(s.spaces.count == 1 && s.panes.map(\.id) == ["a", "d", "b", "c"])
        s.openPane(spec("e"))  // a third row needs 3 x 560 + 24 = 1704 > 1200
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["e"])
    }

    @Test func aWideAppAlwaysFitsAloneEvenOnASmallWindow() {
        let s = shell(800, 500)
        s.openPane(spec("machines", w: 880))
        s.openPane(spec("b"))
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["b"])
    }

    @Test func aShortWindowStillTakesAppsSideBySide() {
        let s = shell(1446, 400)  // shorter than any app's minimum height: height cannot be what keeps them apart
        s.openPane(spec("a"))
        s.openPane(spec("b"))
        #expect(s.spaces.count == 1)
    }

    @Test func anAppAlreadyOpenIsFocusedNotOpenedTwice() {
        let s = shell(air.width, air.height)
        s.openPane(spec("a"))
        s.openPane(spec("b"))
        s.openPane(spec("a"))
        #expect(s.allPanes.count == 2 && s.spaces.count == 1 && s.activePane == "a")
    }

    @Test func aFullScreenAppStillGetsAWorkspaceAlone() {
        let s = shell(big.width, big.height)
        s.openPane(spec("a"))
        s.openPane(spec("design", full: true))
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["design"])
    }

    @Test func reopeningAClosedAppPlacesItByTheSameRule() {
        let s = shell(air.width, air.height)
        for id in ["a", "b", "c"] { s.openPane(spec(id)) }
        s.dismissPane("b")
        s.reopenClosedPane()  // fits beside a and c again
        #expect(s.spaces.count == 1 && s.panes.map(\.id) == ["a", "c", "b"])
        s.openPane(spec("d"))  // the fourth: a workspace of its own
        s.dismissPane("d")  // that workspace empties and closes: back to the first
        #expect(s.spaces.count == 1 && s.panes.count == 3)
        s.reopenClosedPane()  // still no room there
        #expect(s.spaces.count == 2 && s.panes.map(\.id) == ["d"])
    }

    @Test func aUserStackCountsAsOneColumn() {
        var t = TileTree()
        for id in ["a", "b", "c"] { t.open(id) }
        t.drop("c", on: "a", edge: .bottom)  // a/c stacked, b beside
        let mins: (String) -> CGSize = { _ in CGSize(width: 460, height: 300) }
        let placed = t.placing("d", in: CGSize(width: 1404, height: 892), gap: 12, min: mins)
        #expect(placed?.leaves == ["a", "c", "b", "d"])  // a third column fits: the stack is one column wide
    }

    @Test func unmeasuredWorkspaceTakesEverything() {
        let s = ShellModel()
        for id in ["a", "b", "c", "d", "e"] { s.openPane(spec(id)) }
        #expect(s.spaces.count == 1)
    }

    @Test func aClickOnAnotherWorkspacesAppGoesThereAndPicksIt() {
        let s = shell(air.width, air.height)
        for id in ["a", "b", "c", "d", "e"] { s.openPane(spec(id)) }
        #expect(s.panes(inSpace: 0).map(\.id) == ["a", "b", "c"] && s.panes(inSpace: 1).map(\.id) == ["d", "e"])
        s.goTo("b")
        #expect(s.spaceIndex == 0 && s.activePane == "b" && s.surface == .workspace)
        s.goTo("e")
        #expect(s.spaceIndex == 1 && s.activePane == "e")
    }
}
