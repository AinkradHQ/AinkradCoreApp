import CoreKit
import Foundation
import Observation

// A run's log, live. The Core streams it over `GET /projects/{id}/run/logs/ws` (a text frame is a `RunLogs`, about every 1.5 s)
// and answers the same page over `GET /projects/{id}/run/logs`; this reads the stream and, when it cannot, polls every 3 s.
// Security model: the Core redacts every line before it leaves; nothing here keeps a line beyond the page's own list.

/// A log line as text: colour and cursor codes the container's tools print are removed, never shown as `[32m`.
enum LogText {
    /// CSI (`ESC [ … final`), OSC (`ESC ] … BEL|ST`) and the two-byte escapes; then a lone `\r` is a line start.
    private static let codes = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[@-Z\\\\-_]")

    static func plain(_ s: String) -> String {
        var t = s
        if t.contains("\u{1B}") {
            t = codes.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        // A progress bar redraws its line with `\r`: the last draw is what was left on screen.
        if t.contains("\r") {
            t = t.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        }
        return t
    }
}

/// Where a log's lines come from: a page on request, and a live tail when the Core has one.
protocol RunLogSource: Sendable {
    func page(after: Int, service: String?) async throws -> RunLogPage
    /// The live tail from `after`; nil when this source has none (the model polls). It finishes when the run ended and throws
    /// when the socket failed.
    func stream(after: Int, service: String?) -> AsyncThrowingStream<RunLogPage, any Error>?
}

extension RunLogSource {
    func stream(after: Int, service: String?) -> AsyncThrowingStream<RunLogPage, any Error>? { nil }
}

/// The Core's log routes for one project, of its newest live run or of one run by id.
struct LiveRunLogSource: RunLogSource {
    let connection: CoreConnection
    let project: Int64
    var run: String?

    /// `?after=&service=&run=`, each escaped as one value.
    static func query(after: Int, service: String?, run: String?, limit: Int? = nil) -> String {
        var q = ["after=\(after)"]
        if let service { q.append("service=\(LiveProjectRunService.seg(service))") }
        if let run { q.append("run=\(LiveProjectRunService.seg(run))") }
        if let limit { q.append("limit=\(limit)") }
        return q.joined(separator: "&")
    }

    private var base: String { "/api/v1/projects/\(project)/run/logs" }

    func page(after: Int, service: String?) async throws -> RunLogPage {
        let target = "\(base)?\(Self.query(after: after, service: service, run: run, limit: 500))"
        do {
            return try RunWire.logs(
                try await connection.signedRequest(method: "GET", target: target, body: Data()), after: after)
        } catch CoreError.http(let status, _, _) where status == 404 || status == 501 {
            return RunLogPage(next: after)
        } catch CoreError.http(let status, let code, let message) {
            throw LiveProjectRunService.failure(status: status, code: code, message: message)
        }
    }

    func stream(after: Int, service: String?) -> AsyncThrowingStream<RunLogPage, any Error>? {
        let target = "\(base)/ws?\(Self.query(after: after, service: service, run: run))"
        let connection = connection
        return AsyncThrowingStream { out in
            let task = Task {
                do {
                    let socket = try await connection.openSocket(target: target)
                    defer { socket.cancel() }
                    var cursor = after
                    while !Task.isCancelled {
                        let frame: CoreSocketFrame
                        do { frame = try await socket.receive() } catch {
                            // 1000 is "the run ended"; anything else is a socket that failed.
                            if socket.closeCode == 1000 { return out.finish() }
                            throw error
                        }
                        guard case .text(let text) = frame, let page = try? RunWire.logs(Data(text.utf8), after: cursor)
                        else { continue }
                        cursor = page.next
                        out.yield(page)
                    }
                    out.finish()
                } catch { out.finish(throwing: error) }
            }
            out.onTermination = { _ in task.cancel() }
        }
    }
}

/// One row of the log: a line, or a gap where the runner dropped lines before it.
struct LogEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case line(ProjectLive.LogLine)
        case skipped(Int)
    }
    let id: Int
    let kind: Kind
}

/// The log of one run on screen: the lines (the last `cap`), the filters, and whether the view follows the newest line.
@MainActor @Observable
final class RunLogsModel {
    enum Feed: Equatable, Sendable {
        /// Not started, or the run is not live.
        case idle
        /// The Core's stream is open.
        case live
        /// Reading a page every few seconds (no stream, or it failed).
        case polling
        /// The Core said the run ended.
        case ended
    }

    /// Lines kept; older ones fall off the top (ponytail: a window, search covers only what is kept).
    static let cap = 2000

