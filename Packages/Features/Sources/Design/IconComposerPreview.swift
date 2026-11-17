import AppKit
import Foundation

/// The picture of an Icon Composer file (`.icon` bundle, stored as one zip). With Xcode's Icon Composer installed, its
/// `ictool` renders the real icon in the Default look; without it the bundle's first PNG or SVG layer stands in. Everything
/// runs in child processes (`ditto`, `ictool`) on a fresh temporary folder; only the resulting PNG/SVG is read here.
/// Results are cached per sha256 under Caches, so each file renders once per Mac.
/// Only ever called for a file the Core has passed (`check_state = ok`): the design helper (V6-01) checked the zip first.
enum IconComposerPreview {
    static func image(zip: Data, sha: String) async -> NSImage? {
        await Task.detached(priority: .utility) { render(zip: zip, sha: sha) }.value
    }

    static var ictool: URL? {
        let dev = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dev.isEmpty else { return nil }
        let url = URL(fileURLWithPath: dev).deletingLastPathComponent()
            .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static func render(zip: Data, sha: String) -> NSImage? {
        guard sha.allSatisfy(\.isHexDigit) else { return nil }
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ainkrad.core/design-icons", isDirectory: true)
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let cached = cache.appendingPathComponent("\(sha).png")
        if let img = NSImage(contentsOf: cached) { return img }

        let work = fm.temporaryDirectory.appendingPathComponent("ainkrad-icon-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return nil }
        let zipURL = work.appendingPathComponent("in.zip")
        let out = work.appendingPathComponent("x", isDirectory: true)
        guard (try? zip.write(to: zipURL)) != nil else { return nil }
        _ = run("/usr/bin/ditto", ["-x", "-k", zipURL.path, out.path])
        guard let bundle = iconBundle(in: out) else { return nil }

        if let tool = ictool {
            let png = work.appendingPathComponent("out.png")
            _ = run(
                tool.path,
                [
                    bundle.path, "--export-image", "--output-file", png.path, "--platform", "macOS", "--rendition",
                    "Default", "--width", "256", "--height", "256", "--scale", "2",
                ])
            if let img = NSImage(contentsOf: png) {
                try? fm.copyItem(at: png, to: cached)
                return img
            }
        }
        return firstLayer(in: bundle)
    }

    /// The `.icon` folder (or the folder holding `icon.json`), at most two levels down. Links are not followed.
    static func iconBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("icon.json").path) { return root }
        let kids = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for k in kids.sorted(by: { $0.path < $1.path }) where !isLink(k) {
            if k.pathExtension == "icon" || fm.fileExists(atPath: k.appendingPathComponent("icon.json").path) {
                return k
            }
        }
        for k in kids where !isLink(k) {
            let inner = (try? fm.contentsOfDirectory(at: k, includingPropertiesForKeys: nil)) ?? []
            if let b = inner.first(where: { $0.pathExtension == "icon" && !isLink($0) }) { return b }
        }
        return nil
    }

    /// The first PNG or SVG under `Assets/`, by name.
    static func firstLayer(in bundle: URL) -> NSImage? {
        let assets = bundle.appendingPathComponent("Assets", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)) ?? []
        let layer = files.filter { ["png", "svg"].contains($0.pathExtension.lowercased()) && !isLink($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        return layer.flatMap { NSImage(contentsOf: $0) }
    }

    private static func isLink(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    /// Runs a tool and returns its standard output; gives up after 20 s.
    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let stop = DispatchWorkItem { [p] in if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: stop)
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        stop.cancel()
        return String(decoding: out, as: UTF8.self)
    }
}
