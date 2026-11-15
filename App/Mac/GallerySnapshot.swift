#if DEBUG
import AppKit
import CoreUI
import SwiftUI

/// Debug only. `CORE_GALLERY_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_GALLERY_ONLY=<section,section>]` opens the
/// component gallery in its own window, shows each section in turn, captures it a page at a time and quits. No key events.
@MainActor
enum GallerySnapshot {
    private static var openWindow: NSWindow?

    /// `CORE_OPEN_GALLERY=1 [CORE_GALLERY_ONLY=<section>]`: opens the gallery at launch on that section and keeps running
    /// (no capture, no quit) so someone can look at it.
    static func open(env: [String: String]) async {
        try? await Task.sleep(for: .seconds(2))
        let section = sections(env).first ?? .foundations
        let window = makeWindow(CoreUIGallery(section: section))
        window.title = "CoreUI Gallery"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        openWindow = window
    }

    static func run(dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        if env["CORE_GALLERY_MATRIX"] == "1" {
            // Every style on one screen under each accent, each wallpaper and each scenario.
            // A throwaway first capture: the first window can be captured before it has drawn.
            await capture(CoreUIGallery(section: .styles, theme: theme), "matrix-warmup", dir)
            let accent = AccentPrefs.shared.accent
            let wall = WallpaperPrefs.shared.choice
            for a in CoreAccent.allCases {
                AccentPrefs.shared.accent = a
                await capture(
                    CoreUIGallery(section: .styles, theme: theme), "matrix-accent-\(a.rawValue)-\(theme)", dir)
            }
            AccentPrefs.shared.accent = accent
            for w in CoreWallpaper.presets {
                WallpaperPrefs.shared.choice = w
                await capture(CoreUIGallery(section: .styles, theme: theme), "matrix-wall-\(w.rawValue)-\(theme)", dir)
            }
            WallpaperPrefs.shared.choice = wall
            await capture(
                CoreUIGallery(section: .styles, theme: theme, contrast: true), "matrix-contrast-\(theme)", dir)
            await capture(CoreUIGallery(section: .styles, theme: theme, solid: true), "matrix-solid-\(theme)", dir)
            await capture(CoreUIGallery(section: .styles, theme: theme, rtl: true), "matrix-rtl-\(theme)", dir)
        } else {
            for (i, section) in sections(env).enumerated() {
                await capture(
                    CoreUIGallery(section: section, theme: theme), String(format: "%02d-%@", i + 1, section.rawValue),
                    dir, theme: theme, pages: true)
            }
        }
        NSApp.terminate(nil)
    }

    /// Opens `view` in its own window and captures it: the first screen, or every page when `pages`.
    private static func capture(
        _ view: CoreUIGallery, _ name: String, _ dir: String, theme: String? = nil, pages: Bool = false
    ) async {
        let window = makeWindow(view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(2))
        let scroll = findScroll(window.contentView)
        let height = scroll?.documentView?.frame.height ?? 0
        let page = max(scroll?.contentView.bounds.height ?? 800, 200)
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
                let file = pages ? "\(name)-\(n)-\(theme ?? "")" : name
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(file).png"))
            }
            y += page
            n += 1
            if !pages || y >= height || n > 12 { break }
        }
        window.close()
    }

    private static func sections(_ env: [String: String]) -> [GallerySection] {
        let only = (env["CORE_GALLERY_ONLY"] ?? "").split(separator: ",").compactMap {
            GallerySection(rawValue: String($0))
        }
        return only.isEmpty ? GallerySection.allCases : only
    }

    private static func makeWindow<V: View>(_ view: V) -> NSWindow {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: frame.minX, y: frame.minY, width: min(1400, frame.width), height: frame.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private static func findScroll(_ v: NSView?) -> NSScrollView? {
        guard let v else { return nil }
        if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > 400 { return s }
        for sub in v.subviews { if let s = findScroll(sub) { return s } }
        return nil
    }
}
#endif
