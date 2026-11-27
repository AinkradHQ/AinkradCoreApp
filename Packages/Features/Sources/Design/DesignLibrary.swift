import AppKit
import CoreUI
import Foundation
import Observation

/// The library's own state: sort, favourites, the multi-selection, uploads in flight, archived designs, the Core's search
/// hits and what is hidden while a delete can still be undone. The rules (order, ranges, tags, upload checks, kit colours)
/// are plain functions so they are tested without a Core.
@MainActor @Observable
final class DesignLibrary {
    enum Sort: String, CaseIterable, Sendable { case recent, name }

    struct UploadJob: Identifiable, Equatable {
        enum State: Equatable {
            case uploading
            case done(duplicate: Bool)
            case failed(String)
        }
        let id = UUID()
        let name: String
        var state: State
    }

    private static let sortKey = "sort"
    private static let favouritesKey = "favourites"
    private static let favouritesFirstKey = "favouritesFirst"

    var sort: Sort {
        didSet {
            DesignOptions.options.set(Self.sortKey, sort.rawValue)
            model?.sortItems()
        }
    }
    var favouritesFirst: Bool {
        didSet {
            DesignOptions.options.set(Self.favouritesFirstKey, favouritesFirst)
            model?.sortItems()
        }
    }
    var favourites: Set<String>
    /// The ⌘/⇧-clicked cards (`DesignItem.id`).
    var multi: Set<String> = []
    var anchor: String?
    private(set) var archived: [DesignDoc] = []
    private(set) var archivedLoaded = false
    private(set) var archivedError: String?
    /// Library files the Core found for the Filter text that the (capped) list did not hold.
    private(set) var extra: [DesignAsset] = []
    var uploads: [UploadJob] = []
    /// Items that are deleted unless Undo is pressed in time.
    private(set) var hidden: Set<String> = []
    /// The Core can restore an archived design (API 109).
    var restoreSupported = false
    @ObservationIgnored weak var model: DesignModel?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init() {
        let o = DesignOptions.options
        sort = Sort(rawValue: o.string(Self.sortKey, "recent")) ?? .recent
        favouritesFirst = o.bool(Self.favouritesFirstKey, false)
        favourites = Set(o.string(Self.favouritesKey, "").split(separator: "\n").map(String.init))
    }

    func reset() {
        multi = []
        anchor = nil
        archived = []
        archivedLoaded = false
        extra = []
        uploads = []
        hidden = []
        restoreSupported = false
        searchTask?.cancel()
    }

    // MARK: order

    /// Recent (newest first) or Name; favourites first when asked. Stable: ties keep their order.
    static func order(_ items: [DesignItem], sort: Sort, favourites: Set<String>, favouritesFirst: Bool) -> [DesignItem]
    {
        let base: [DesignItem]
        switch sort {
        case .recent:
            base = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .name:
            base = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        guard favouritesFirst else { return base }
        return base.filter { favourites.contains($0.id) } + base.filter { !favourites.contains($0.id) }
    }

    func isFavourite(_ item: DesignItem) -> Bool { favourites.contains(item.id) }

    func toggleFavourite(_ item: DesignItem) {
        if favourites.contains(item.id) { favourites.remove(item.id) } else { favourites.insert(item.id) }
        DesignOptions.options.set(Self.favouritesKey, favourites.sorted().joined(separator: "\n"))
        if favouritesFirst { model?.sortItems() }
    }

    // MARK: selection

    /// The ids from `a` to `b` in `list`, both ends included (a shift-click).
    static func range(in list: [String], from a: String?, to b: String) -> [String] {
        guard let a, let i = list.firstIndex(of: a), let j = list.firstIndex(of: b) else { return [b] }
        return Array(list[min(i, j)...max(i, j)])
    }

    func toggle(_ id: String) {
        if multi.contains(id) { multi.remove(id) } else { multi.insert(id) }
        anchor = id
    }
    func extend(to id: String, in list: [String]) {
        multi.formUnion(Self.range(in: list, from: anchor ?? multi.first, to: id))
        anchor = id
    }
    func clearSelection() {
        multi = []
        anchor = nil
    }

    // MARK: hiding (undoable delete)

    func hide(_ ids: [String]) {
        hidden.formUnion(ids)
        multi.subtract(ids)
        model?.sortItems()
    }
    func unhide(_ ids: [String]) {
        hidden.subtract(ids)
        model?.sortItems()
    }

    // MARK: server search

    /// The Filter text changed: after a pause, the Core is asked for library files with that in their name.
    func searchChanged(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            if !extra.isEmpty { extra = [] }
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, let service = model?.service else { return }
            guard let hits = try? await service.searchAssets(q), !Task.isCancelled else { return }
            let have = Set(model?.assets.map(\.sha) ?? [])
            extra = hits.filter { !have.contains($0.sha) }
        }
    }

