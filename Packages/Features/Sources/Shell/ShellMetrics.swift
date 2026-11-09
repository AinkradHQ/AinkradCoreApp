import CoreUI
import SwiftUI

/// Shell layout constants. Everything derives from CoreUI spacing tokens except the two pane minimums, which the plan fixes (D9, `tiles.js`).
enum ShellMetrics {
    /// No app gets narrower than this (Ahmed, 2026-11-05: squeezed apps broke their headers); past it the workspace
    /// scrolls sideways.
    static let paneMinWidth: CGFloat = 460
    static let paneMinHeight: CGFloat = 560
    static let paneGap = Space.s3
    static let paneInset = Space.s3
    /// Top strip the status cluster lives in; panes and widgets start below it.
    static let topBar = MacSize.controlLg + Space.s5
    /// Home is laid out on the prototype's 1440 x 900 stage (`widgets.js`: 150 px cells, 14 px gaps, 71 px side margin) and the whole
    /// stage is scaled to the screen, exactly as the prototype fits its window. These four are that grid, not UI tokens.
    static let designSize = CGSize(width: 1440, height: 900)
    static let widgetCell: CGFloat = 150
    static let widgetGap: CGFloat = 14
    static let widgetInset: CGFloat = 71
    static let widgetTop: CGFloat = 50
    static let launcherWidth = Space.s8 * 20
    static let bellWidth: CGFloat = 460
    /// The prototype's Settings overlay is 1080 wide.
    static let settingsSize = CGSize(width: 1080, height: Space.s8 * 23)
}
