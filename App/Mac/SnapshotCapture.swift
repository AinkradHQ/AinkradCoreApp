#if DEBUG
import AppKit

/// Debug only. The one capture every snapshot walk uses. The window server path (`CGWindowListCreateImage`) returns nothing
/// for a window that is not on the active Space or not on screen, which is exactly the forced full-screen main window when
/// the app was started by `open` or without focus. Then the view tree is drawn offscreen instead (`cacheDisplay`): no
/// window server, no Screen Recording permission, but live materials (blur) come out flat. Every step goes to stderr.
@MainActor
enum SnapshotCapture {
    static func png(_ window: NSWindow, to path: String) -> Bool {
        log(
            "capture win=\(window.windowNumber) fs=\(window.styleMask.contains(.fullScreen)) visible=\(window.isVisible) "
                + "occluded=\(!window.occlusionState.contains(.visible)) onActiveSpace=\(window.isOnActiveSpace) "
                + "sharing=\(window.sharingType.rawValue) frame=\(window.frame.size) -> \(path)")
        window.orderFrontRegardless()
        if let image = CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .nominalResolution])
        {
            if isBlank(image) {
                log("  window server image is blank \(image.width)x\(image.height), falling back")
            } else if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                return write(data, path)
            }
        } else {
            log("  window server returned nil, falling back")
        }
        guard let view = window.contentView?.superview ?? window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            log("  offscreen: no view or bitmap")
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("  offscreen: png encode failed")
            return false
        }
        log("  offscreen \(rep.pixelsWide)x\(rep.pixelsHigh)")
        return write(data, path)
    }

    /// The main window, waiting up to 30 s for it (a slow machine opens it late). Logs every window when it never shows.
    static func mainWindow() async -> NSWindow? {
        for _ in 0..<60 {
            if let w = NSApp.windows.first(where: { $0.title == "Ainkrad" }) {
                log("main window found fs=\(w.styleMask.contains(.fullScreen)) active=\(NSApp.isActive)")
                return w
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        log("no main window; windows: \(NSApp.windows.map { "\"\($0.title)\" \($0.frame.size)" })")
        return nil
    }

    private static func write(_ data: Data, _ path: String) -> Bool {
        do {
            try data.write(to: URL(fileURLWithPath: path))
            log("  wrote \(data.count) bytes")
            return true
        } catch {
            log("  write failed: \(error)")
            return false
        }
    }

    /// Fully transparent when scaled to a few pixels: the window server gave a hollow image.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard image.width > 1, image.height > 1 else { return true }
        var px = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let drew = px.withUnsafeMutableBytes { buf -> Bool in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        return !drew || stride(from: 3, to: px.count, by: 4).allSatisfy { px[$0] == 0 }
    }

    /// Under `open` the app's stderr is not reliably delivered, so every line also lands in `$TMPDIR`-independent
    /// `/tmp/ainkrad-snap.log` (Debug only; `scripts/air-shots.sh` prints it).
    static func log(_ s: String) {
        let line = Data("SNAP \(s)\n".utf8)
        FileHandle.standardError.write(line)
        if let h = FileHandle(forWritingAtPath: "/tmp/ainkrad-snap.log")
            ?? (FileManager.default.createFile(atPath: "/tmp/ainkrad-snap.log", contents: nil)
                ? FileHandle(forWritingAtPath: "/tmp/ainkrad-snap.log") : nil)
        {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        }
    }
}
#endif
