import BrainImport
import Foundation

/// One thing the wizard can collect from. The Claude Code one is the only one in M1.
public protocol ImportSource: Sendable {
    /// The id the Core knows (`source_kind` of its items).
    var id: String { get }
    var title: String { get }
    /// What is there and what a rule already skips, from file names alone: no file is opened.
    func scan() async -> CollectReport
    func collect() async -> (items: [ImportItem], report: CollectReport)
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

    public func collect() async -> (items: [ImportItem], report: CollectReport) {
        var report = CollectReport()
        let items = ClaudeCodeCollector(device: device, files: files).collect(root: root, report: &report)
        return (items, report)
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
        default: return reason
        }
    }

    /// "3 for a refused project, 2 for restricted files". Empty when nothing was skipped.
    public static func skips(_ skipped: [String: Int]) -> String {
        var by: [String: Int] = [:]
        for (k, n) in skipped { by[skip(k), default: 0] += n }
        return by.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    public static func left(seconds: Int) -> String {
        seconds < 90 ? "\(max(seconds, 1)) s" : "\((seconds + 30) / 60) min"
    }
}
