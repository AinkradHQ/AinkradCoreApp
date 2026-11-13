import BrainImport
import Foundation

/// One kind of "Notes and docs" read from wherever `ImportPlaces` points: the chosen folders, or what the last
/// whole-disk search found. Uses the existing collectors and the shared streaming loop; only the list of files differs.
///
/// Sync (Brain M2): chosen folders are listed again each time, so a folder added later is picked up. For the whole
/// disk the walk is not repeated: a sync re-reads the folders and files the last search found (kept in
/// `ImportPlaces.disk`), so new files inside them arrive and new folders wait for the next search.
public struct PlacesSource: ImportSource {
    public enum Kind: Sendable { case doc, vault, agents, chat }

    public let id: String
    public let title: String
    let kind: Kind
    let places: ImportPlaces
    let device: String
    let home: URL
    let files: any FileAccess

    public init(
        _ kind: Kind, places: ImportPlaces, device: String = Host.current().localizedName ?? "Mac",
        home: URL = FileManager.default.homeDirectoryForCurrentUser, files: any FileAccess = DiskFiles()
    ) {
        self.kind = kind
        self.places = places
        self.device = device
        self.home = home
        self.files = files
        switch kind {
        case .doc: (id, title) = ("doc", "Project docs")
        case .vault: (id, title) = ("vault", "Notes (Obsidian vaults)")
        case .agents: (id, title) = ("agents_md", "AGENTS.md, CLAUDE.md and README files")
        case .chat: (id, title) = ("chat", "Chat exports")
        }
    }

    var collector: any FileCollector {
        switch kind {
        case .doc: MarkdownCollector(layout: .projectDocs, device: device, files: files)
        case .vault: MarkdownCollector(layout: .vault, device: device, files: files)
        case .agents: MarkdownCollector(layout: .agentFiles, device: device, files: files)
        case .chat: ChatExportCollector(device: device)
        }
    }

    /// Each file with its path under the folder it was found in (what the skip rules read).
    func candidates() -> [(url: URL, rel: String)] {
        func rel(_ u: URL, _ root: URL) -> String { u.path.replacingOccurrences(of: root.path, with: "") }
        if kind == .chat {
            guard let root = places.chat else { return [] }
            return collector.candidates(under: root).map { ($0, rel($0, root)) }
        }
        var seen = Set<String>()
        func unique(_ l: [(url: URL, rel: String)]) -> [(url: URL, rel: String)] {
            l.filter { seen.insert($0.url.path).inserted }
        }
        if places.mode == .disk {
            let f = DocWalker.files(of: places.disk ?? DocWalker.Found())
            let list = kind == .doc ? f.docs : kind == .vault ? f.vault : f.agents
            return unique(list.map { ($0, rel($0, home)) })
        }
        let k: PlaceCandidates.Kind = kind == .doc ? .doc : kind == .vault ? .vault : .agents
        return unique(
            places.folders.flatMap { root in
                PlaceCandidates.files(k, under: root, device: device, files: files).map { ($0, rel($0, root)) }
            })
    }

    public func scan() async -> CollectReport {
        var report = CollectReport()
        for c in candidates() {
            report.found += 1
            if let why = PreFilter.skipReason(path: c.rel) { report.skipped[why, default: 0] += 1 }
        }
        return report
    }

    public var incremental: Bool { true }

    public func newCount(since: Date?) async -> Int {
        guard let since else { return 0 }
        return candidates().filter {
            (files.modified(of: $0.url) ?? .distantPast) > since && PreFilter.skipReason(path: $0.rel) == nil
        }.count
    }

    public func streamNew(
        since: Date?, run: String, uploader: Uploader, uploaded: Uploader.Progress
    ) async throws -> CollectReport {
        try await read(
            since: since, run: run, uploader: uploader, uploaded: uploaded, resume: .init(), save: { _ in },
            onProgress: { _ in })
    }

    public func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        try await read(
            since: nil, run: run, uploader: uploader, uploaded: uploaded, resume: resume, save: save,
            onProgress: onProgress)
    }

    private func read(
        since: Date?, run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        var report = CollectReport()
        var todo: [ImportStreamer.Unit] = []
        let collector = collector
        for c in candidates().sorted(by: { $0.url.path < $1.url.path }) {
            if let since {
                guard let m = files.modified(of: c.url), m > since else { continue }
                report.newest = max(report.newest ?? m, m)
            }
            report.found += 1
            if let why = PreFilter.skipReason(path: c.rel) {
                report.skipped[why, default: 0] += 1
                continue
            }
            // The key is the whole path: two chosen folders can hold the same relative name.
            todo.append(.init(key: c.url.path, size: files.size(of: c.url), url: c.url))
        }
        return try await ImportStreamer(collector: collector, uploader: uploader).run(
            units: todo, report: report, runID: run, resume: resume, uploaded: uploaded, save: save,
            onProgress: onProgress
        ) { unit, sink in
            guard let url = unit.url else { return "unreadable" }
            return try await collector.stream(file: url, sink: sink)
        }
    }
}
