import SwiftUI
import Testing

@testable import Shell

@MainActor
struct PaneSpecTests {
    @Test func everyAppHasAMinimumSizeAndNoneIsFullScreenOnlyByDefault() {
        let plain = PaneSpec(id: "a", title: "a", symbol: "square") { EmptyView() }
        #expect(plain.minWidth == ShellMetrics.paneMinWidth && plain.minHeight == ShellMetrics.paneMinHeight)
        #expect(!plain.fullScreenOnly)
    }

    @Test func aMinimumCanGrowButNeverGoBelowTheShellFloor() {
        let big = PaneSpec(id: "a", title: "a", symbol: "square", minWidth: 720, minHeight: 700, fullScreenOnly: true) {
            EmptyView()
        }
        #expect(big.minWidth == 720 && big.minHeight == 700 && big.fullScreenOnly)
        let small = PaneSpec(id: "b", title: "b", symbol: "square", minWidth: 100, minHeight: 100) { EmptyView() }
        #expect(small.minWidth == ShellMetrics.paneMinWidth && small.minHeight == ShellMetrics.paneMinHeight)
    }
}
