import BrainImport
import Foundation

/// One thing the wizard can collect from.
public protocol ImportSource: Sendable {
    /// The id the Core knows (`source_kind` of its items).
    var id: String { get }
    var title: String { get }
    /// Why this source cannot be collected yet, in plain words; nil when it can. Such a source is listed in
    /// step 1 as "not readable yet" and can not be chosen.
    var notReadable: String? { get }
    /// What is there and what a rule already skips, from file names alone: no file is opened.
    func scan() async -> CollectReport
    /// Reads and uploads file by file, so memory never depends on how much there is. Files in `resume`
    /// are not read again; `save` is told what is finished.
    func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport
}

extension ImportSource {
    public var notReadable: String? { nil }
}

/// Claude Code sessions, `<root>/<project>/<session>.jsonl`.
public struct ClaudeCodeSource: ImportSource {
    public let id = "claude_code"
    public let title = "Claude Code sessions"
    let device: String
    let root: URL
    let files: any FileAccess

    public init(device: String, root: URL, files: any FileAccess = DiskFiles()) {
        self.device = device
        self.root = root
        self.files = files
    }

    /// This Mac's `~/.claude/projects`.
    public static func standard() -> ClaudeCodeSource {
        ClaudeCodeSource(
            device: Host.current().localizedName ?? "Mac",
            root: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects"))
    }

    public func scan() async -> CollectReport {
        var report = CollectReport()
        for url in files.listFiles(under: root) where url.pathExtension == "jsonl" {
            report.found += 1
            if let why = PreFilter.skipReason(path: url.path.replacingOccurrences(of: root.path, with: "")) {
                report.skipped[why, default: 0] += 1
            }
        }
        return report
    }

    public func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        let streamer = ImportStreamer(collector: ClaudeCodeCollector(device: device, files: files), uploader: uploader)
        return try await streamer.run(
            root: root, runID: run, resume: resume, uploaded: uploaded, save: save, onProgress: onProgress)
    }
}

/// The plain words for the counts a run shows. Reasons are codes, never text from an item.
public enum ImportWords {
    /// "deprecated:GitScope" is a refused project; the rest are kinds of skip.
    public static func skip(_ reason: String) -> String {
        if reason.hasPrefix("deprecated:") { return "a refused project" }
        if reason.hasPrefix("rule:") { return "a rule" }
        switch reason {
        case "restricted": return "restricted files"
        case "empty": return "empty"
        case "unreadable": return "unreadable"
        case "unknown-format": return "a format this version does not know"
        case "needs-zstd": return "compressed files (install zstd to read them)"
        case "too-big": return "files too big to read"
        case "zip": return "zip files (unpack them first)"
        default: return reason
        }
    }

    /// "3 for a refused project, 2 for restricted files". Empty when nothing was skipped.
    public static func skips(_ skipped: [String: Int]) -> String {
        var by: [String: Int] = [:]
        for (k, n) in skipped { by[skip(k), default: 0] += n }
        return by.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    /// The file name only, cut in the middle past 28 characters.
    public static func shortName(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard name.count > 28 else { return name }
        return name.prefix(14) + "…" + name.suffix(13)
    }

    public static func bytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    public static func left(seconds: Int) -> String {
        seconds < 90 ? "\(max(seconds, 1)) s" : "\((seconds + 30) / 60) min"
    }
}
