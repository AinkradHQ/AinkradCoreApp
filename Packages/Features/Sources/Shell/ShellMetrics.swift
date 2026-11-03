import CoreUI
import SwiftUI

/// Shell layout constants. Everything derives from CoreUI spacing tokens except the two pane minimums, which the plan fixes (D9, `tiles.js`).
enum ShellMetrics {
    static let paneMinWidth: CGFloat = 340
    static let paneMinHeight: CGFloat = 560
    static let paneGap = Space.s3
    static let paneInset = Space.s3
    /// Top strip the status cluster lives in; panes and widgets start below it.
    static let topBar = MacSize.controlLg + Space.s5
    static let widgetCell = Space.s8 * 4.5
    static let widgetGap = Space.s3
    static let widgetInset = Space.s8 * 2
    static let launcherWidth = Space.s8 * 20
    static let bellWidth = Space.s8 * 14
    static let settingsSize = CGSize(width: Space.s8 * 26, height: Space.s8 * 18)
}
