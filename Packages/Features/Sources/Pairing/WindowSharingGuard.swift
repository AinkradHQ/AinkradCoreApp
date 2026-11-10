import AppKit
import SwiftUI

/// Keeps the window out of screenshots and screen sharing while a one-time secret (a QR, or a link in a field) may be on it.
/// Best effort: it is the system's request that capture skip this window, not a guarantee. It is on in every build; the
/// snapshot walk and the Air rig, which have to capture the window, start the app with `CORE_ALLOW_CAPTURE=1`.
struct WindowSharingGuard: NSViewRepresentable {
    static var allowCapture: Bool { ProcessInfo.processInfo.environment["CORE_ALLOW_CAPTURE"] == "1" }

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
