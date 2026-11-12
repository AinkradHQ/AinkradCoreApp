import Foundation

/// A collector that turns the files under a root into items, one file at a time (`ImportStreamer` drives it).
public protocol FileCollector: Sendable {
    var files: any FileAccess { get }
    /// Whether this collector reads a file of that name.
    func accepts(_ url: URL) -> Bool
    /// The files to read under `root`, found by name only. Nothing is opened.
    func candidates(under root: URL) -> [URL]
    /// Reads one file and hands each item to `sink` as soon as it is complete. Returns the reason the file
    /// was skipped, or nil. An error from `sink` (a failed upload) is thrown.
    func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String?
}

extension FileCollector {
    public func candidates(under root: URL) -> [URL] { files.listFiles(under: root).filter(accepts) }
}

/// ISO 8601 text for a time, the form `started_at` carries.
func isoTime(_ d: Date) -> String { d.formatted(.iso8601) }

/// A collector for a JSON-lines session format. A session file becomes one item (or ordered parts when it
/// is large). It is read as a stream, so memory is bounded by a chunk, a line, and a part, never by the file.
/// Records of an unknown shape are skipped, never guessed at; a file whose first record is not a known shape
/// is skipped whole with `unknown-format`.
public struct LineCollector: FileCollector {
    public let device: String
    public let files: any FileAccess
    public let chunk: Int
    public let maxLine: Int
    public let gauge: BufferGauge?
    let kind: String
    let defaultTitle: String
    let strictFirst: Bool
    let acceptsFile: @Sendable (URL) -> Bool
    let decode: @Sendable ([String: Any], Bool) -> SessionStream.Read
    /// A project hint known from the path, and whether file times stand in for missing timestamps.
    let hint: @Sendable (URL) -> String?
    let usesFileTime: Bool

    init(
        device: String, files: any FileAccess, chunk: Int, maxLine: Int, gauge: BufferGauge?, kind: String,
        defaultTitle: String, strictFirst: Bool = false, usesFileTime: Bool = false,
        hint: @escaping @Sendable (URL) -> String? = { _ in nil },
        accepts: @escaping @Sendable (URL) -> Bool,
        decode: @escaping @Sendable ([String: Any], Bool) -> SessionStream.Read
    ) {
        self.device = device
        self.files = files
        self.chunk = chunk
        self.maxLine = maxLine
        self.gauge = gauge
        self.kind = kind
        self.defaultTitle = defaultTitle
        self.strictFirst = strictFirst
        self.usesFileTime = usesFileTime
        self.hint = hint
        self.acceptsFile = accepts
        self.decode = decode
    }

    public func accepts(_ url: URL) -> Bool { acceptsFile(url) }

    public func stream(file url: URL, sink: (ImportItem) async throws -> Void) async throws -> String? {
        var s = SessionStream(
            path: url.path, device: device, gauge: gauge, kind: kind, defaultTitle: defaultTitle, cwd: hint(url),
            startedAt: usesFileTime ? files.modified(of: url).map(isoTime) : nil, strictFirst: strictFirst)
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
                switch s.add(line: line, decode: decode) {
                case .skip(let why):
                    skip = why
                    return false
                case .items(let items): return await emit(items)
                }
            }
        } catch {
            gauge?.set("reader", 0)
            return error as? FileReadError == .needsZstd ? "needs-zstd" : "unreadable"
        }
        gauge?.set("reader", 0)
        if let failure { throw failure }
        if let skip { return skip }
        if case .items(let items) = s.finish() { _ = await emit(items) }
        if let failure { throw failure }
        return s.emitted == 0 ? "empty" : nil
    }
}
