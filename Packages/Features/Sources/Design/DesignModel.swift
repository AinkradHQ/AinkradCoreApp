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

    var docs: [DesignDoc] = []
    var assets: [DesignAsset] = []
    var kits: [BrandKit] = []
    var load: DesignLoad = .notConnected
    /// The rail's pick.
    var category = DesignCategory.all
    /// The rail's project (by id), or nil for all projects.
    var project: String?
    /// The top bar's Filter field: names, kinds and tags.
    var filter = ""
    /// The open item (a `DesignItem.id`), or nil for the home.
    var openID: String?
    /// The pictures of loaded assets, by sha256.
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var fetching: Set<String> = []
    private(set) var readOnly = false
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
    #endif

    public init(host: any AdminHost, projects: ProjectsModel) {
        self.host = host
        projectsModel = projects
        projects.designsIsland = { [weak self] ref in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(DesignsIsland(model: self, project: ref))
        }
    }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        mockups = LiveMockupSource(connection: connection)
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
        docs = []
        assets = []
        kits = []
        images = [:]
        fetching = []
        load = .notConnected
        openID = nil
        editors = [:]
        readOnly = false
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }

    /// An event from the Core that may change what the screens show (ids only: `design.doc`, `design.asset`, …).
    public func event(kind: String) { if kind.hasPrefix("design.") { resync() } }

    func reload() async {
        guard let service else { return }
        do {
            async let d = service.docs()
            async let a = service.assets()
            async let k = service.kits()
            docs = try await d
            assets = try await a
            kits = try await k
            load = .ready
        } catch let e as DesignFailure where e.status == 404 || e.status == 501 {
            load = .absent
        } catch {
            if docs.isEmpty, assets.isEmpty, kits.isEmpty { load = .failed(words(error)) }
        }
    }

    // MARK: derived

    /// Every item, newest first.
    var items: [DesignItem] {
        (docs.map(DesignItem.doc) + kits.map(DesignItem.kit) + assets.map(DesignItem.asset))
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The items after the rail's project and the Filter field.
    var visible: [DesignItem] { visible(in: project) }

    func visible(in project: String?) -> [DesignItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            (project.map { item.projects.contains($0) } ?? true)
                && (q.isEmpty || item.name.lowercased().contains(q) || item.kindWord.lowercased().contains(q)
                    || item.tags.contains { $0.lowercased().contains(q) })
        }
    }

    func items(in c: DesignCategory) -> [DesignItem] { items(in: c, project: project) }

    func items(in c: DesignCategory, project: String?) -> [DesignItem] {
        switch c {
        // TODO(V6-02): designs waiting for review or approval. TODO(V7-02): designs an AI session is drawing.
        case .needsYou, .drawing: []
        case .all: visible(in: project)
        default: visible(in: project).filter { $0.category == c }
        }
    }

    /// A category row's count: what picking it shows (a category is never scoped to a project).
    func count(_ c: DesignCategory) -> Int { items(in: c, project: nil).count }

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
        guard a.loadable, images[a.sha] == nil, !fetching.contains(a.sha), let service else { return }
        fetching.insert(a.sha)
        defer { fetching.remove(a.sha) }
        guard let data = try? await service.data(a.sha) else { return }
        let img: NSImage? =
            a.kind == .iconComposer
            ? await IconComposerPreview.image(zip: data, sha: a.sha) : NSImage(data: data)
        if let img { images[a.sha] = img }
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

    // MARK: navigation

    func openItem(_ id: String) {
        withAnimation(Motion.out(Motion.move)) { openID = id }
    }

    func closeItem() {
        editors = [:]
        withAnimation(Motion.out(Motion.move)) { openID = nil }
    }

    /// One rail row is selected at a time: a category clears the project, a project shows all of its designs.
    func pick(_ c: DesignCategory) {
        category = c
        project = nil
        openID = nil
    }

    func pickProject(_ id: String) {
        project = project == id ? nil : id
        category = .all
        openID = nil
    }

    /// Opens the pane; with `item`, on that item (from a project's Designs island); with `project`, filtered to it.
    public func show(item: String? = nil, project: String? = nil) {
        if let item { openID = item }
        if let project {
            self.project = project
            category = .all
            openID = nil
        }
        var spec = PaneSpec(
            id: "design", title: "Design", sub: "Home Core", symbol: "paintbrush.pointed", minWidth: 760
        ) { DesignView(model: self) }
        spec.tab = "Design"
        host.shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
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
