import AppKit
import Shell
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
    @MainActor private static var settled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, tokens.isEmpty else { return }
        Self.pin(window)
        NSApp.appearance = ThemeChoice.stored().appearance  // the saved Day/Night choice, before anything is drawn
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
        // Mission Control's Spaces bar can drag this Space onto another (Split View tiles both, so the window shrinks to half
        // the screen) or onto a Desktop (it leaves full screen). No notification names the tiling, so every resize and every
        // screen change re-checks that the window still fills its screen, and puts things right if not.
        for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            tokens.append(
                center.addObserver(forName: name, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        Self.pin(window)
                        Self.restoreIfTiled(window)
                    }
                })
        }
        // The enter/exit animation resizes the window too; only a settled full-screen window is checked.
        for (name, to) in [
            (NSWindow.willEnterFullScreenNotification, false), (NSWindow.willExitFullScreenNotification, false),
            (NSWindow.didEnterFullScreenNotification, true),
        ] {
            tokens.append(
                center.addObserver(forName: name, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        Self.settled = to
                        if to { Self.hideChrome(window) }
                        if to {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                MainActor.assumeIsolated { Self.restoreIfTiled(window) }
                            }
                        }
                    }
                })
        }
        // Entering needs a key window in an active app, so try again whenever either becomes true.
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            tokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated {
                        if let window {
                            Self.enter(window)
                            Self.hideChrome(window)
                        }
                    }
                })
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            MainActor.assumeIsolated { if let window { Self.enter(window) } }
        }
    }

    /// No tiling, and a minimum size of the whole screen: macOS does not tile (Split View, window tiling) a window that cannot
    /// shrink to half, so this holds even if the collection behaviour is reset. Re-applied on every resize and screen change.
    @MainActor private static func pin(_ window: NSWindow) {
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenDisallowsTiling]
        if let size = (window.screen ?? NSScreen.main)?.frame.size, window.contentMinSize != size {
            window.contentMinSize = size
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    /// In full screen but narrower than the screen: tiled. Leaving full screen makes `didExitFullScreen` bring it straight back.
    @MainActor private static func restoreIfTiled(_ window: NSWindow) {
        guard settled, window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
        guard window.frame.width < screen.frame.width - 1 else { return }
        window.toggleFullScreen(nil)
    }

    @MainActor private static func enter(_ window: NSWindow) {
        guard window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    /// No title bar strip (traffic lights) and no menu bar sliding down when the pointer reaches the top edge (Ahmed,
    /// 2026-11-05). Menu commands stay on their shortcuts and in the launcher. Re-applied on every activation, because the
    /// options only hold while the app is frontmost.
    @MainActor static func hideChrome(_ window: NSWindow) {
        guard window.styleMask.contains(.fullScreen) else { return }
        NSApp.presentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
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
