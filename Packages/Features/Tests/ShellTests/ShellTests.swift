import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Shell

@MainActor
struct LauncherTests {
    private func entries(_ titles: [String]) -> [LauncherEntry] { titles.map { LauncherEntry(id: $0, title: $0) {} } }

    @Test func initialsAndScatteredLettersFind() {
        let all = entries(["Terminals", "New agent session", "Citadel Board", "Settings"])
        #expect(Fuzzy.rank(all, query: "trm", recents: []).first?.entry.id == "Terminals")
        #expect(Fuzzy.rank(all, query: "ns", recents: []).first?.entry.id == "New agent session")
        #expect(Fuzzy.rank(all, query: "cit bo", recents: []).first?.entry.id == "Citadel Board")
        #expect(Fuzzy.rank(all, query: "zzz", recents: []).isEmpty)
    }

    @Test func emptyQueryPutsRecentsFirst() {
        let all = entries(["A", "B", "C"])
        let rows = Fuzzy.rank(all, query: "", recents: ["C"])
        #expect(rows.map(\.entry.id) == ["C", "A", "B"])
        #expect(rows.first?.group == .recent)
    }
}

@MainActor
struct ShellModelTests {
    @Test func onlyTheActivePaneInTheWorkspaceIsFront() {
        let shell = ShellModel()
        for id in ["a", "b"] { shell.openPane(PaneSpec(id: id, title: id, symbol: "square") { EmptyView() }) }
        #expect(shell.isFront("b") && !shell.isFront("a"))
        shell.surface = .home
        #expect(!shell.isFront("b"))
    }

    @Test func panesOpenFocusMoveAndClose() {
        let shell = ShellModel()
        for id in ["a", "b", "c"] { shell.openPane(PaneSpec(id: id, title: id, symbol: "square") { EmptyView() }) }
        #expect(shell.surface == .workspace && shell.panes.map(\.id) == ["a", "b", "c"] && shell.activePane == "c")
        shell.openPane(PaneSpec(id: "a", title: "a", symbol: "square") { EmptyView() })
        #expect(shell.panes.count == 3 && shell.activePane == "a")
        shell.movePane("a", to: 2)
        #expect(shell.panes.map(\.id) == ["b", "c", "a"])
        shell.closePane("a")
        #expect(shell.panes.map(\.id) == ["b", "c"] && shell.activePane == "c")
    }

    @Test func aClosedPaneComesBackWithUndoAndReopen() {
        let shell = ShellModel()
        for id in ["a", "b"] { shell.openPane(PaneSpec(id: id, title: id, symbol: "square") { EmptyView() }) }
        shell.dismissPane("b")
        #expect(shell.panes.map(\.id) == ["a"] && shell.closedPanes.map(\.id) == ["b"])
        #expect(shell.toast?.kind == .info && shell.toast?.undo != nil)
        shell.reopenClosedPane()
        #expect(shell.panes.map(\.id) == ["a", "b"] && shell.closedPanes.isEmpty)
        shell.closePane("a")  // a feature closing its own pane leaves nothing to reopen
        #expect(shell.closedPanes.isEmpty)
        shell.reopenClosedPane()
        #expect(shell.toast?.message == "No closed pane to reopen.")
    }

    @Test func aDropReordersThePanesAndKeepsThemAllOpen() {
        let shell = ShellModel()
        for id in ["a", "b", "c"] { shell.openPane(PaneSpec(id: id, title: id, symbol: "square") { EmptyView() }) }
        shell.dropPane("c", on: "a", edge: .bottom)
        #expect(shell.panes.map(\.id) == ["a", "c", "b"])
    }
}

@MainActor
struct ThemeTests {
    @Test func theChoiceIsRememberedAndSystemMeansNoOverride() {
        let d = UserDefaults(suiteName: "theme-tests-\(UUID())")!
        #expect(ThemeChoice.stored(d) == .system)
        d.set("night", forKey: ThemeChoice.key)
        #expect(ThemeChoice.stored(d) == .night)
        d.set("junk", forKey: ThemeChoice.key)
        #expect(ThemeChoice.stored(d) == .system)
        #expect(ThemeChoice.system.appearance == nil)
        #expect(
            ThemeChoice.sun.appearance(hour: 6)?.name == .darkAqua && ThemeChoice.sun.appearance(hour: 7)?.name == .aqua
        )
        #expect(
            ThemeChoice.sun.appearance(hour: 17)?.name == .aqua
                && ThemeChoice.sun.appearance(hour: 18)?.name == .darkAqua)
        #expect(ThemeChoice.day.appearance?.name == .aqua && ThemeChoice.night.appearance?.name == .darkAqua)
    }
}

@MainActor
struct LaneL4Tests {
    private func model() -> ShellModel {
        ShellModel(defaults: UserDefaults(suiteName: "l4-\(UUID().uuidString)")!)
    }

    @Test func escClosesTheNewestLayerFirstAndLeavesPanesAlone() {
        let m = model()
        #expect(!m.closeTopmost())  // nothing open: the pane's own back handler gets Esc
        m.launcherOpen = true
        m.presentSheet(title: "t", message: "m", actions: [])
        #expect(m.closeTopmost() && m.sheet == nil && m.launcherOpen)
        #expect(m.closeTopmost() && !m.launcherOpen)
        #expect(!m.closeTopmost())
    }

    @Test func aDialogThatCannotBeDismissedIgnoresEsc() {
        let m = model()
        m.presentOnTop(ShellDialog(id: "step-up", dismissible: false) { EmptyView() })
        #expect(m.closeTopmost() && m.topDialog != nil)  // consumed, not closed
    }

    @Test func waitingCountsApprovalsFromTheSourceOnly() {
        let m = model()
        m.bell.add(BellItem(id: "a", kind: .approval, title: "a"))
        m.bell.add(BellItem(id: "b", kind: .alarm, title: "b"))
        #expect(m.waitingOnYou == 1 && m.alertsOnYou == 1)  // the alarm is its own count
        m.waitingSource = { 3 }
        #expect(m.waitingOnYou == 3 && m.alertsOnYou == 1)
    }

    @Test func aTabUsesTheAppsNameNotTheSubText() {
        let m = model()
        var spec = PaneSpec(id: "p", title: "Accounts", sub: "Home Core", symbol: "x") { EmptyView() }
        #expect(m.tabName(spec) == "Home Core")
        spec.tab = "Accounts"
        #expect(m.tabName(spec) == "Accounts")
    }
}
