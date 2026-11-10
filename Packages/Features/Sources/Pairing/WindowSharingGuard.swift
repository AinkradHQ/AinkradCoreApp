import AppKit
import SwiftUI

/// Keeps the window out of screenshots and screen sharing while a one-time secret (a QR, or a link in a field) may be on it.
/// Best effort: it is the system's request that capture skip this window, not a guarantee. A Release build always guards.
/// Only a Debug build reads `CORE_ALLOW_CAPTURE=1`, which the snapshot scripts and the Air rig set because they have to
/// capture the window.
struct WindowSharingGuard: NSViewRepresentable {
    static var allowCapture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CORE_ALLOW_CAPTURE"] == "1"
        #else
        false
        #endif
    }

    final class Anchor: NSView {
        private var before: NSWindow.SharingType = .readOnly
        private weak var held: NSWindow?
        override func viewWillMove(toWindow new: NSWindow?) {
            if !WindowSharingGuard.allowCapture {
                if let new {
                    before = new.sharingType
                    new.sharingType = .none
                    held = new
                } else if let held {
                    held.sharingType = before
                }
            }
            super.viewWillMove(toWindow: new)
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}
