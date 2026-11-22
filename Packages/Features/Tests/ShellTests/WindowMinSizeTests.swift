import AppKit
import SwiftUI
import Testing

@testable import Shell

/// The window root never asks for a minimum size, in any connection, notice or lock state: the full-screen window took the
/// content's minimum as its own, and the reconnect banner's 2174 pt grew it past the screen (2026-11-22).
@MainActor
struct WindowMinSizeTests {
    private func minimum(_ setup: (ShellModel) -> Void) -> CGSize {
        _ = NSApplication.shared
        let shell = ShellModel(defaults: UserDefaults(suiteName: "window-min-\(UUID())")!)
        setup(shell)
        return NSHostingController(rootView: ShellView(shell: shell).fillsWindow()).sizeThatFits(in: .zero)
    }

    @Test(arguments: [CoreLink.none, .connecting, .live, .reconnecting, .offline])
    func noMinimumInAnyLinkState(_ link: CoreLink) {
        for lock in [AppLock.open, .locked, .checking] {
            #expect(
                minimum {
                    $0.coreLink = link
                    $0.lock = lock
                } == .zero, "\(link) \(lock)")
        }
    }

    @Test(arguments: [LinkNotice.rateLimited(until: nil), .renewing, .restarted])
    func noMinimumWithANotice(_ notice: LinkNotice) {
        #expect(minimum { $0.linkNotice = notice } == .zero)
    }
}
