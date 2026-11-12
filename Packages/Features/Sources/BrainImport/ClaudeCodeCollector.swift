import Foundation

/// Reads files for a collector. Injected so a test can prove which files were opened.
public protocol FileAccess: Sendable {
    func listFiles(under root: URL) -> [URL]
    /// The size from file attributes; the file is not opened.
    func size(of url: URL) -> UInt64
    /// Calls `each` with every line (no line end), reading `chunk` bytes at a time. A line longer than
    /// `maxLine` is dropped, never held. `each` returns false to stop reading this file.
    func readLines(_ url: URL, chunk: Int, maxLine: Int, _ each: (Data) async throws -> Bool) async throws
}

public struct DiskFiles: FileAccess {
    public init() {}
    public func listFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return e.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    public func size(of url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    public func readLines(_ url: URL, chunk: Int, maxLine: Int, _ each: (Data) async throws -> Bool) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var line = Data()
        var dropping = false
        while true {
            guard let buf = try handle.read(upToCount: chunk), !buf.isEmpty else { break }
            var start = buf.startIndex
            while start < buf.endIndex {
                if let nl = buf[start...].firstIndex(of: 10) {
                    if !dropping {
                        line.append(buf[start..<nl])
                        if !line.isEmpty, line.count <= maxLine, try await !each(line) { return }
                    }
                    line = Data()
                    dropping = false
                    start = nl + 1
                } else {
                    if !dropping {
                        line.append(buf[start...])
                        if line.count > maxLine {
                            line = Data()
                            dropping = true
                        }
                    }
                    start = buf.endIndex
                }
            }
        }
        if !dropping, !line.isEmpty { _ = try await each(line) }
    }
}

/// Test instrument: the bytes the collector holds at once, by slot, and the highest sum seen.
public final class BufferGauge: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [String: Int] = [:]
    private var top = 0
    public init() {}
    func set(_ slot: String, _ bytes: Int) {
        lock.withLock {
            slots[slot] = bytes
            top = max(top, slots.values.reduce(0, +))
        }
    }
    public var peak: Int { lock.withLock { top } }
}

/// Claude Code sessions: `<root>/<encoded project dir>/<session>.jsonl`, one JSON record per line.
/// A session becomes one item (or ordered parts when it is large): the user and assistant text, with
/// tool output trimmed. It is read as a stream, so memory is bounded by a chunk, a line, and a part,
/// never by the file. Records of an unknown shape are skipped, never guessed at.
public struct ClaudeCodeCollector: Sendable {
    public let device: String
    public let files: any FileAccess
    public let chunk: Int
    public let maxLine: Int
    public let gauge: BufferGauge?
    /// Tool output longer than this many characters is cut.
    public static let toolOutputLimit = 400
    public static let defaultChunk = 1 << 20
    public static let defaultMaxLine = 4 << 20

    public init(
        device: String, files: any FileAccess = DiskFiles(), chunk: Int = defaultChunk,
        maxLine: Int = defaultMaxLine, gauge: BufferGauge? = nil
    ) {
        self.device = device
        self.files = files
        self.chunk = chunk
        self.maxLine = maxLine
        self.gauge = gauge
    }

    /// Reads one session file and hands each item to `sink` as soon as it is complete. Returns the
    /// reason the file was skipped, or nil. An error from `sink` (a failed upload) is thrown.
    public func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String? {
        var s = SessionStream(path: url.path, device: device, gauge: gauge)
        var failure: Error?
        var skip: String?
        func emit(_ items: [ImportItem]) async -> Bool {
            for i in items {
                do { try await sink(i) } catch {
                    failure = error
                    return false
                }
            }
            return true
        }
        do {
            try await files.readLines(url, chunk: chunk, maxLine: maxLine) { line in
                gauge?.set("reader", chunk + line.count)
                switch s.add(line: line) {
                case .skip(let why):
                    skip = why
                    return false
                case .items(let items): return await emit(items)
                }
            }
        } catch {
            gauge?.set("reader", 0)
            return "unreadable"
        }
        gauge?.set("reader", 0)
        if let failure { throw failure }
        if let skip { return skip }
        if case .items(let items) = s.finish() { _ = await emit(items) }
        if let failure { throw failure }
        return s.emitted == 0 ? "empty" : nil
    }

    static func text(of content: Any?) -> String {
        if let s = content as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for b in blocks {
            switch b["type"] as? String {
            case "text": if let t = b["text"] as? String { parts.append(t) }
            case "tool_result":
                let nested = (b["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }
                let raw = (b["content"] as? String) ?? nested?.joined(separator: "\n") ?? ""
                parts.append("[tool output] " + trim(raw))
            default: break  // tool calls, thinking and images are not kept
            }
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trim(_ s: String) -> String {
        s.count > toolOutputLimit ? String(s.prefix(toolOutputLimit)) + " [trimmed]" : s
    }
}
