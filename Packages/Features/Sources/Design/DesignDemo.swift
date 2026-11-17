#if DEBUG
import AppKit
import CryptoKit
import Foundation
import Projects
import Shell
import SwiftUI

/// Debug only: every Design state on sample data and a stand-in service, for screenshots and for the reviewer to click
/// through. Nothing here reaches a Core. The names are made up; the pictures are drawn here from SF Symbols and system
/// colours; the projects are the Projects demo's.
@MainActor
public final class DesignDemo {
    final class Service: DesignService, @unchecked Sendable {
        private let lock = NSLock()
        private var docList: [DesignDoc]
        private var assetList: [DesignAsset]
        private var kitList: [BrandKit]
        private let bytes: [String: Data]
        init(docs: [DesignDoc], assets: [DesignAsset], kits: [BrandKit], bytes: [String: Data]) {
            docList = docs
            assetList = assets
            kitList = kits
            self.bytes = bytes
        }
        func docs() async throws -> [DesignDoc] { lock.withLock { docList } }
        func assets() async throws -> [DesignAsset] { lock.withLock { assetList } }
        func kits() async throws -> [BrandKit] { lock.withLock { kitList } }
        func data(_ sha: String) async throws -> Data {
            guard let d = bytes[sha] else {
                throw DesignFailure(sentence: "That is gone.", code: "not_found", status: 404)
            }
            return d
        }
        func link(_ item: DesignItem, project: String, _ on: Bool) async throws {
            lock.withLock {
                func edit(_ p: inout [String]) {
                    p.removeAll { $0 == project }
                    if on { p.append(project) }
                    p.sort()
                }
                switch item {
                case .doc(let d): if let i = docList.firstIndex(where: { $0.id == d.id }) { edit(&docList[i].projects) }
                case .asset(let a):
                    if let i = assetList.firstIndex(where: { $0.sha == a.sha }) { edit(&assetList[i].projects) }
                case .kit(let k): if let i = kitList.firstIndex(where: { $0.id == k.id }) { edit(&kitList[i].projects) }
                }
            }
        }
    }

    public static let scenes = [
        "home", "home-hover", "screens", "brand", "icons", "illustrations", "fonts", "systems", "mockups", "needs-you",
        "drawing", "filtered", "project", "empty", "loading", "offline", "absent", "failed", "open-design",
        "open-design-menu", "open-system", "open-mockup", "open-logo", "open-icon-composer", "open-kit", "open-font",
        "project-island", "project-island-empty",
    ]

    private let model: DesignModel
    public init(model: DesignModel) { self.model = model }

