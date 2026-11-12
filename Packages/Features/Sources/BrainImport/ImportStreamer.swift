import Foundation

/// How far a streamed import has got. Sizes come from file attributes; nothing is read ahead.
public struct StreamProgress: Sendable, Equatable {
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: UInt64 = 0
    public var bytesTotal: UInt64 = 0
    /// Path under the root of the file being read, "" before the first.
    public var current = ""
    public init() {}
}

/// What one source has finished, kept on this Mac so an interrupted import carries on. Paths only: no content.
public struct SourceResume: Codable, Sendable, Equatable {
    public var done: Set<String> = []
    public var items = 0
    public var skipped: [String: Int] = [:]
    public init(done: Set<String> = [], items: Int = 0, skipped: [String: Int] = [:]) {
        self.done = done
        self.items = items
        self.skipped = skipped
    }
}

public struct ResumeState: Codable, Sendable, Equatable {
    public var run: String?
    public var sources: [String: SourceResume] = [:]
    public init() {}
}

/// The small local state file. There is no Core route that lists runs, so the run id lives here too.
public struct ResumeStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func standard() -> ResumeStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Ainkrad", directoryHint: .isDirectory)
        return ResumeStore(url: dir.appending(path: "brain-import-state.json"))
    }

    public func load() -> ResumeState {
        (try? JSONDecoder().decode(ResumeState.self, from: Data(contentsOf: url))) ?? ResumeState()
    }

    public func save(_ s: ResumeState) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: url, options: .atomic)
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}

/// Collects and uploads a Claude Code folder one file at a time: read a file in bounded pieces, send its
/// items in batches, forget them, go to the next. A finished file is remembered through `save`.
public struct ImportStreamer: Sendable {
    public let collector: ClaudeCodeCollector
    public let uploader: Uploader
    public let gauge: BufferGauge?
    /// How often the done list is written, at most.
    public let saveEvery: TimeInterval

    public init(
        collector: ClaudeCodeCollector, uploader: Uploader, gauge: BufferGauge? = nil, saveEvery: TimeInterval = 1
    ) {
        self.collector = collector
        self.uploader = uploader
        self.gauge = gauge
        self.saveEvery = saveEvery
    }

    public func run(
        root: URL, runID: String, resume: SourceResume, uploaded: Uploader.Progress,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        var report = CollectReport()
        var todo: [(url: URL, rel: String, size: UInt64)] = []
        for url in collector.files.listFiles(under: root).sorted(by: { $0.path < $1.path })
        where url.pathExtension == "jsonl" {
            report.found += 1
            let rel = url.path.replacingOccurrences(of: root.path, with: "")
            // Decided by the path alone, before the file is opened.
            if let why = PreFilter.skipReason(path: rel) {
                report.skipped[why, default: 0] += 1
                continue
            }
            todo.append((url, rel, collector.files.size(of: url)))
        }
        var state = resume
        var p = StreamProgress()
        p.filesTotal = todo.count
        p.bytesTotal = todo.reduce(0) { $0 + $1.size }
        for f in todo where state.done.contains(f.rel) {
            p.filesDone += 1
            p.bytesDone += f.size
        }
        report.items = state.items
        for (k, n) in state.skipped { report.skipped[k, default: 0] += n }
        await onProgress(p)

        var pending: [ImportItem] = []
        var pendingBytes = 0
        func flush() async throws {
            guard !pending.isEmpty else { return }
            try await uploader.upload(pending, run: runID, progress: uploaded)
            pending = []
            pendingBytes = 0
            gauge?.set("batch", 0)
        }
        var lastSave = Date()
        do {
            for f in todo where !state.done.contains(f.rel) {
                try Task.checkCancellation()
                p.current = f.rel
                await onProgress(p)
                var count = 0
                let why = try await collector.stream(file: f.url) { item in
                    pending.append(item)
                    pendingBytes += item.text.utf8.count + 1024
                    gauge?.set("batch", pendingBytes)
                    count += 1
                    if pendingBytes >= Uploader.maxBatchBytes || pending.count >= Uploader.maxBatchItems {
                        try await flush()
                    }
                }
                try await flush()
                if let why {
                    state.skipped[why, default: 0] += 1
                    report.skipped[why, default: 0] += 1
                } else {
                    state.items += count
                    report.items += count
                }
                state.done.insert(f.rel)
                p.filesDone += 1
                p.bytesDone += f.size
                await onProgress(p)
                if Date().timeIntervalSince(lastSave) >= saveEvery {
                    save(state)
                    lastSave = Date()
                }
            }
        } catch {
            save(state)
            throw error
        }
        save(state)
        return report
    }
}
