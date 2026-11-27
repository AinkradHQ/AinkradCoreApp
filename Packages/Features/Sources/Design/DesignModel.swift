import Admin
import AppKit
import CoreKit
import CoreUI
import Foundation
import Observation
import Projects
import Shell
import SwiftUI
import UniformTypeIdentifiers

/// The Design app: the home of every design by category (the rail), the library (logos, icons, illustrations, fonts, brand
/// kits), the open item, and the Designs island in a project's space. It owns the lists, the Core service and the project
/// links, and registers the pane and the launcher entries. Drawing happens on the canvas (V3-02, set by the app through `canvas`); review (V3-05), design systems
/// (V3-06), the mockup viewer (V3-07) and AI drawing from a brief (V7-02) come in later stories.
@MainActor @Observable
public final class DesignModel {
    let host: any AdminHost
    let projectsModel: ProjectsModel
    var service: (any DesignService)?
    /// Where the mockup viewer reads packages from (V3-07); nil until a Core is attached.
    var mockups: (any MockupSource)?
    /// The paired connection, for the canvas's sync socket; nil until a Core is attached.
    @ObservationIgnored var connection: CoreConnection?

    var docs: [DesignDoc] = [] { didSet { sortItems() } }
    var assets: [DesignAsset] = [] { didSet { sortItems() } }
    var kits: [BrandKit] = [] { didSet { sortItems() } }
    /// Every item, newest first: sorted once when a list changes, not on every count and redraw.
    private(set) var items: [DesignItem] = []
    var load: DesignLoad = .notConnected
    /// Sort, favourites, multi-select, uploads, archived designs and undoable deletes (`DesignLibrary.swift`).
    let lib = DesignLibrary()
    /// Comments and approvals of the designs on screen (`DesignCollab.swift`).
    let collab = DesignCollab()
    /// The rail's pick.
    var category = DesignCategory.all
    /// The rail's project (by id), or nil for all projects.
    var project: String?
    /// The top bar's Filter field: names, kinds and tags.
    var filter = "" { didSet { if filter != oldValue { lib.searchChanged(filter) } } }
    /// The open item (a `DesignItem.id`), or nil for the home.
    var openID: String?
    /// The card the keyboard is on (a `DesignItem.id`), or nil.
    var selected: String?
    /// The wall's column count, for ↑ ↓ (set by the wall as it lays out).
    @ObservationIgnored var columns = 1
    /// The open item's About panel.
    var aboutOpen = false
    /// The AI panel over the open design's canvas, or nil.
    var composer: DesignComposer?
    /// Present (the mockup and prototype view) over the open design, or nil.
    var presenter: DesignPresenter?
    /// The pictures of loaded assets, by sha256: a bounded cache (`image(_:)` reads `imageTick` so views redraw as pictures land).
    @ObservationIgnored private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 160
        return c
    }()
    private(set) var imageTick = 0
    /// Assets whose picture could not be loaded (the card shows an error and Retry).
    var failedImages: Set<String> = []
    @ObservationIgnored private var fetching: Set<String> = []
    /// A refresh failed while lists were already on screen: a quiet note over the wall, the old lists kept.
    var refreshFailure: String?
    /// The Core returns at most this many rows of a list (docs, library files), by name.
    static let listMax = 500
    var docsCapped = false
    var readOnly = false
    /// The Core can draw three directions from a prompt (API minor 95, E11-4).
    private(set) var composeSupported = false
    /// The Core can write a whole design system with AI (API 108).
    private(set) var systemAISupported = false
    /// The Core's edit mode reads a frame itself (API 109).
    private(set) var editSupported = false
    /// The open item's Projects menu.
    var projectsMenuOpen = false
    /// The editor chrome of each design whose canvas was built (V3-04), by doc id.
    @ObservationIgnored var editors: [String: DesignEditor] = [:]
    /// Builds the canvas for an open design (V3-02). Set by the app, which links the engine; it returns nil while the
    /// Core cannot sync the doc. Nil here (tests) keeps the preview.
    @ObservationIgnored public var canvas: ((DesignCanvasInput) -> AnyView?)?
    #if DEBUG
    /// Snapshots only: draws this card in its hover state.
    var debugHover: String?
    /// Snapshots only: forgets every loaded picture, so a card shows its failed state.
    func debugForgetImages() {
        imageCache.removeAllObjects()
        imageTick += 1
    }
    /// Snapshots only: shows the Saved badge in this state.
    var debugSave: SaveState?
    /// Snapshots only: the Comments panel shown open.
    var debugCommentsOpen = false
    /// Snapshots only: the style guide's Add token popover shown open.
    var debugAddTokenOpen = false
    /// Snapshots only: opens the style guide's Generate popover on its replace confirmation.
    var debugSystemAsk = false
    /// Snapshots only: the app's on-canvas probe (pointer and keys on the real canvas view), set by the app.
    @ObservationIgnored public var debugCanvasProbe: (@MainActor (@escaping @MainActor (String) -> Void) async -> Void)?
    #endif

    public init(host: any AdminHost, projects: ProjectsModel) {
        self.host = host
        projectsModel = projects
        lib.model = self
        collab.model = self
        projects.designsIsland = { [weak self] ref in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(DesignsIsland(model: self, project: ref))
        }
    }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        mockups = LiveMockupSource(connection: connection)
        self.connection = connection
        AboutIsland.me = connection.identity.deviceID
        Task { composeSupported = await connection.serverSupports(minor: coreMinorV010) }
        use(LiveDesignService(connection: connection))
    }

    func use(_ service: any DesignService) {
        self.service = service
        load = .loading
        Task { await reload() }
    }

    public func detach() {
        service = nil
        mockups = nil
        connection = nil
        docs = []
        assets = []
        kits = []
        imageCache.removeAllObjects()
        failedImages = []
        fetching = []
        refreshFailure = nil
        load = .notConnected
        // Nothing of the open item may outlive the Core: its keys, composer and canvases go with it.
        clearOpen()
        withAnimation(Motion.out(Motion.move)) { openID = nil }
        selected = nil
        readOnly = false
        composeSupported = false
        systemAISupported = false
        lib.reset()
        collab.reset()
        editSupported = false
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }

    /// An event from the Core that may change what the screens show (ids only: `design.doc`, `design.asset`, …). Only the
    /// list it is about is read again; comments, approvals and versions change none of the lists.
    public func event(kind: String) {
        guard kind.hasPrefix("design."), service != nil else { return }
        collab.refresh()
        switch kind {
        case _ where kind.hasPrefix("design.doc"): Task { await reload(.docs) }
        case _ where kind.hasPrefix("design.asset"): Task { await reload(.assets) }
        case _ where kind.hasPrefix("design.collection"): Task { await reload(.kits) }
        case _ where ["design.comment", "design.approval", "design.version"].contains { kind.hasPrefix($0) }: break
        default: resync()
        }
    }

    struct Lists: OptionSet {
        let rawValue: Int
        static let docs = Lists(rawValue: 1)
        static let assets = Lists(rawValue: 2)
        static let kits = Lists(rawValue: 4)
        static let all: Lists = [.docs, .assets, .kits]
    }

    func reload(_ which: Lists = .all) async {
        guard let service else { return }
        do {
            // The module's own absence is the docs list answering 404; a 404 on another call is about that call.
            if which.contains(.docs) {
                do { docs = try await service.docs() } catch let e as DesignFailure
                    where e.status == 404 || e.status == 501
                {
                    load = .absent
                    return
                }
                docsCapped = docs.count >= Self.listMax
            }
            if which.contains(.assets) { assets = try await service.assets() }
            if which.contains(.kits) { kits = try await service.kits() }
            refreshFailure = nil
            load = .ready
            // The handshake that proves the Core's minors happens on the first request, so ask after a load.
            if let connection {
                composeSupported = await connection.serverSupports(minor: coreMinorV010)
                systemAISupported = await connection.serverSupports(minor: 108)
                lib.restoreSupported = await connection.serverSupports(minor: 109)
                editSupported = await connection.serverSupports(minor: 109)
            }
            if lib.archivedLoaded { await lib.loadArchived() }
        } catch {
            if docs.isEmpty, assets.isEmpty, kits.isEmpty {
                load = .failed(words(error))
            } else {
                refreshFailure = words(error)
            }
        }
    }

    // MARK: derived

    /// Every item, newest first.
    func sortItems() {
        let all = (docs.map(DesignItem.doc) + kits.map(DesignItem.kit) + assets.map(DesignItem.asset))
            .filter { !lib.hidden.contains($0.id) }
        items = DesignLibrary.order(
            all, sort: lib.sort, favourites: lib.favourites, favouritesFirst: lib.favouritesFirst)
    }

    /// The items after the rail's project and the Filter field.
    var visible: [DesignItem] { visible(in: project) }

    func visible(in project: String?) -> [DesignItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        // What the Core found for the typed text beyond the lists' 500 joins them.
        let pool = q.isEmpty || lib.extra.isEmpty ? items : items + lib.extra.map(DesignItem.asset)
        return pool.filter { item in
            (project.map { item.projects.contains($0) } ?? true)
                && (q.isEmpty || item.name.lowercased().contains(q) || item.kindWord.lowercased().contains(q)
                    || item.tags.contains { $0.lowercased().contains(q) })
        }
    }

    func items(in c: DesignCategory) -> [DesignItem] { items(in: c, project: project) }

    func items(in c: DesignCategory, project: String?) -> [DesignItem] {
        switch c {
        case .archived:
            lib.archived.map(DesignItem.doc).filter {
                let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
                return q.isEmpty || $0.name.lowercased().contains(q)
            }
        case .all: visible(in: project)
        case .library: visible(in: project).filter { DesignCategory.libraryKinds.contains($0.category) }
        default: visible(in: project).filter { $0.category == c }
        }
    }

    /// A category row's count: what picking it shows, so it follows the project chip.
    func count(_ c: DesignCategory) -> Int {
        c == .archived && !lib.archivedLoaded ? -1 : items(in: c).count
    }

    /// The projects with something related to them, for the rail.
    var railProjects: [(ref: ProjectRef, count: Int)] {
        projectsModel.refs.compactMap { p in
            let n = items.filter { $0.projects.contains(p.id) }.count
            return n > 0 ? (p, n) : nil
        }
    }

    var allProjects: [ProjectRef] { projectsModel.refs }

    func projectName(_ id: String) -> String { allProjects.first { $0.id == id }?.name ?? "Project \(id)" }

    func projectWords(_ item: DesignItem) -> String {
        item.projects.isEmpty ? "No project" : item.projects.map(projectName).joined(separator: ", ")
    }

    func item(_ id: String?) -> DesignItem? { id.flatMap { id in items.first { $0.id == id } } }
    var open: DesignItem? { item(openID) }

    func doc(_ id: String?) -> DesignDoc? { id.flatMap { id in docs.first { $0.id == id } } }
    func asset(_ sha: String) -> DesignAsset? { assets.first { $0.sha == sha } }

    /// The designs that use a system.
    func usedBy(_ system: DesignDoc) -> [DesignDoc] { docs.filter { $0.system == system.id } }

    /// What a project's Designs island lists.
    func linked(to project: String) -> [DesignItem] { items.filter { $0.projects.contains(project) } }

    var summary: String {
        let n = items.count
        return "\(Words.count(n, "item")) · \(Words.count(docs.count, "design")) · \(Words.count(assets.count, "file"))"
    }

    // MARK: pictures

    /// Loads an asset's picture once: images, logos, icons and PDFs as they are, an Icon Composer file through
    /// `IconComposerPreview`. Fonts and unchecked files are never fetched.
    func loadImage(_ a: DesignAsset) async {
        guard a.loadable, image(a.sha) == nil, !failedImages.contains(a.sha), !fetching.contains(a.sha), let service
        else { return }
        fetching.insert(a.sha)
        defer { fetching.remove(a.sha) }
        let data = try? await service.data(a.sha)
        var img: NSImage?
        if let data {
            img =
                a.kind == .iconComposer
                ? await IconComposerPreview.image(zip: data, sha: a.sha) : NSImage(data: data)
        }
        if let img {
            imageCache.setObject(img, forKey: a.sha as NSString)
            imageTick += 1
        } else {
            failedImages.insert(a.sha)
        }
    }

    /// The loaded picture of an asset, if it is still cached.
    func image(_ sha: String) -> NSImage? {
        _ = imageTick
        return imageCache.object(forKey: sha as NSString)
    }

    /// Tries a picture again after it failed.
    func retryImage(_ a: DesignAsset) {
        failedImages.remove(a.sha)
        Task { await loadImage(a) }
    }

    /// A drag to Finder or another app makes a real file with the asset's name; the bytes are fetched when it drops.
    func dragProvider(_ a: DesignAsset) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = a.fileName
        guard a.check == .ok, let service else { return provider }
        let type = UTType(mimeType: a.contentType) ?? .data
        let name = a.fileName
        let sha = a.sha
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) {
            done in
            Task {
                do {
                    let data = try await service.data(sha)
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "ainkrad-drag-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try data.write(to: url)
                    done(url, false, nil)
                } catch { done(nil, false, error) }
            }
            return nil
        }
        return provider
    }

    // MARK: words

    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        if let e = error as? DesignFailure { return e.sentence }
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return error.localizedDescription }
        return e.localizedDescription
    }

    // MARK: writes

    /// Relates an item to a project, or ends that. Related, not owned: the item stays in the library either way.
    func setLink(_ item: DesignItem, project: ProjectRef, _ on: Bool) async {
        guard let service else { return }
        if readOnly {
            host.shell.showToast("This device can look at designs but not change them.", kind: .warn)
            return
        }
        if let why = host.pausedReason {
            host.shell.showToast(why)
            return
        }
        do {
            try await service.link(item, project: project.id, on)
            await reload()
            host.shell.showToast(on ? "\(item.name) linked to \(project.name)" : "\(item.name) unlinked")
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            host.shell.showToast(words(error), kind: .warn)
        }
    }

    /// New design, quick: made at once with the defaults (named for the category being looked at) and opened.
    func quickNew(starter: Bool = true) async {
        // A mockup is not an empty document: it shows one of the designs, so New there asks which (Present).
        if category.page == .mockups { return openNew(kind: .mockup) }
        let kind: DesignDoc.Kind = category.page == .systems ? .system : .design
        await create(kind: kind, name: Self.defaultName(kind), project: project, starter: starter ? nil : [])
    }

    static func defaultName(_ kind: DesignDoc.Kind) -> String {
        switch kind {
        case .design: "Untitled design"
        case .system: "Untitled design system"
        case .mockup: "Untitled mockup"
        }
    }

    /// Makes the design and opens it. Returns the Core's refusal in words (the advanced sheet shows it inline), nil on
    /// success; the quick path toasts it.
    @discardableResult
    /// `starter`: the new design's first ops; nil gives the default frame, `[]` none (the AI draws instead).
    func create(
        kind: DesignDoc.Kind, name: String, project: String?, system: String? = nil,
        starter: [[String: DJSON]]? = nil, toast: Bool = true
    ) async -> String? {
        guard let service else { return "Not connected to a Core." }
        if readOnly || host.pausedReason != nil {
            let why = host.pausedReason ?? "This device can look at designs but not change them."
            if toast { host.shell.showToast(why, kind: .warn) }
            return why
        }
        do {
            let d = try await service.create(
                kind: kind, name: DesignName.clean(name), project: project, system: system)
            docs.append(d)
            if kind == .design {
                let ops = starter ?? DesignOptions.starterOps(DesignOptions.canvas)
                if !ops.isEmpty { editor(for: d.id).starter = ops }
            }
            host.shell.closeDialog()
            category = .all
            filter = ""
            openItem(DesignItem.doc(d).id)
            Task { await reload() }
            return nil
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            let why = words(error)
            if toast { host.shell.showToast(why, kind: .warn) }
            return why
        }
    }

    /// Draw with AI: the composer on the open design; from the home, on a new blank design.
    /// Opens the AI panel on the open design (from the home: on a new blank design). With a frame selected it edits that
    /// frame; with `prompt` (the Ask… field) it starts at once.
    func drawWithAI(prompt: String = "") async {
        // AI draws on designs only: from the home it makes a design (never a system or mockup, whatever page is open).
        // The new design has no starter frame of its own to keep: the AI's frame replaces it.
        let fromHome = openID == nil
        if fromHome {
            guard await create(kind: .design, name: Self.defaultName(.design), project: project) == nil else { return }
        }
        guard let id = openID, let item = item(id), case .doc(let d) = item, d.kind == .design else {
            host.shell.showToast("Draw with AI works on a design. Open a design first.", kind: .warn)
            return
        }
        let target = editors[d.id]?.targetFrame().map { DesignComposer.Target(id: $0.id, name: $0.title) }
        let c = DesignComposer(model: self, doc: d.id, prompt: prompt, target: target)
        if fromHome { c.starterFrame = editors[d.id]?.starter?.last?["id"]?.string }
        composer?.shutdown()  // one run at a time
        withAnimation(Motion.out(Motion.ui)) { composer = c }
        if !prompt.isEmpty { c.draw() }
    }

    /// New design (advanced): the sheet with name, kind and project.
    func openNew(kind: DesignDoc.Kind = .design) {
        host.shell.present(ShellDialog(id: "new-design") { NewDesignView(model: self, kind: kind) })
    }

    // MARK: navigation

    func openItem(_ id: String) {
        if let c = composer, "doc:\(c.doc)" != id {  // another design: its run ends with its panel
            c.shutdown()
            composer = nil
        }
        withAnimation(Motion.out(Motion.move)) { openID = id }
    }

    /// Lets go of everything that belongs to the open item (its canvases, AI panel and Present) so none keeps the keys.
    func clearOpen() {
        presenter?.viewer.present(nil)
        editors = [:]
        aboutOpen = false
        composer?.shutdown()
        composer = nil
        presenter = nil
    }

    func closeItem() {
        clearOpen()
        withAnimation(Motion.out(Motion.move)) { openID = nil }
    }

    /// One rail row is selected at a time: a category clears the project, a project shows all of its designs.
    func pick(_ c: DesignCategory) {
        withAnimation(Motion.out(Motion.ui)) { category = c }
        selected = nil
        project = nil
        closeItem()
        lib.clearSelection()
        if c == .archived { Task { await lib.loadArchived() } }
    }

    func pickProject(_ id: String) {
        project = project == id ? nil : id
        category = .all
        closeItem()
    }

    /// Opens the pane; with `item`, on that item (from a project's Designs island); with `project`, filtered to it.
    public func show(item: String? = nil, project: String? = nil) {
        if let item {
            if openID != item { clearOpen() }
            openID = item
        }
        if let project {
            self.project = project
            category = .all
            closeItem()
        }
        var spec = PaneSpec(
            id: "design", title: "Design", sub: "Home Core", symbol: "paintbrush.pointed", minWidth: 760
        ) { DesignView(model: self) }
        spec.tab = "Design"
        spec.fullScreenOnly = true
        // ⌘N (File, New) on this pane makes a blank design at once.
        spec.onNew = { [weak self] in Task { await self?.quickNew() } }
        host.shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
        // Settings, Apps, Design: Look (follows Appearance unless turned off) and Options.
        shell.settings.section(
            SettingsSection(
                id: "design", group: .apps, title: "Design", sub: "Its look, grid and first canvas",
                symbol: "paintbrush.pointed", order: 8,
                tabs: [
                    SettingsTab("look", "Look", order: 0) {
                        AppLookSection(appName: "Design", prefs: AppLookPrefs.shared("design"))
                            .foregroundStyle(GlassInk.primary)
                    },
                    SettingsTab("options", "Options", order: 1) { DesignOptionsTab() },
                ]))
        func entry(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String],
            _ run: @escaping @MainActor (DesignModel) -> Void
        ) {
            shell.launcher.register(
                LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys) { [weak self] in
                    if let self { run(self) }
                })
        }
        entry(
            "design", "Design", "Every design, by category · the library", "paintbrush.pointed",
            ["mockup", "screen", "logo", "icon", "brand", "font", "library"]
        ) { $0.show() }
        // Quick by default, advanced on request (Ahmed, 2026-11-05).
        shell.launcher.register(
            LauncherEntry(
                id: "new-design", title: "New design", sub: "Opens a blank design at once", symbol: "plus",
                keywords: ["create", "canvas", "screen"], isAction: true
            ) { [weak self] in
                self?.show()
                Task { await self?.quickNew() }
            })
        shell.launcher.register(
            LauncherEntry(
                id: "new-design-advanced", title: "New design (advanced)…", sub: "Name, kind and project",
                symbol: "slider.horizontal.3", keywords: ["create", "design system", "mockup"], isAction: true
            ) { [weak self] in
                self?.show()
                self?.openNew()
            })
        entry(
            "design-library", "Design Library", "Logos, icons, illustrations, fonts and brand kits",
            "photo.on.rectangle",
            ["asset", "logo", "icon", "font", "brand kit", "image"]
        ) {
            $0.pick(.brand)
            $0.show()
        }
    }
}
