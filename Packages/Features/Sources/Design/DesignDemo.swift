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
        // Collaboration and library writes, in memory.
        private var commentList: [DesignComment] = []
        private var approvalList: [String: [ScreenApproval]] = [:]
        private var archivedList: [DesignDoc] = []
        func seed(comments: [DesignComment], approvals: [String: [ScreenApproval]], archived: [DesignDoc]) {
            lock.withLock {
                commentList = comments
                approvalList = approvals
                archivedList = archived
            }
        }
        func archivedDocs() async throws -> [DesignDoc] { lock.withLock { archivedList } }
        func unarchive(doc: String) async throws {
            lock.withLock {
                if let i = archivedList.firstIndex(where: { $0.id == doc }) {
                    var d = archivedList.remove(at: i)
                    d.archived = false
                    docList.append(d)
                }
            }
        }
        func comments(doc: String) async throws -> [DesignComment] { lock.withLock { commentList } }
        func postComment(doc: String, _ new: NewDesignComment) async throws -> DesignComment {
            lock.withLock {
                let c = DesignComment(
                    id: "dc_\(commentList.count + 1)", screen: new.screen, body: new.body, author: "d_you",
                    createdAt: Date(), node: new.node, parent: new.parent, resolvedAt: nil)
                commentList.append(c)
                return c
            }
        }
        func resolveComment(doc: String, id: String, resolved: Bool) async throws {
            lock.withLock {
                if let i = commentList.firstIndex(where: { $0.id == id }) {
                    let c = commentList[i]
                    commentList[i] = DesignComment(
                        id: c.id, screen: c.screen, body: c.body, author: c.author, createdAt: c.createdAt,
                        node: c.node, parent: c.parent, resolvedAt: resolved ? Date() : nil)
                }
            }
        }
        func approvals(doc: String) async throws -> [ScreenApproval] { lock.withLock { approvalList[doc] ?? [] } }
        func approve(doc: String, screen: String) async throws {
            lock.withLock {
                approvalList[doc, default: []].removeAll { $0.screen == screen }
                approvalList[doc, default: []].append(
                    ScreenApproval(
                        screen: screen, version: "dv_1", state: .approved, decidedBy: "d_you", decidedAt: Date()))
            }
        }
        func withdrawApproval(doc: String, screen: String) async throws {
            lock.withLock { approvalList[doc, default: []].removeAll { $0.screen == screen } }
        }
        func setTags(sha: String, tags: [String]) async throws -> DesignAsset {
            lock.withLock {
                let i = assetList.firstIndex { $0.sha == sha }!
                assetList[i].tags = tags
                return assetList[i]
            }
        }
        func setSystem(doc: String, system: String?) async throws -> DesignDoc {
            lock.withLock {
                let i = docList.firstIndex { $0.id == doc }!
                docList[i].system = system
                return docList[i]
            }
        }
        func pauseAI(doc: String) async throws -> DesignDoc { try await ai(doc, true) }
        func takeOver(doc: String) async throws -> DesignDoc { try await ai(doc, true) }
        func resumeAI(doc: String) async throws -> DesignDoc { try await ai(doc, false) }
        private func ai(_ doc: String, _ paused: Bool) async throws -> DesignDoc {
            lock.withLock {
                let i = docList.firstIndex { $0.id == doc }!
                docList[i].aiPaused = paused
                return docList[i]
            }
        }
        func patchKit(id: String, name: String?, colors: [String]?, fonts: [String]?) async throws -> BrandKit {
            lock.withLock {
                let i = kitList.firstIndex { $0.id == id }!
                if let name { kitList[i].name = name }
                if let colors { kitList[i].colors = colors }
                if let fonts { kitList[i].fonts = fonts }
                return kitList[i]
            }
        }
        func putKitItem(id: String, sha: String, role: String?) async throws {
            lock.withLock {
                let i = kitList.firstIndex { $0.id == id }!
                kitList[i].items.removeAll { $0.sha == sha }
                kitList[i].items.append(.init(sha: sha, role: role))
            }
        }
        func removeKitItem(id: String, sha: String) async throws {
            lock.withLock { kitList[kitList.firstIndex { $0.id == id }!].items.removeAll { $0.sha == sha } }
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
        "home", "home-hover", "screens", "brand", "icons", "illustrations", "fonts", "systems", "mockups", "library",
        "capped", "refresh-failed", "image-failed", "filtered", "project", "empty", "loading", "offline", "absent",
        "failed", "open-design",
        "open-design-menu", "open-system", "open-mockup", "open-logo", "open-icon-composer", "open-kit", "open-font",
        "project-island", "project-island-empty", "project-island-offline", "new-advanced", "new-mockup",
        "save-reconnecting", "save-halted", "save-saving", "present-empty", "rename", "delete",
        "open-design-insert", "open-design-text", "editor-selftest", "tools-probe", "ai-new", "ai-edit", "ai-drawing",
        "ai-directions", "ai-done", "ai-drawing-new", "present-phone", "present-desktop", "system-empty",
        "system-guide", "system-guide-night", "comments", "approval", "ai-paused", "archived", "archived-old-core",
        "open-folder", "new-kit", "library-upload", "multi-select", "sort-favourites", "open-design-about",
        "add-token", "delete-bulk", "tools-selftest", "tools-zoom", "tools-pages", "tools-cursors",
        "tools-follow", "tools-shortcuts", "tools-paste", "tools-text", "ai-over-limit", "ai-flow",
        "system-replace-confirm", "tools-rotate", "tools-locked", "tools-effects", "tools-strokes",
        "tools-effects-look",
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
                id: "dc_\(String(format: "%016x", 3))", name: "Illustrations",
                colors: [], fonts: [],
                items: [
                    .init(sha: sha("Empty cart scene"), role: nil), .init(sha: sha("Reading nook"), role: nil),
                ], projects: ["1"], updatedAt: now.addingTimeInterval(-10 * 3600), kind: .folder),
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
        model.debugCommentsOpen = false
        model.debugAddTokenOpen = false
        model.lib.reset()
        model.lib.sort = .recent
        model.lib.favouritesFirst = false
        model.lib.favourites = []
        model.projectsMenuOpen = false
        await ProjectsDemo(model: model.projectsModel).loadSample()
        let s = Self.sample()
        let empty = scene == "empty" || scene == "project-island-empty" || scene == "project-island-offline"
        let svc = Service(
            docs: empty ? [] : Self.docs(), assets: empty ? [] : s.assets, kits: empty ? [] : Self.kits(),
            bytes: s.bytes)
        svc.seed(
            comments: [], approvals: [:],
            archived: [
                DesignDoc(
                    id: Self.did(20), kind: .design, name: "Old onboarding", system: nil, projects: ["2"],
                    aiPaused: false,
                    createdBy: "d_you", updatedAt: Date().addingTimeInterval(-400 * 3600), archived: true),
                DesignDoc(
                    id: Self.did(21), kind: .design, name: "Pricing experiment", system: nil, projects: ["1"],
                    aiPaused: false, createdBy: "session:as_00000021",
                    updatedAt: Date().addingTimeInterval(-900 * 3600), archived: true),
            ])
        await model.useNow(svc)
        model.debugSystemAsk = false
        model.debugSave = nil
        model.refreshFailure = nil
        model.docsCapped = false
        model.failedImages = []
        if scene == "project-island-offline" { model.load = .failed("The Core did not answer in time.") }
        // Scenes share one run: nothing from the scene before (AI panel, dialog) may stay open.
        model.composer?.shutdown()
        model.composer = nil
        model.host.shell.closeDialog()
        if scene.hasPrefix("project-island") {
            shell.closePane("design")
            await ProjectsDemo(model: model.projectsModel).show("overview-running")
            return
        }
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        model.presenter = nil  // scenes share one run: Present from the scene before must not stay open
        if scene == "add-token" { model.debugAddTokenOpen = true }
        switch scene {
        case "home-hover": model.debugHover = DesignItem.doc(Self.docs()[0]).id
        case "screens": model.category = .screens
        case "brand": model.category = .brand
        case "icons": model.category = .icons
        case "illustrations": model.category = .illustrations
        case "fonts": model.category = .fonts
        case "systems": model.category = .systems
        case "mockups": model.category = .mockups
        case "library": model.category = .library
        case "capped":
            model.docsCapped = true
        case "refresh-failed": model.refreshFailure = "The Core did not answer in time."
        case "image-failed":
            model.category = .library
            for a in s.assets where a.loadable { model.failedImages.insert(a.sha) }
        case "filtered": model.filter = "checkout"
        case "project": model.project = "1"
        case "loading": model.load = .loading
        case "offline": model.load = .notConnected
        case "absent": model.load = .absent
        case "failed": model.load = .failed("The Core did not answer in time (timeout).")
        case "open-design", "open-design-menu", "open-design-insert", "open-design-text", "editor-selftest", "ai-new",
            "ai-edit", "ai-drawing", "ai-directions", "ai-done", "ai-drawing-new", "present-phone", "present-desktop",
            "tools-probe", "tools-selftest", "tools-zoom", "tools-pages", "tools-cursors", "tools-follow",
            "tools-shortcuts", "tools-paste", "tools-text", "ai-over-limit", "ai-flow", "tools-rotate", "tools-locked",
            "tools-effects", "tools-strokes", "tools-effects-look", "save-reconnecting", "save-halted", "save-saving",
            "present-empty":
            model.openID = "doc:\(Self.did(1))"
        case "open-design-about", "comments", "approval": model.openID = "doc:\(Self.did(1))"
        case "open-system", "system-empty", "system-guide", "system-guide-night", "add-token", "system-replace-confirm":
            model.openID = "doc:\(Self.did(8))"
        case "open-mockup": model.openID = "doc:\(Self.did(10))"
        case "open-logo": model.openID = "asset:\(Self.sha("Lanterna mark"))"
        case "open-icon-composer": model.openID = "asset:\(Self.sha("Lanterna app icon"))"
        case "ai-paused": model.openID = "doc:\(Self.did(2))"
        case "archived", "archived-old-core":
            model.lib.restoreSupported = scene == "archived"
            model.pick(.archived)
            await model.lib.loadArchived()
        case "open-folder": model.openID = "kit:dc_\(String(format: "%016x", 3))"
        case "library-upload":
            model.category = .illustrations
            model.lib.uploads = [
                .init(name: "Hero.png", state: .uploading), .init(name: "Logo.svg", state: .done(duplicate: false)),
                .init(name: "Cart.png", state: .done(duplicate: true)),
                .init(name: "notes.exe", state: .failed("Only images, SVG, PDF and fonts can be added.")),
            ]
        case "multi-select":
            let list = model.shown
            model.lib.multi = Set(list.prefix(3).map(\.id))
            model.lib.favourites = [list[1].id]
        case "sort-favourites":
            model.lib.sort = .name
            model.lib.favouritesFirst = true
            model.lib.favourites = [DesignItem.doc(Self.docs()[3]).id]
        case "delete-bulk": break
        case "open-kit": model.openID = "kit:dc_\(String(format: "%016x", 1))"
        case "open-font": model.openID = "asset:\(Self.sha("Lanterna Serif Bold"))"
        default: break
        }
        if scene == "new-advanced" { model.openNew() }
        if scene == "new-mockup" { model.openNew(kind: .mockup) }
        switch scene {
        case "save-reconnecting": model.debugSave = .reconnecting
        case "save-halted": model.debugSave = .notSaving
        case "save-saving": model.debugSave = .saving
        default: break
        }
        if scene == "new-kit" {
            model.host.shell.present(ShellDialog(id: "new-kit") { NewKitView(model: model, kind: .brandKit) })
        }
        if scene == "delete-bulk" { model.askDelete(Array(model.shown.prefix(3))) }
        if scene == "open-design-about" {
            try? await Task.sleep(for: .seconds(2))
            model.aboutOpen = true
        }
        if scene == "comments" || scene == "approval" {
            // On the real canvas (CORE_DESIGN_SCENE): the screens' ids are the engine's, so the notes are written then.
            try? await Task.sleep(for: .seconds(2))
            if let e = model.editors[Self.did(1)], let screen = e.screens.first {
                let now = Date()
                func note(_ i: Int, _ body: String, by: String, parent: String? = nil, done: Bool = false)
                    -> DesignComment
                {
                    DesignComment(
                        id: "dc_\(i)", screen: screen.id, body: body, author: by,
                        createdAt: now.addingTimeInterval(Double(-i) * 1800),
                        node: nil, parent: parent, resolvedAt: done ? now : nil)
                }
                svc.seed(
                    comments: [
                        note(1, "The primary button is too close to the total. Can it have more air?", by: "d_you"),
                        note(2, "Moved it 16 pt down.", by: "session:as_00000001", parent: "dc_1"),
                        note(3, "Use the system's warning colour for the stock note.", by: "d_ada"),
                        note(4, "Title is fine now.", by: "d_you", done: true),
                    ],
                    approvals: [
                        Self.did(1): [
                            ScreenApproval(
                                screen: screen.id, version: "dv_1", state: scene == "approval" ? .changed : .approved,
                                decidedBy: "d_you", decidedAt: now.addingTimeInterval(-7200))
                        ]
                    ], archived: [])
                await model.collab.load(Self.did(1))
                if scene == "approval" { e.select(screen.id) } else { model.debugCommentsOpen = true }
            }
        }
        if scene == "tools-probe" {
            try? await Task.sleep(for: .seconds(2))
            await model.debugCanvasProbe?({ FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
        }
        if scene == "editor-selftest" {
            try? await Task.sleep(for: .seconds(2))
            if let e = model.editors[Self.did(1)] {
                EditorSelfTest.run(e) { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            } else {
                FileHandle.standardError.write(Data("SELFTEST ABORT no editor\n".utf8))
            }
        }
        if scene == "open-design-insert" || scene == "open-design-text" {
            // Probe: the real canvas (CORE_DESIGN_SCENE) takes an insert and selects it.
            try? await Task.sleep(for: .seconds(2))
            if let e = model.editors[Self.did(1)] {
                let before = e.layers.layers.count
                // Every kind once, then the rectangle last so the inspector shows it.
                for p in InsertPreset.shapes.dropFirst() + InsertPreset.texts.prefix(1) { e.insert(p) }
                e.select("", quiet: true)
                let ok = e.insert(scene == "open-design-text" ? InsertPreset.texts[0] : InsertPreset.shapes[0])
                let line =
                    "PROBE attached=\(e.attached) before=\(before) insert=\(ok) after=\(e.layers.layers.count) "
                    + "sel=\(e.selection) notice=\(e.notice ?? "-")\n"
                FileHandle.standardError.write(Data(line.utf8))
            } else {
                FileHandle.standardError.write(Data("PROBE no editor\n".utf8))
            }
        }
        if scene.hasPrefix("tools-") { await tools(scene) }
        if scene == "rename" { model.askRename(.doc(Self.docs()[0])) }
        if scene == "present-empty" {
            try? await Task.sleep(for: .seconds(1))
            if let item = model.open, case .doc(let d) = item {
                model.present(d)
                try? await Task.sleep(for: .seconds(3))  // after the real open settles
                model.presenter?.debugPhase(.empty)
            }
        } else if scene.hasPrefix("present-") {
            // Present on the real canvas (CORE_DESIGN_SCENE): the scene's frame in a phone, or as a desktop in a browser.
            try? await Task.sleep(for: .seconds(2))
            if let item = model.open, case .doc(let d) = item {
                model.present(d)
                if scene == "present-phone" { model.presenter?.device = .phone }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        if scene == "system-replace-confirm" {
            // A system that already has tokens: Generate asks before replacing them.
            // The guide opens with the confirmation armed, then the system gets its tokens (the label counts them live).
            model.debugSystemAsk = true
            model.openID = nil
            try? await Task.sleep(for: .milliseconds(300))
            model.openID = "doc:\(Self.did(8))"
            try? await Task.sleep(for: .seconds(2))
            model.editors[Self.did(8)]?.setTokens(SystemStarter.tokens)
            try? await Task.sleep(for: .seconds(2))
        }
        if scene == "system-guide" || scene == "system-guide-night" || scene == "add-token" {
            // The style guide on the real engine (CORE_DESIGN_SCENE): the default set written as token ops.
            try? await Task.sleep(for: .seconds(2))
            model.editors[Self.did(8)]?.setTokens(SystemStarter.tokens)
            try? await Task.sleep(for: .seconds(1))
        }
        if scene.hasPrefix("ai-") {
            // The AI panel on the real canvas (CORE_DESIGN_SCENE): new, edit, drawing, directions, done.
            try? await Task.sleep(for: .seconds(2))
            let e = model.editors[Self.did(1)]
            if scene != "ai-new", scene != "ai-drawing-new",
                let frame = e?.layers.layers.first(where: { $0.type == "frame" })
            {
                e?.select(frame.id)
            }
            await model.drawWithAI()
            // As a person would: the panel opens, then the drawing starts.
            try? await Task.sleep(for: .milliseconds(500))
            let c = model.composer
            let three = ComposeState(
                id: "dc_1", phase: .done, reason: "", session: nil,
                directions: [
                    .init(
                        name: "Calm", summary: "A light, airy layout with soft cards and one blue accent.", frame: nil),
                    .init(
                        name: "Bold", summary: "A dark, poster-style layout with huge type and a lime accent.",
                        frame: nil),
                    .init(name: "Editorial", summary: "A warm, paper-like layout with a serif name.", frame: nil),
                ])
            switch scene {
            case "ai-new": c?.prompt = ""
            case "ai-over-limit":
                c?.target = nil
                c?.prompt = String(repeating: "A calm sign-in screen with a big logo and a short welcome. ", count: 11)
            case "ai-flow":
                c?.target = nil
                c?.prompt = "An onboarding flow"
                let ids = (1...3).map { "n_flow\($0)" }
                let flow = ComposeState(
                    id: "dc_1", phase: .done, reason: "", session: nil,
                    directions: [.init(name: "Onboarding", summary: "Three steps", frame: ids[0], screens: ids)],
                    flow: true)
                c?.debugShow(flow, phase: .done("3 screens are on the canvas."))
            case "ai-edit": c?.prompt = "Make the button green"
            case "ai-drawing":
                c?.prompt = "Make the button green"
                c?.debugShow(nil, phase: .drawing)
            case "ai-drawing-new":
                c?.target = nil
                c?.single = false
                c?.prompt = "A pricing page"
                c?.debugShow(nil, phase: .drawing)
            case "ai-directions":
                c?.target = nil
                c?.single = false
                c?.debugShow(three, phase: .directions)
            case "ai-done":
                // As it really goes: drawing (the shimmer), then done; the shimmer must be gone.
                c?.debugShow(nil, phase: .drawing)
                try? await Task.sleep(for: .seconds(1.5))
                c?.debugShow(nil, phase: .done("Desktop is updated."))
            default: break
            }

        }
        if scene == "delete" { model.askDelete(.doc(Self.docs()[0])) }
        if scene == "open-design-menu" {
            try? await Task.sleep(for: .milliseconds(300))
            model.projectsMenuOpen = true
        }
    }
}

extension DesignDemo {
    /// The editor tools on the real canvas (CORE_DESIGN_SCENE): zoom readout, pages, collaborators, shortcuts, paste.
    func tools(_ scene: String) async {
        try? await Task.sleep(for: .seconds(2))
        guard let e = model.editors[Self.did(1)] else {
            return FileHandle.standardError.write(Data("TOOLS no editor\n".utf8))
        }
        let frame = e.layers.layers.first { $0.type == "frame" }
        func peer(_ n: Int, _ id: String, _ label: String, _ at: [Double]) -> String {
            let sel = frame.map { ",\"selection\":[\"\($0.id)\"]" } ?? ""
            return "{\"peer\":\"\(id)\",\"conn\":\(n),\"label\":\"\(label)\",\"cursor\":[\(at[0]),\(at[1])]\(sel)}"
        }
        switch scene {
        case "tools-selftest":
            EditorToolsSelfTest.run(e) { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        case "tools-zoom":
            e.backend?.zoom(to: 2)
        case "tools-pages":
            e.insert(InsertPreset.frames[0])
            e.addPage()
            e.insert(InsertPreset.frames[3])
            e.insert(InsertPreset.shapes[0])
            e.addPage()
            e.showPage(1)
        case "tools-cursors", "tools-follow":
            e.backend?.debugPresence(peer(1, "person:d_maya", "Maya Ortiz", [180, 260]))
            e.backend?.debugPresence(peer(2, "session:as_0a1b2c3d", "Claude", [90, 420]))
            e.reload()
            if scene == "tools-follow", let maya = e.collaborators.first { e.follow(maya) }
        case "tools-shortcuts":
            e.shortcutsOpen = true
        case "tools-rotate":
            // A layer turned 25 degrees, selected: the Rotate field shows it and the canvas draws the turned box.
            guard let f = frame, e.select(f.id), e.insert(InsertPreset.shapes[0]) else { return }
            e.set("rotation", .number(25))
        case "tools-locked":
            // Layers: one layer locked (its lock stays on the row) and one hidden; the locked one is selected, so the
            // inspector header shows the lock too.
            guard let f = frame, e.select(f.id), e.insert(InsertPreset.shapes[0]) else { return }
            let first = e.selection.first ?? ""
            e.insert(InsertPreset.shapes[1])
            e.setHidden(e.selection.first ?? "", true)
            e.setLocked([first], true)
            e.select(first)
        case "tools-effects", "tools-strokes":
            // The inspector's Effects (drop and inner shadow, layer and background blur) and Stroke (two strokes with
            // alignment and dash) on one rectangle.
            guard let f = frame, e.select(f.id), e.insert(InsertPreset.shapes[0]) else { return }
            let inner = DJSON.object(
                [
                    "x": .number(0), "y": .number(2), "blur": .number(6), "spread": .number(0),
                    "color": .string("#ffffff40"), "inset": .bool(true),
                ])
            e.set("shadow", .array([InspectorIsland.shadow, inner]))
            e.set("blur", .number(4))
            e.set("backdrop_blur", .number(20))
            e.set(
                "stroke",
                InspectorEdits.strokeValue([
                    .object(["color": .string("#4f46e5"), "width": .number(2), "align": .string("outside")]),
                    .object(
                        [
                            "color": .string("#ec4899"), "width": .number(1), "align": .string("center"),
                            "dash": InspectorEdits.dash("dashed", width: 1) ?? .null,
                        ]),
                ]))
            try? await Task.sleep(for: .milliseconds(600))
            e.inspectorScroll = scene == "tools-effects" ? "Effects" : "Stroke"
        case "tools-effects-look":
            // What the effects draw, nothing selected and zoomed in: inner shadow and two strokes (one dashed) on a
            // rectangle, a layer blur on an ellipse, a rotated card.
            guard let f = frame, e.select(f.id), e.insert(InsertPreset.shapes[0]) else { return }
            e.set("x", .number(40))
            e.set("y", .number(40))
            e.set("fill", .array([.object(["type": .string("solid"), "color": .string("#e0e7ff")])]))
            e.set(
                "shadow",
                .array([
                    .object([
                        "x": .number(0), "y": .number(10), "blur": .number(10), "spread": .number(0),
                        "color": .string("#4f46e5ff"), "inset": .bool(true),
                    ])
                ]))
            e.set(
                "stroke",
                InspectorEdits.strokeValue([
                    .object(["color": .string("#4f46e5"), "width": .number(6), "align": .string("outside")]),
                    .object(
                        [
                            "color": .string("#ec4899"), "width": .number(3), "align": .string("inside"),
                            "dash": InspectorEdits.dash("dashed", width: 3) ?? .null,
                        ]),
                ]))
            e.select(f.id)
            if e.insert(InsertPreset.shapes[1]) {
                e.set("x", .number(300))
                e.set("y", .number(40))
                e.set("blur", .number(8))
            }
            e.select(f.id)
            if e.insert(InsertPreset.shapes[0]) {
                e.set("x", .number(560))
                e.set("y", .number(60))
                e.set("rotation", .number(-20))
            }
            e.selectMany([])
            e.fit(CGRect(x: 0, y: 0, width: 800, height: 300))
        case "tools-paste", "tools-text":
            // A card of three layers is copied and pasted twice (the second time into another frame), grouped, and a
            // line of plain text is pasted as a text layer.
            guard let f = frame, e.select(f.id) else { return }
            e.insert(InsertPreset.shapes[0])
            e.insert(InsertPreset.shapes[1])
            e.insert(InsertPreset.texts[1])
            let three = e.layers.children(of: f.id).suffix(3).map(\.id)
            e.selectMany(three)
            e.copy()
            e.paste()
            if scene == "tools-paste" {
                e.group()
                e.selectMany(e.selection)
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("Pay now to finish the order", forType: .string)
                e.select(f.id)
                e.paste()
            }
        default: break
        }
        try? await Task.sleep(for: .seconds(1))
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
