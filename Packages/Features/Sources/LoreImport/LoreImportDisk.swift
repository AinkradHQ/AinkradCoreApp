// LoreImportDisk — reads the files a person chose for "Import Files…" (plan R4-02).
//
// Only what was picked is opened: `.md` / `.markdown` files and `.zip` files, nothing is walked. Files the Brain pre-filter
// calls restricted (`.env*`, keys, tokens), files over 1 MB and text that is not UTF-8 are skipped and counted by reason,
// never sent. The Core checks every path and size again (R4-01); this only keeps unwanted bytes off the wire.
import BrainImport
import CoreKit
import Foundation

struct LoreImportPick: Sendable, Equatable {
    var zips: [Data] = []
    var files: [LoreImportFile] = []
    /// Reason -> how many files were left out.
    var skipped: [String: Int] = [:]

    var isEmpty: Bool { zips.isEmpty && files.isEmpty }
    var skippedCount: Int { skipped.values.reduce(0, +) }
}

enum LoreImportDisk {
    /// The Core's own caps: a note file, a zip, and the files one run takes.
    static let fileMax = 1 << 20
    static let zipMax = 16 << 20
    static let filesMax = 2000
    /// One upload call stays under the signed-body cap (1 MiB) and the Core's 200 items.
    static let batchBytes = 900_000
    static let batchItems = 200

    static func read(_ urls: [URL]) -> LoreImportPick {
        var out = LoreImportPick()
        var taken = Set<String>()
        func skip(_ why: String) { out.skipped[why, default: 0] += 1 }
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if ext == "zip" {
                if size > zipMax {
                    skip("zip over 16 MB")
                } else if let d = try? Data(contentsOf: url) {
                    out.zips.append(d)
                } else {
                    skip("not readable")
                }
                continue
            }
            guard ["md", "markdown"].contains(ext) else {
                skip("not Markdown")
                continue
            }
            if PreFilter.isRestricted(url.path) {
                skip("private file")
            } else if size > fileMax {
                skip("over 1 MB")
            } else if out.files.count >= filesMax {
                skip("past \(filesMax) files")
            } else if let d = try? Data(contentsOf: url), let text = String(data: d, encoding: .utf8) {
                // The path is the name; a second file of the same name takes its folder's name too.
                var path = url.lastPathComponent
                if taken.contains(path) { path = url.deletingLastPathComponent().lastPathComponent + "/" + path }
                let file = LoreImportFile(path: path, text: text)
                if ((try? JSONEncoder().encode(file).count) ?? Int.max) > batchBytes {
                    // A call carries at most 1 MiB of JSON, and escaping can grow a file past it.
                    skip("too large to send")
                } else if taken.insert(path).inserted {
                    out.files.append(file)
                } else {
                    skip("same name")
                }
            } else {
                skip("not readable text")
            }
        }
        return out
    }

    /// Files grouped so each call's JSON stays under the cap (JSON escaping makes the size differ from the text's).
    static func batches(_ files: [LoreImportFile]) -> [[LoreImportFile]] {
        let enc = JSONEncoder()
        var out: [[LoreImportFile]] = []
        var cur: [LoreImportFile] = []
        var size = 0
        for f in files {
            let n = ((try? enc.encode(f).count) ?? f.text.utf8.count * 2) + 1
            if !cur.isEmpty, size + n > batchBytes || cur.count >= batchItems {
                out.append(cur)
                cur = []
                size = 0
            }
            cur.append(f)
            size += n
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
