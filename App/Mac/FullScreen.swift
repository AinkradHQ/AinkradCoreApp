import AppKit
import SwiftUI

/// Plan D9: the main window is full screen only. It launches into native full screen (its own Space), has no way out
/// (no Exit Full Screen / Zoom menu items, no ⌃⌘F, green button disabled) and re-enters full screen if anything leaves it.
/// The Debug gallery window does not use this.
struct FullScreenEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { EnforcerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class EnforcerView: NSView {
    private var tokens: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, tokens.isEmpty else { return }
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenDisallowsTiling]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { Self.enter(window) }
            })
        tokens.append(
            center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Self.scrubMenus() }
            })
        // Entering needs a key window in an active app, so try again whenever either becomes true.
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            tokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated { if let window { Self.enter(window) } }
                })
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            MainActor.assumeIsolated { if let window { Self.enter(window) } }
        }
    }

    @MainActor private static func enter(_ window: NSWindow) {
        guard window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    /// Removes the system's way out: Enter/Exit Full Screen (and its ⌃⌘F), Zoom.
    @MainActor private static func scrubMenus() {
        guard let main = NSApp.mainMenu else { return }
        func scrub(_ menu: NSMenu) {
            for item in menu.items.reversed() {
                if item.action == #selector(NSWindow.toggleFullScreen(_:))
                    || item.action == #selector(NSWindow.zoom(_:))
                {
                    menu.removeItem(item)
                } else if let sub = item.submenu {
                    scrub(sub)
                }
            }
        }
        scrub(main)
    }
}
