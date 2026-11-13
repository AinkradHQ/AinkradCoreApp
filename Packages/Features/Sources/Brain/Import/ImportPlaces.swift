import BrainImport
import Foundation

/// Where the "Notes and docs" sources look: folders the person chose, or a search of the home folder. Kept per Mac.
/// Starts empty: nothing is read until the person adds a folder or asks for the search. Not sandboxed, so a chosen
/// folder is just a path (no bookmark); a folder macOS refuses (Privacy & Security) reads as empty and is counted.
public final class ImportPlaces: @unchecked Sendable {
    public enum Mode: String, Sendable { case folders, disk }

    public typealias Search = @Sendable (@escaping @Sendable (Int) -> Void) -> DocWalker.Found
    public typealias Suggest = @Sendable (_ exclude: [URL]) -> [URL]

    private let lock = NSLock()
    private var _mode: Mode
    private var _folders: [URL]
    private var _chat: URL?
    private var _disk: DocWalker.Found?
    private let defaults: UserDefaults?
    private let diskFile: URL?
    private let search: Search
    private let suggest: Suggest

    /// This Mac's choices, in `UserDefaults` and Application Support.
    public static let shared = ImportPlaces(
        defaults: .standard,
        diskFile: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Ainkrad/brain-import-disk.json"))

    public init(
        defaults: UserDefaults? = nil, diskFile: URL? = nil, mode: Mode = .folders, folders: [URL] = [],
        chat: URL? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, search: Search? = nil,
        suggest: Suggest? = nil
    ) {
        self.defaults = defaults
        self.diskFile = diskFile
        self.search = search ?? { progress in DocWalker().walk(root: home, progress: progress) }
        self.suggest = suggest ?? { Self.suggestions(home: home, exclude: $0) }
        if let d = defaults {
            _mode = Mode(rawValue: d.string(forKey: "brain.import.mode") ?? "") ?? .folders
            _folders = (d.stringArray(forKey: "brain.import.folders") ?? []).map { URL(fileURLWithPath: $0) }
            _chat = d.string(forKey: "brain.import.chat").map { URL(fileURLWithPath: $0) }
        } else {
            _mode = mode
            _folders = folders
            _chat = chat
        }
        _disk = diskFile.flatMap { try? JSONDecoder().decode(DocWalker.Found.self, from: Data(contentsOf: $0)) }
    }

    public var mode: Mode {
        get { lock.withLock { _mode } }
        set {
            lock.withLock { _mode = newValue }
            defaults?.set(newValue.rawValue, forKey: "brain.import.mode")
        }
    }

    public var folders: [URL] {
        get { lock.withLock { _folders } }
        set {
            lock.withLock { _folders = newValue }
            defaults?.set(newValue.map(\.path), forKey: "brain.import.folders")
        }
    }

    /// The one folder chat exports are read from.
    public var chat: URL? {
        get { lock.withLock { _chat } }
        set {
            lock.withLock { _chat = newValue }
            defaults?.set(newValue?.path, forKey: "brain.import.chat")
        }
    }

    /// What the last whole-disk search found. A sync reads these folders and files again; it does not walk the disk.
    public var disk: DocWalker.Found? { lock.withLock { _disk } }

    /// Runs the whole-disk search on this thread (call it off the main actor) and keeps the answer, a stopped one too.
    public func runSearch(progress: @escaping @Sendable (Int) -> Void) -> DocWalker.Found {
        let found = search(progress)
        lock.withLock { _disk = found }
        if let diskFile {
            try? FileManager.default.createDirectory(
                at: diskFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(found).write(to: diskFile, options: .atomic)
        }
        return found
    }

    public func suggestions(excluding: [URL]) -> [URL] { suggest(excluding) }

    /// Folders under `home` (two levels) that look like projects or notes: a `Docs` folder, AGENTS.md or CLAUDE.md, an
    /// Obsidian vault, or a folder that holds git repositories. Never added on their own. Desktop, Documents and
    /// Downloads are not opened here: listing them would make macOS ask for access before the person has chosen
    /// anything. At most `limit`, a folder inside another suggestion left out.
    public static func suggestions(
        home: URL, exclude: [URL], limit: Int = 3, files: any FileAccess = DiskFiles()
    ) -> [URL] {
        let fm = FileManager.default
        let guarded: Set<String> = [
            "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications",
        ]
        let skip = DocWalker.skipDirs
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        func listable(_ u: URL) -> Bool {
            let n = u.lastPathComponent
            return isDir(u) && !n.hasPrefix(".") && !skip.contains(n.lowercased())
        }
        func marked(_ d: URL) -> Bool {
            let kids = files.children(of: d)
            let names = Set(kids.map(\.lastPathComponent))
            if names.contains(".obsidian") || names.contains("Docs") || names.contains("docs") { return true }
            if names.contains("CLAUDE.md") || names.contains("AGENTS.md") { return true }
            return kids.contains { fm.fileExists(atPath: $0.appending(path: ".git").path) }
        }
        // Compared as real paths: a listing can come back as /private/var where the person's choice says /var.
        func real(_ u: URL) -> String { u.resolvingSymlinksInPath().path }
        let taken = exclude.map(real)
        var out: [URL] = []
        for top in files.children(of: home).filter(listable).sorted(by: { $0.path < $1.path })
        where !guarded.contains(top.lastPathComponent) {
            for d in [top] + files.children(of: top).filter(listable).sorted(by: { $0.path < $1.path })
            where marked(d) && !taken.contains(real(d))
                && !out.contains(where: { d.path.hasPrefix($0.path + "/") })
                && !taken.contains(where: { real(d).hasPrefix($0 + "/") })
            {
                out.append(d)
                if out.count == limit { return out }
                if d == top { break }  // a marked top folder stands for what is inside it
            }
        }
        return out
    }
}
