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

struct PaneLayoutTests {
    private let gap: CGFloat = 12

    @Test func fittingPanesShareTheWidthEqually() {
        let l = PaneLayout.make(
            minWidths: [340, 340, 340], container: CGSize(width: 1500, height: 700), gap: gap, minHeight: 560)
        #expect(!l.isStrip)
        #expect(l.frames.count == 3 && l.frames[0].width == l.frames[2].width)
        #expect(abs(l.frames[2].maxX - 1500) < 0.5)
    }

    @Test func stripStartsWhenMinimumsDoNotFit() {
        let w: CGFloat = 340 * 4 + gap * 3
        #expect(
            !PaneLayout.make(
                minWidths: Array(repeating: 340, count: 4), container: CGSize(width: w, height: 700), gap: gap,
                minHeight: 560
            ).isStrip)
        let l = PaneLayout.make(
            minWidths: Array(repeating: 340, count: 4), container: CGSize(width: w - 1, height: 700), gap: gap,
            minHeight: 560)
        #expect(l.isStrip && l.frames.allSatisfy { $0.width == 340 } && l.contentWidth == w)
    }

    @Test func heightNeverDropsBelowTheMinimum() {
        let l = PaneLayout.make(minWidths: [340], container: CGSize(width: 900, height: 400), gap: gap, minHeight: 560)
        #expect(l.frames[0].height == 560)
    }

    @Test func fractionsSetWidthsButMinimumsHold() {
        let area = CGSize(width: 1100, height: 700)
        let l = PaneLayout.make(
            minWidths: [340, 340, 340], fractions: [0.6, 0.2, 0.2], container: area, gap: 12, minHeight: 560)
        #expect(l.frames[0].width > l.frames[1].width && l.frames.allSatisfy { $0.width >= 340 - 0.01 })
        #expect(abs(l.frames[2].maxX - 1100) < 0.5)
        let mixed = PaneLayout.make(
            minWidths: [560, 340, 340], container: CGSize(width: 1400, height: 700), gap: 12, minHeight: 560)
        #expect(mixed.frames[0].width >= 560 - 0.01 && abs(mixed.frames[2].maxX - 1400) < 0.5)
    }

    @Test func nearestColumn() {
        let l = PaneLayout.make(
            minWidths: [340, 340, 340], container: CGSize(width: 1100, height: 700), gap: gap, minHeight: 560)
        #expect(l.nearestIndex(toX: 20) == 0 && l.nearestIndex(toX: 1090) == 2)
    }
}

@MainActor
struct ShellModelTests {
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
        #expect(ThemeChoice.day.appearance?.name == .aqua && ThemeChoice.night.appearance?.name == .darkAqua)
    }
}
