import SwiftUI
import Testing

@testable import Shell

@MainActor
struct WorkspaceTests {
    private func spec(_ id: String, full: Bool = false, minWidth: CGFloat? = nil) -> PaneSpec {
        PaneSpec(id: id, title: id, symbol: "square", minWidth: minWidth, fullScreenOnly: full) { EmptyView() }
    }

    @Test func appsThatFitShareOneWorkspace() {
        let shell = ShellModel()
        shell.workspaceWidth = 1500
        for id in ["a", "b", "c"] { shell.openPane(spec(id)) }
        #expect(shell.spaces.count == 1 && shell.panes.map(\.id) == ["a", "b", "c"])
    }

    @Test func anAppThatDoesNotFitOpensANewWorkspaceNeverAStack() {
        let shell = ShellModel()
        shell.workspaceWidth = 1000
        shell.openPane(spec("a"))
        shell.openPane(spec("b"))
        shell.openPane(spec("c"))
        #expect(shell.spaces.count == 2)
        #expect(shell.panes.map(\.id) == ["c"] && shell.allPanes.count == 3 && shell.spaceNote?.fullScreen == false)
    }

    @Test func aFullScreenAppGetsItsOwnWorkspaceAndNothingJoinsIt() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        #expect(shell.spaces.count == 2 && shell.panes.map(\.id) == ["design"] && shell.spaceNote?.fullScreen == true)
        shell.openPane(spec("b"))
        #expect(shell.spaces.count == 3 && shell.panes.map(\.id) == ["b"])
        shell.switchSpace(to: 0)
        #expect(shell.panes.map(\.id) == ["a"] && shell.activePane == "a")
    }

    @Test func aFullScreenAppOpensWithNothingElseOpenWithoutANewWorkspace() {
        let shell = ShellModel()
        shell.openPane(spec("design", full: true))
        #expect(shell.spaces.count == 1)
    }

    @Test func openingAnAppInAnotherWorkspaceTakesYouThere() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        shell.openPane(spec("a"))
        #expect(shell.spaceIndex == 0 && shell.activePane == "a" && shell.allPanes.count == 2)
    }

    @Test func switchingKeepsEachWorkspacesActivePaneAndRoundsTheRing() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("b"))
        shell.openPane(spec("full", full: true))
        shell.moveSpace(1)
        #expect(shell.spaceIndex == 0 && shell.activePane == "b")
        shell.moveSpace(-1)
        #expect(shell.spaceIndex == 1 && shell.activePane == "full")
        shell.switchSpace(to: 9)
        #expect(shell.spaceIndex == 1)
    }

    @Test func anEmptyWorkspaceClosesAndGoesHome() {
        let shell = ShellModel()
        shell.openPane(spec("a"))
        shell.newSpace()
        #expect(shell.spaces.count == 2 && shell.panes.isEmpty && shell.surface == .workspace)
        shell.closeEmptySpace()
        #expect(shell.surface == .home && shell.spaces.count == 1 && shell.panes.map(\.id) == ["a"])
        shell.closeEmptySpace()
        #expect(shell.surface == .home)
    }

    @Test func closingTheLastAppLeavesAnEmptyWorkspaceThatCanStay() {
        let shell = ShellModel()
        shell.openPane(spec("a"))
        shell.closePane("a")
        #expect(shell.panes.isEmpty && shell.spaces.count == 1 && shell.surface == .workspace)
    }

    @Test func leavingAnEmptyWorkspaceDropsIt() {
        let shell = ShellModel()
        shell.openPane(spec("a"))
        shell.newSpace()
        shell.switchSpace(to: 0)
        #expect(shell.spaces.count == 1)
    }

    @Test func closingAPaneInAnotherWorkspaceRemovesTheWorkspaceWhenItEmpties() {
        let shell = ShellModel()
        shell.workspaceWidth = 3000
        shell.openPane(spec("a"))
        shell.openPane(spec("design", full: true))
        shell.closePane("a")
        #expect(shell.spaces.count == 1 && shell.panes.map(\.id) == ["design"])
        shell.closePane("design")
        #expect(shell.spaces.count == 1 && shell.allPanes.isEmpty)
    }

    @Test func commandZeroTogglesHomeAndTheWorkspaceButNeedsSomethingOpen() {
        let shell = ShellModel()
        shell.toggleSurface()
        #expect(shell.surface == .home)
        shell.openPane(spec("a"))
        shell.toggleSurface()
        #expect(shell.surface == .home)
        shell.toggleSurface()
        #expect(shell.surface == .workspace && shell.panes.map(\.id) == ["a"])
    }
}
