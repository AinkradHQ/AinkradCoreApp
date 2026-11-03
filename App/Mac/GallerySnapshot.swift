#if DEBUG
import AppKit
import CoreUI
import SwiftUI

/// Debug only. `CORE_GALLERY_SNAPSHOT=<dir> [CORE_THEME=light|dark]` opens the CoreUI gallery in its own window, scrolls it a
/// page at a time, captures each page of its own window and quits. No key events.
@MainActor
enum GallerySnapshot {
    static func run(dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: frame.minX, y: frame.minY, width: 900, height: frame.height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: CoreUIGallery())
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
                try? png.write(to: URL(fileURLWithPath: "\(dir)/gallery-\(n)-\(theme).png"))
            }
            y += page
            n += 1
            if y >= height || n > 8 { break }
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