    // MARK: archived

    func loadArchived() async {
        guard let service = model?.service else { return }
        do {
            archived = try await service.archivedDocs()
            archivedLoaded = true
            archivedError = nil
        } catch {
            archivedError = model?.words(error)
        }
    }

    func dropArchived(_ id: String) { archived.removeAll { $0.id == id } }

    // MARK: uploads

    /// What the Core takes: images, SVG, PDF, fonts and Icon Composer zips, each at most 25 MB.
    static let uploadTypes: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "pdf", "ttf", "otf", "woff", "woff2", "zip",
    ]

    /// Nil when the file may go; else the reason in words.
    static func uploadProblem(name: String, size: Int) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        if !uploadTypes.contains(ext) { return "Only images, SVG, PDF and fonts can be added." }
        if size == 0 { return "The file is empty." }
        if size > LiveDesignService.uploadLimit { return "Over 25 MB." }
        return nil
    }

    /// The display name: the file name, at most 200 characters, no control characters.
    static func uploadName(_ file: String) -> String {
        let clean = String(file.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return String(clean.prefix(200))
    }

    /// `icon`/`logo` are the person's to say; a raster or SVG is an `image`, everything else follows its type.
    static func uploadKind(_ file: String) -> String? {
        ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains((file as NSString).pathExtension.lowercased())
            ? "image" : nil
    }

    func upload(_ urls: [URL], project: String?) async {
        guard let model, let service = model.service else { return }
        if model.readOnly || model.host.pausedReason != nil {
            model.host.shell.showToast(
                model.host.pausedReason ?? "This device can look at designs but not change them.", kind: .warn)
            return
        }
        var added = 0
        var already = 0
        var failed = 0
        for url in urls {
            let file = url.lastPathComponent
            let name = Self.uploadName(file)
            var job = UploadJob(name: name, state: .uploading)
            uploads.append(job)
            func finish(_ s: UploadJob.State) {
                job.state = s
                if let i = uploads.firstIndex(where: { $0.id == job.id }) { uploads[i] = job }
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if let why = Self.uploadProblem(name: file, size: size) {
                finish(.failed(why))
                failed += 1
                continue
            }
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                let r = try await service.upload(
                    name: name, kind: Self.uploadKind(file), project: project, data: data)
                finish(.done(duplicate: r.duplicate))
                if r.duplicate { already += 1 } else { added += 1 }
            } catch {
                finish(.failed(model.words(error)))
                failed += 1
            }
        }
        await model.reload()
        var parts: [String] = []
        if added > 0 { parts.append("\(Words.count(added, "file")) added") }
        if already > 0 { parts.append("\(already) already in the library") }
        if failed > 0 { parts.append("\(failed) could not be added") }
        model.host.shell.showToast(parts.joined(separator: ", "), kind: failed > 0 ? .warn : .ok)
        // Finished rows stay a moment, failures until dismissed.
        try? await Task.sleep(for: .seconds(4))
        uploads.removeAll { if case .failed = $0.state { false } else { $0.state != .uploading } }
    }

    // MARK: tags and kit colours

    /// Tags typed as a list: trimmed, de-duplicated, at most 20 of 1 to 32 characters (the Core's own limits).
    static func tags(from text: String) -> (tags: [String], error: String?) {
        var out: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || out.contains(t) { continue }
            if t.count > 32 { return (out, "A tag is at most 32 characters.") }
            out.append(t)
        }
        if out.count > 20 { return (Array(out.prefix(20)), "At most 20 tags.") }
        return (out, nil)
    }

    /// A brand colour as the Core wants it: `#rrggbb`, lower case. A colour picker's alpha is dropped.
    static func kitColor(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 8 { t = String(t.prefix(6)) }
        guard t.count == 6, t.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + t
    }
}