    @ObservationIgnored let source: any RunLogSource
    private(set) var entries: [LogEntry] = []
    private(set) var feed = Feed.idle
    /// Lines the runner dropped, in all (the rows say where).
    private(set) var skipped = 0
    private(set) var failure: String?
    /// The service the Core filters to; nil for all. Changing it starts the log again from the oldest line held.
    private(set) var service: String?
    var search = ""
    var showTimes = false
    /// Whether the view stays on the newest line; scrolling up pauses it, `jumpToLatest` or reaching the bottom resumes.
    private(set) var follow = true
    /// Bumps when the view should scroll to the end.
    private(set) var scrollTick = 0
    @ObservationIgnored var pollEvery: Duration = .seconds(3)
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var useStream = true
    /// Asked after every page: false once the run is over, so a log that has ended is read once and not polled for ever.
    @ObservationIgnored var keepReading: @MainActor () -> Bool = { true }
    @ObservationIgnored private var next = 0
    @ObservationIgnored private var counter = 0
    @ObservationIgnored private var lastAppend = Date.distantPast

    init(source: any RunLogSource) { self.source = source }

    // MARK: what is shown

    /// The rows the search keeps; a search hides the gap rows (they belong to no line).
    var shown: [LogEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            if case .line(let l) = $0.kind { return l.text.localizedCaseInsensitiveContains(q) }
            return false
        }
    }

    var lineCount: Int { entries.reduce(0) { if case .line = $1.kind { $0 + 1 } else { $0 } } }

    /// "3 of 120 lines" while searching.
    var matchLine: String? {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let n = shown.count
        return "\(n) of \(ProjectItem.count(lineCount, "line"))"
    }

    static func gapWords(_ n: Int) -> String { "\(n.formatted()) line\(n == 1 ? "" : "s") skipped" }

    /// "14:02:09", the clock of the line (the time zone of this Mac).
    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    /// What Copy puts on the pasteboard: the rows shown, one per line, with the time when it is on.
    var copyText: String {
        shown.map {
            switch $0.kind {
            case .line(let l):
                let when = showTimes ? l.at.map { Self.clock($0) + " " } ?? "" : ""
                return "\(when)\(l.service)  \(l.text)"
            case .skipped(let n): return "… \(Self.gapWords(n))"
            }
        }.joined(separator: "\n")
    }

    // MARK: follow

    /// The end of the list came into view (true) or left it (false). A line arriving moves the end out of view for a moment;
    /// that is not the person scrolling up, so a change right after an append is ignored.
    func endVisible(_ visible: Bool) {
        if visible {
            follow = true
        } else if now().timeIntervalSince(lastAppend) > 0.35 {
            follow = false
        }
    }

    func jumpToLatest() {
        follow = true
        scrollTick += 1
    }

    // MARK: reading

    func setService(_ s: String?) {
        guard s != service else { return }
        service = s
        entries = []
        next = 0
        skipped = 0
        follow = true
    }

    /// Takes one page: its gap, its lines, and where to ask next.
    func ingest(_ page: RunLogPage) {
        next = max(next, page.next)
        if page.lost > 0 {
            skipped += page.lost
            counter += 1
            entries.append(LogEntry(id: counter, kind: .skipped(page.lost)))
        }
        for var l in page.lines {
            l = ProjectLive.LogLine(service: l.service, text: LogText.plain(l.text), seq: l.seq, at: l.at)
            counter += 1
            entries.append(LogEntry(id: counter, kind: .line(l)))
        }
        if entries.count > Self.cap { entries.removeFirst(entries.count - Self.cap) }
        if !page.lines.isEmpty || page.lost > 0 {
            lastAppend = now()
            if follow { scrollTick += 1 }
        }
    }

    /// Reads until the task is cancelled or the run ends (through filter changes): the stream when the Core has one, else (or after it fails) a page
    /// every `pollEvery`. The stream is tried again every tenth page.
    func run() async {
        repeat { await readOnce() } while !Task.isCancelled && feed != .ended
    }

    /// One reading session of the service filter as it is now; it returns early when the filter changes (`run` goes on).
    private func readOnce() async {
        failure = nil
        var polls = 0
        let wanted = service
        while !Task.isCancelled, service == wanted {
            if useStream, polls % 10 == 0, let stream = source.stream(after: next, service: wanted) {
                feed = .live
                do {
                    for try await page in stream {
                        guard service == wanted else { return }
                        failure = nil
                        ingest(page)
                    }
                    // The stream finished: the run ended.
                    if !Task.isCancelled { feed = .ended }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    failure = (error as? RunFailure)?.sentence
                }
            }
            feed = .polling
            do {
                ingest(try await source.page(after: next, service: wanted))
                failure = nil
            } catch is CancellationError {
                return
            } catch {
                failure = (error as? RunFailure)?.sentence ?? "The log could not be read. Trying again."
            }
            polls += 1
            if !keepReading() {
                feed = .ended
                return
            }
            try? await Task.sleep(for: pollEvery)
        }
    }
}

extension RunLogsModel {
    /// A log that already holds `lines` and reads nothing more (the Debug demo's).
    static func fixed(_ lines: [ProjectLive.LogLine], lost: Int = 0, times: Bool = false) -> RunLogsModel {
        let m = RunLogsModel(source: NoRunLogSource())
        m.showTimes = times
        m.ingest(RunLogPage(lines: lines, next: lines.count, lost: lost))
        return m
    }
}

private struct NoRunLogSource: RunLogSource {
    func page(after: Int, service: String?) async throws -> RunLogPage { RunLogPage(next: after) }
}
