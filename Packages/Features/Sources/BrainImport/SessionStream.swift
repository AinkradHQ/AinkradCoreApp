import Foundation

/// The parser for one session file, fed a line at a time. It keeps the part being built and one
/// finished part (so a lone part is known to be lone); nothing else of the file.
struct SessionStream {
    /// What one record of a session says, once a format's decoder has read it.
    struct Read {
        var cwd: String?
        var timestamp: String?
        /// "user" or "assistant", and the text of the turn.
        var turn: (role: String, text: String)?
        /// Set by a decoder that does not recognise the format (first record) or a record it must not read.
        var skip: String?
    }

    enum Step {
        case items([ImportItem])
        case skip(String)
    }

    let path: String
    let device: String
    let gauge: BufferGauge?
    let kind: String
    let defaultTitle: String
    let strictFirst: Bool
    private(set) var emitted = 0
    private var cwd: String?
    private var cwdKnown = false
    private var first: String?
    private var last: String?
    private var title: String?
    private var cur = ""
    private var held: String?
    private var index = 0
    private var lines = 0

    /// `cwd`, `startedAt` and `title` are known before the first record (from the path, file times or an
    /// export's own fields); a record may still set what is nil.
    init(
        path: String, device: String, gauge: BufferGauge?, kind: String = "claude_code",
        defaultTitle: String = "Claude Code session", cwd: String? = nil, startedAt: String? = nil,
        title: String? = nil, strictFirst: Bool = false
    ) {
        self.strictFirst = strictFirst
        self.path = path
        self.device = device
        self.gauge = gauge
        self.kind = kind
        self.defaultTitle = defaultTitle
        self.cwd = cwd
        self.cwdKnown = cwd != nil
        self.first = startedAt
        self.last = startedAt
        self.title = title
    }

    /// One JSON line of a session file, read by `decode`.
    mutating func add(line: Data, decode: (_ obj: [String: Any], _ first: Bool) -> Read) -> Step {
        defer { lines += 1 }
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            // A format that checks its first record does not accept a first line that is not JSON.
            return lines == 0 && strictFirst ? .skip("unknown-format") : .items([])
        }
        return add(decode(obj, lines == 0))
    }

    mutating func add(_ r: Read) -> Step {
        if let why = r.skip { return .skip(why) }
        if !cwdKnown, let c = r.cwd {
            cwd = c
            cwdKnown = true
            // The working directory is only known after reading; a deprecated project still stops here.
            if let p = PreFilter.deprecatedProject(in: c) { return .skip("deprecated:\(p)") }
            if PreFilter.isRestricted(c) { return .skip("restricted") }
        }
        if let t = r.timestamp {
            if first == nil { first = t }
            last = t
        }
        guard let turn = r.turn, !turn.text.isEmpty else { return .items([]) }
        let text = turn.text
        if title == nil, turn.role == "user" { title = text }
        let entry = "\(turn.role == "user" ? "User" : "Assistant"): \(text)"
        var out: [ImportItem] = []
        if !cur.isEmpty, cur.utf8.count + entry.utf8.count + 2 > ItemFormat.partBytes {
            out += finish(part: cur)
            cur = ""
        }
        if entry.utf8.count > ItemFormat.partBytes {
            let pieces = ItemFormat.split(entry)
            for p in pieces.dropLast() { out += finish(part: p) }
            cur = pieces.last ?? ""
        } else {
            cur += (cur.isEmpty ? "" : "\n\n") + entry
        }
        gauge?.set("parts", cur.utf8.count + (held?.utf8.count ?? 0))
        return .items(out)
    }

    mutating func finish() -> Step {
        var out: [ImportItem] = []
        if !cur.isEmpty {
            out += finish(part: cur)
            cur = ""
        }
        if let h = held {
            held = nil
            out += make(h, multi: emitted > 0)
        }
        gauge?.set("parts", 0)
        return .items(out)
    }

    /// A part is complete: release the one before it, now known to have a successor.
    private mutating func finish(part: String) -> [ImportItem] {
        cwdKnown = true  // no working directory by the first full part: stop looking
        var out: [ImportItem] = []
        if let h = held { out += make(h, multi: true) }
        held = part
        return out
    }

    private mutating func make(_ part: String, multi: Bool) -> [ImportItem] {
        defer { index += 1 }
        guard let first else { return [] }
        let headline = String((title ?? defaultTitle).split(separator: "\n").first ?? "").prefix(80)
        emitted += 1
        return [
            ImportItem(
                item_id: ItemFormat.itemID(seed: "\(path)#\(index)"),
                source_kind: kind,
                content_hash: ItemFormat.hash(part),
                origin: .init(device: device, path: path, range: multi ? [UInt64(index), 0] : nil),
                project_hint: cwd,
                author: .init(kind: "person", name: "me"),
                title: multi ? "\(headline) (part \(index + 1))" : String(headline),
                text: part, links: [], started_at: first, ended_at: last == first ? nil : last)
        ]
    }
}
