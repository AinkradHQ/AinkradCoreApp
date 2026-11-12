import Foundation

/// The parser for one session file, fed a line at a time. It keeps the part being built and one
/// finished part (so a lone part is known to be lone); nothing else of the file.
struct SessionStream {
    enum Step {
        case items([ImportItem])
        case skip(String)
    }

    let path: String
    let device: String
    let gauge: BufferGauge?
    private(set) var emitted = 0
    private var cwd: String?
    private var cwdKnown = false
    private var first: String?
    private var last: String?
    private var title: String?
    private var cur = ""
    private var held: String?
    private var index = 0

    init(path: String, device: String, gauge: BufferGauge?) {
        self.path = path
        self.device = device
        self.gauge = gauge
    }

    mutating func add(line: Data) -> Step {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return .items([]) }
        if !cwdKnown, let c = obj["cwd"] as? String {
            cwd = c
            cwdKnown = true
            // The working directory is only known after reading; a deprecated project still stops here.
            if let p = PreFilter.deprecatedProject(in: c) { return .skip("deprecated:\(p)") }
            if PreFilter.isRestricted(c) { return .skip("restricted") }
        }
        if let t = obj["timestamp"] as? String {
            if first == nil { first = t }
            last = t
        }
        guard let type = obj["type"] as? String, type == "user" || type == "assistant",
            let message = obj["message"] as? [String: Any]
        else { return .items([]) }
        let text = ClaudeCodeCollector.text(of: message["content"])
        guard !text.isEmpty else { return .items([]) }
        if title == nil, type == "user" { title = text }
        let entry = "\(type == "user" ? "User" : "Assistant"): \(text)"
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
        let headline = String((title ?? "Claude Code session").split(separator: "\n").first ?? "").prefix(80)
        emitted += 1
        return [
            ImportItem(
                item_id: ItemFormat.itemID(seed: "\(path)#\(index)"),
                source_kind: "claude_code",
                content_hash: ItemFormat.hash(part),
                origin: .init(device: device, path: path, range: multi ? [UInt64(index), 0] : nil),
                project_hint: cwd,
                author: .init(kind: "person", name: "me"),
                title: multi ? "\(headline) (part \(index + 1))" : String(headline),
                text: part, links: [], started_at: first, ended_at: last == first ? nil : last)
        ]
    }
}
