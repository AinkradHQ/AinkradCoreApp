import Foundation

/// Finds docs and memories by walking a folder (the person's home folder, for "Search the whole disk"). Only names
/// are looked at: no file is opened. What it keeps is folders and file paths, so the same answer can be read again later
/// (a sync) without walking the disk again.
public struct DocWalker: Sendable {
    public struct Limits: Sendable, Equatable {
        public var maxChecked: Int
        public var seconds: TimeInterval
        public init(maxChecked: Int = 400_000, seconds: TimeInterval = 180) {
            self.maxChecked = maxChecked
            self.seconds = seconds
        }
    }

    public struct Found: Codable, Sendable, Equatable {
        /// `Docs` / `docs` folders: every Markdown file under one is a project doc.
        public var docFolders: [String] = []
        /// Folders holding an `.obsidian` folder: every Markdown file under one is a note.
        public var vaults: [String] = []
        /// README*.md, AGENTS.md, CLAUDE.md, GEMINI.md and MEMORY.md found outside the two kinds above.
        public var agentFiles: [String] = []
        /// Files and folders looked at.
        public var checked = 0
        /// Folders macOS did not let this app open (Privacy & Security).
        public var unreadable = 0
        /// Why it stopped before the end: "files" (the cap), "time", or "cancelled". Nil when it finished.
        public var stopped: String?
        public init() {}
    }

    /// Never walked into, at any depth. Names are compared in lower case.
    public static let skipDirs: Set<String> = [
        "library", "node_modules", "deriveddata", "vendor", "pods", "caches", "cache", "trash", ".trash",
        "carthage", ".build", ".cargo", ".rustup", ".gradle", ".m2", "bower_components", ".venv", "venv",
        "__pycache__", "site-packages", ".npm", ".pnpm-store", ".yarn", ".next", ".terraform", ".cache", ".gem",
        ".cocoapods", ".nvm", ".pyenv",
    ]
    /// Build output, but also names a person's own docs folder can have: skipped only next to a repo or a manifest.
    static let outputDirs: Set<String> = ["dist", "build", "target"]
    static let manifests = [
        ".git", "package.json", "Cargo.toml", "go.mod", "Package.swift", "pyproject.toml", "pom.xml", "build.gradle",
        "build.gradle.kts", "CMakeLists.txt",
    ]

    /// True for a folder no walk goes into: a skipped name, a build-output name beside a repo or manifest, or a
    /// well-known cache root (`go/pkg` and `$GOPATH/pkg` for the Go module cache, `.local/share`).
    public static func shouldSkip(_ dir: URL) -> Bool {
        let name = dir.lastPathComponent.lowercased()
        if skipDirs.contains(name) { return true }
        let parent = dir.deletingLastPathComponent()
        if outputDirs.contains(name) {
            return manifests.contains { FileManager.default.fileExists(atPath: parent.appending(path: $0).path) }
        }
        let up = parent.lastPathComponent.lowercased()
        if (name == "pkg" && up == "go") || (name == "share" && up == ".local") { return true }
        if name == "pkg", let gopath = ProcessInfo.processInfo.environment["GOPATH"], !gopath.isEmpty {
            return gopath.split(separator: ":").contains { URL(fileURLWithPath: String($0)).path == parent.path }
        }
        return false
    }
    static let agentNames: Set<String> = ["agents.md", "claude.md", "gemini.md", "memory.md"]

    public let limits: Limits
    public init(limits: Limits = Limits()) { self.limits = limits }

    static func isMarkdown(_ u: URL) -> Bool { ["md", "markdown"].contains(u.pathExtension.lowercased()) }

    static func isAgentFile(_ name: String) -> Bool {
        let n = name.lowercased()
        return agentNames.contains(n) || (n.hasPrefix("readme") && (n.hasSuffix(".md") || n.hasSuffix(".markdown")))
    }

