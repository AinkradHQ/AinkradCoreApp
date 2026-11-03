import Foundation
import SwiftTerm

/// Feeds bytes to a SwiftTerm view from one serial background queue. SwiftTerm documents `feed` as callable off the main
/// thread (it schedules its own redraw), so the parse stays off the main actor. This is a Swift 5 language-mode target on
/// purpose: that call is the one place the view's main-actor isolation is crossed, and doing it here keeps the rest strict.
public final class TerminalFeeder: @unchecked Sendable {
    private let view: TerminalView
    private let queue = DispatchQueue(label: "com.ainkrad.core.terminal-feed", qos: .userInteractive)

    public init(view: TerminalView) { self.view = view }

    /// Draws `data` (after a full reset when `reset`), then calls `done`, all on the feed queue, in order.
    public func feed(_ data: Data, reset: Bool, done: @escaping @Sendable () -> Void) {
        queue.async { [view] in
            if reset { view.feed(text: "\u{1b}c") }
            view.feed(byteArray: [UInt8](data)[...])
            done()
        }
    }
}
