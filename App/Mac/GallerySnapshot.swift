#if DEBUG
import AppKit
import CoreUI
import SwiftUI

/// Debug only. `CORE_GALLERY_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_GALLERY_ONLY=official]` opens the CoreUI gallery in its own window, scrolls it a
/// page at a time, captures each page of its own window and quits. No key events.
@MainActor
enum GallerySnapshot {
    private static var openWindow: NSWindow?

    /// `CORE_OPEN_GALLERY=1 [CORE_GALLERY_ONLY=official]`: opens the gallery at launch, scrolled to the Official Liquid Glass
    /// section, and keeps running (no capture, no quit) so someone can look at it.
    static func open(env: [String: String]) async {
        try? await Task.sleep(for: .seconds(2))
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: frame.minX, y: frame.minY, width: 960, height: frame.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "CoreUI Gallery"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: CoreUIGallery(officialOnly: env["CORE_GALLERY_ONLY"] == "official", scrollToOfficial: true))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        openWindow = window
    }

    static func run(dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: frame.minX, y: frame.minY, width: 900, height: frame.height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let only = env["CORE_GALLERY_ONLY"] == "official"
        let prefix = only ? "official" : "gallery"
        window.contentView = NSHostingView(rootView: CoreUIGallery(officialOnly: only))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(2))
        let scroll = findScroll(window.contentView)
        let height = scroll?.documentView?.frame.height ?? 0
        let page = scroll?.contentView.bounds.height ?? frame.height
        var y = 0.0
        var n = 1
        while true {
            scroll?.contentView.scroll(to: NSPoint(x: 0, y: y))
            if let s = scroll { s.reflectScrolledClipView(s.contentView) }
            try? await Task.sleep(for: .seconds(1.2))
            if let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution]),
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(prefix)-\(n)-\(theme).png"))
            }
            y += page
            n += 1
            if y >= height || n > 24 { break }
        }
        NSApp.terminate(nil)
    }

    private static func findScroll(_ v: NSView?) -> NSScrollView? {
        guard let v else { return nil }
        if let s = v as? NSScrollView { return s }
        for sub in v.subviews { if let s = findScroll(sub) { return s } }
        return nil
    }
}
#endif