    /// Walks `root`. Runs on the caller's thread and stops when the surrounding task is cancelled, when `limits` run out,
    /// or at the end. `progress` is told the count about every thousand files.
    public func walk(root: URL, progress: @Sendable (Int) -> Void = { _ in }) -> Found {
        var found = Found()
        let began = Date()
        var denied = 0
        let fm = FileManager.default
        guard
            let e = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in
                    denied += 1
                    return true
                })
        else { return found }
        for case let url as URL in e {
            found.checked += 1
            if found.checked % 1000 == 0 {
                progress(found.checked)
                if Task.isCancelled {
                    found.stopped = "cancelled"
                    break
                }
                if Date().timeIntervalSince(began) > limits.seconds {
                    found.stopped = "time"
                    break
                }
            }
            if found.checked >= limits.maxChecked {
                found.stopped = "files"
                break
            }
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if Self.shouldSkip(url) {
                    e.skipDescendants()
                } else if fm.fileExists(atPath: url.appending(path: ".obsidian").path) {
                    found.vaults.append(url.path)
                    e.skipDescendants()
                } else if name.lowercased() == "docs" {
                    found.docFolders.append(url.path)
                    e.skipDescendants()
                }
            } else if Self.isAgentFile(name) {
                found.agentFiles.append(url.path)
            }
        }
        progress(found.checked)
        found.unreadable = denied
        return found
    }

    /// Every Markdown file under `folder`, without the folders a walk skips and without hidden ones.
    public static func markdown(under folder: URL) -> [URL] {
        guard
            let e = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        var out: [URL] = []
        for case let url as URL in e {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if shouldSkip(url) { e.skipDescendants() }
            } else if isMarkdown(url) {
                out.append(url)
            }
        }
        return out
    }

    /// True when `path` or any folder above it is one `shouldSkip` refuses: a list saved by an older walker may name
    /// a dependency cache (`~/go/pkg/...`) the current walker would never enter.
    static func isSkipped(_ path: String) -> Bool {
        var u = URL(fileURLWithPath: path)
        while u.path != "/" {
            if shouldSkip(u) { return true }
            u = u.deletingLastPathComponent()
        }
        return false
    }

    /// The files a `Found` stands for, by kind. Re-reads the listed folders only; a saved path the walker now skips
    /// is dropped.
    public static func files(of found: Found) -> (docs: [URL], vault: [URL], agents: [URL]) {
        let keep = { (l: [String]) in l.filter { !isSkipped($0) } }
        return (
            keep(found.docFolders).flatMap { markdown(under: URL(fileURLWithPath: $0)) },
            keep(found.vaults).flatMap { markdown(under: URL(fileURLWithPath: $0)) },
            keep(found.agentFiles).map { URL(fileURLWithPath: $0) }.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
        )
    }
}

/// What the "Folders I choose" mode reads out of one chosen folder, with the existing collectors' layouts.
public enum PlaceCandidates {
    public enum Kind: String, Sendable { case doc, vault, agents }

    /// Project docs: `<folder>/<project>/Docs/**.md`, and `<folder>/Docs` when the folder is itself a project.
    /// Notes: every Markdown file when the folder is an Obsidian vault. AGENTS.md and CLAUDE.md files: the existing
    /// layout, plus the folder's own.
    public static func files(
        _ kind: Kind, under root: URL, device: String, files: any FileAccess = DiskFiles()
    ) -> [URL] {
        var out: [URL]
        switch kind {
        case .doc:
            out = MarkdownCollector(layout: .projectDocs, device: device, files: files).candidates(under: root)
            out += files.listFiles(under: root.appending(path: "Docs", directoryHint: .isDirectory)).filter(
                MarkdownCollector.isMarkdown)
        case .vault:
            guard FileManager.default.fileExists(atPath: root.appending(path: ".obsidian").path) else { return [] }
            out = MarkdownCollector(layout: .vault, device: device, files: files).candidates(under: root)
        case .agents:
            out = MarkdownCollector(layout: .agentFiles, device: device, files: files).candidates(under: root)
            out += files.children(of: root).filter(MarkdownCollector.isAgentFile)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.path).inserted }
    }
}