    static func sha(_ name: String) -> String {
        SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func did(_ n: Int) -> String { "dd_\(String(format: "%016x", n))" }

    private static func docs() -> [DesignDoc] {
        let now = Date()
        func d(
            _ n: Int, _ kind: DesignDoc.Kind, _ name: String, _ p: [String], system: Int? = nil, hours: Double,
            paused: Bool = false
        ) -> DesignDoc {
            DesignDoc(
                id: did(n), kind: kind, name: name, system: system.map(did), projects: p, aiPaused: paused,
                createdBy: "session:as_\(String(format: "%08x", n))", updatedAt: now.addingTimeInterval(-hours * 3600))
        }
        return [
            d(1, .design, "Lanterna checkout", ["1"], system: 8, hours: 1),
            d(2, .design, "Ledger onboarding", ["2"], hours: 5, paused: true),
            d(3, .design, "Lanterna product page", ["1"], system: 8, hours: 26),
            d(4, .design, "Quill reader", ["3"], hours: 50),
            d(8, .system, "Lanterna system", ["1"], hours: 72),
            d(9, .system, "Harbor system", ["4"], hours: 200),
            d(10, .mockup, "Harbor CRM v2", ["4"], hours: 120),
        ]
    }

    private struct Sample {
        var assets: [DesignAsset] = []
        var bytes: [String: Data] = [:]
    }

    private static func sample() -> Sample {
        var s = Sample()
        let now = Date()
        func add(
            _ name: String, _ kind: DesignAsset.Kind, _ p: [String], tags: [String] = [],
            check: DesignAsset.Check = .ok,
            type: String = "image/png", data: Data?, hours: Double
        ) {
            let sha = sha(name)
            s.assets.append(
                DesignAsset(
                    sha: sha, kind: kind, name: name, contentType: type, size: Int64(data?.count ?? 48_200),
                    check: check,
                    tags: tags, projects: p, createdAt: now.addingTimeInterval(-hours * 3600)))
            if let data { s.bytes[sha] = data }
        }
        add(
            "Lanterna mark", .logo, ["1"], tags: ["brand", "mark"], data: art("lightbulb.fill", .white, .systemOrange),
            hours: 3)
        add(
            "Northwind wordmark", .logo, ["2"], tags: ["brand"],
            data: art("book.closed.fill", .white, .systemBlue), hours: 30)
        add("Cart", .icon, ["1"], tags: ["ui", "checkout"], data: art("cart", .systemGray, nil), hours: 4)
        add("Receipt", .icon, ["1"], tags: ["ui", "checkout"], data: art("receipt", .systemGray, nil), hours: 4)
        add("Bookmark", .icon, ["3"], tags: ["ui"], data: art("bookmark", .systemGray, nil), hours: 60)
        add(
            "Lanterna app icon", .iconComposer, ["1"], tags: ["app icon"], type: "application/zip", data: iconZip(),
            hours: 8)
        add(
            "Quill app icon", .iconComposer, ["3"], tags: ["app icon"], check: .pending, type: "application/zip",
            data: nil, hours: 2)
        add(
            "Empty cart scene", .image, ["1"], tags: ["empty state"],
            data: art("cart.badge.questionmark", .systemOrange, nil), hours: 20)
        add(
            "Reading nook", .image, ["3"], tags: ["empty state"], data: art("books.vertical", .systemBrown, nil),
            hours: 90)
        add("Lanterna Serif Bold", .font, ["1"], check: .pending, type: "font/ttf", data: nil, hours: 6)
        add("Harbor Sans", .font, ["4"], check: .pending, type: "font/otf", data: nil, hours: 100)
        add("Quill Text Italic", .font, ["3"], check: .refused, type: "font/ttf", data: nil, hours: 70)
        return s
    }

    private static func kits() -> [BrandKit] {
        let now = Date()
        return [
            BrandKit(
                id: "dc_\(String(format: "%016x", 1))", name: "Lanterna brand kit",
                colors: ["#2b2520", "#e3a857", "#e9dfcf", "#f7f2ea", "#8c8174"],
                fonts: [sha("Lanterna Serif Bold")],
                items: [
                    .init(sha: sha("Lanterna mark"), role: "logo"),
                    .init(sha: sha("Lanterna app icon"), role: "app icon"),
                ],
                projects: ["1"], updatedAt: now.addingTimeInterval(-2 * 3600)),
            BrandKit(
                id: "dc_\(String(format: "%016x", 2))", name: "Northwind brand kit",
                colors: ["#1d3557", "#457b9d", "#f1faee"], fonts: [],
                items: [.init(sha: sha("Northwind wordmark"), role: "logo")], projects: ["2"],
                updatedAt: now.addingTimeInterval(-40 * 3600)),
        ]
    }

    /// A stand-in picture: an SF Symbol on a soft tile, as PNG bytes.
    private static func art(_ symbol: String, _ ink: NSColor, _ tile: NSColor?) -> Data? {
        let size = NSSize(width: 256, height: 256)
        let img = NSImage(size: size, flipped: false) { r in
            if let tile {
                tile.setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 16, dy: 16), xRadius: 56, yRadius: 56).fill()
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: 120, weight: .regular)
                .applying(.init(paletteColors: [ink]))
            if let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let o = NSPoint(x: (r.width - s.size.width) / 2, y: (r.height - s.size.height) / 2)
                s.draw(at: o, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// A made-up Icon Composer file: one SVG layer in a `.icon` bundle, zipped the way the Core stores it.
    private static func iconZip() -> Data? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ainkrad-demo-icon-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let bundle = dir.appendingPathComponent("Lamp.icon/Assets", isDirectory: true)
        try? fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="34" y="20" width="32" height="44" rx="12" \
            fill="#e3a857"/><rect x="44" y="64" width="12" height="18" rx="4" fill="#f7f2ea"/></svg>
            """
        let json = """
            {"fill":"automatic","groups":[{"layers":[{"image-name":"lamp.svg","name":"lamp"}]}],\
            "supported-platforms":{"squares":"shared"}}
            """
        try? Data(svg.utf8).write(to: bundle.appendingPathComponent("lamp.svg"))
        try? Data(json.utf8).write(to: dir.appendingPathComponent("Lamp.icon/icon.json"))
        let zip = dir.appendingPathComponent("lamp.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", dir.appendingPathComponent("Lamp.icon").path, zip.path]
        try? p.run()
        p.waitUntilExit()
        return try? Data(contentsOf: zip)
    }

    /// For clicking through by hand.
    public func showInteractive(_ scene: String) async { await show(scene) }

    public func show(_ scene: String) async {
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.linkNotice = nil
        shell.coreLink = .live
        shell.home.coreName = "core-oracle"
        shell.closePane("projects")
        model.filter = ""
        model.project = nil
        model.category = .all
        model.openID = nil
        model.debugHover = nil
        model.projectsMenuOpen = false
        await ProjectsDemo(model: model.projectsModel).loadSample()
        let s = Self.sample()
        let empty = scene == "empty" || scene == "project-island-empty"
        await model.useNow(
            Service(
                docs: empty ? [] : Self.docs(), assets: empty ? [] : s.assets, kits: empty ? [] : Self.kits(),
                bytes: s.bytes))
        if scene.hasPrefix("project-island") {
            shell.closePane("design")
            await ProjectsDemo(model: model.projectsModel).show("overview-running")
            return
        }
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "home-hover": model.debugHover = DesignItem.doc(Self.docs()[0]).id
        case "screens": model.category = .screens
        case "brand": model.category = .brand
        case "icons": model.category = .icons
        case "illustrations": model.category = .illustrations
        case "fonts": model.category = .fonts
        case "systems": model.category = .systems
        case "mockups": model.category = .mockups
        case "needs-you": model.category = .needsYou
        case "drawing": model.category = .drawing
        case "filtered": model.filter = "checkout"
        case "project": model.project = "1"
        case "loading": model.load = .loading
        case "offline": model.load = .notConnected
        case "absent": model.load = .absent
        case "failed": model.load = .failed("The Core did not answer in time (timeout).")
        case "open-design", "open-design-menu": model.openID = "doc:\(Self.did(1))"
        case "open-system": model.openID = "doc:\(Self.did(8))"
        case "open-mockup": model.openID = "doc:\(Self.did(10))"
        case "open-logo": model.openID = "asset:\(Self.sha("Lanterna mark"))"
        case "open-icon-composer": model.openID = "asset:\(Self.sha("Lanterna app icon"))"
        case "open-kit": model.openID = "kit:dc_\(String(format: "%016x", 1))"
        case "open-font": model.openID = "asset:\(Self.sha("Lanterna Serif Bold"))"
        default: break
        }
        if scene == "open-design-menu" {
            try? await Task.sleep(for: .milliseconds(300))
            model.projectsMenuOpen = true
        }
    }
}

extension DesignModel {
    /// Debug only: attaches a stand-in service and reads it before returning (no background reload to race a scene).
    func useNow(_ s: any DesignService) async {
        service = s
        load = .loading
        await reload()
    }
}
#endif
