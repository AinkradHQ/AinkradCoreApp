// AppleNotesExport — turns scanned Apple Notes into the Markdown files the Core's `apple_notes` import takes (R4-03, T13).
// Security model: that of `AppleNotesSource` and `NoteHTML`. Pure text work; note content is never logged or run.
// Each note becomes `<Folder>/<title>-<id hash>.md` (the Core makes the folder a tag; the hash keeps the path stable, so a
// second import updates the note it made). Attachments are sent first and linked by `lore-attachment:<sha256>`.
import CryptoKit
import Foundation

struct AppleNotePrepared: Sendable {
    let path: String
    let markdown: String
    let attachments: [AppleNoteAttachment]
}

enum AppleNotesExport {
    /// A note file the Core takes is at most 1 MiB, and one call at most about 900 KB of JSON.
    static let markdownMax = 800_000
    /// The Core's own attachment cap.
    static let attachmentMax = 10 << 20

    /// Notes to files. `skipped` counts what was left out, by reason.
    static func prepare(_ notes: [AppleNote]) -> (files: [AppleNotePrepared], skipped: [String: Int]) {
        var files: [AppleNotePrepared] = []
        var skipped: [String: Int] = [:]
        for note in notes {
            guard let converted = NoteHTML.convert(note.html) else {
                skipped["over 5 MB", default: 0] += 1
                continue
            }
            var body = converted.markdown
            let title = clean(note.title, fallback: "Untitled", max: 120)
            // Notes starts a body with its title as a heading; do not say it twice.
            let first = body.prefix { $0 != "\n" }.drop { $0 == "#" || $0 == " " }
            if first.trimmingCharacters(in: .whitespaces) != title { body = "# \(title)\n\n" + body }
            guard body.utf8.count <= markdownMax else {
                skipped["over 1 MB", default: 0] += 1
                continue
            }
            let name = clean(note.title, fallback: "Untitled", max: 60) + "-" + hash(note.id) + ".md"
            files.append(
                AppleNotePrepared(
                    path: clean(note.folder, fallback: "Notes", max: 60) + "/" + name, markdown: body,
                    attachments: note.attachments))
        }
        return (files, skipped)
    }

    /// The note text with its attachments appended: `shas[i]` is the stored sha of `attachments[i]`, nil when it could not
    /// be sent (the note then says so, so nothing goes missing silently).
    static func finish(_ note: AppleNotePrepared, shas: [String?]) -> String {
        var text = note.markdown
        let lines = zip(note.attachments, shas).map { att, sha -> String in
            let name = att.name.filter { !"[]()\n\r".contains($0) }
            guard let sha else { return "_The attachment “\(name)” could not be imported._" }
            let link = "(lore-attachment:\(sha))"
            return name.lowercased().hasSuffix(".pdf") ? "[\(name)]\(link)" : "![\(name)]\(link)"
        }
        if !lines.isEmpty { text += "\n\n" + lines.joined(separator: "\n\n") }
        return text
    }

    /// A path part: no `/`, `\`, `:`, control or format characters (ZWJ, bidi marks), no leading dot, at most `max` characters.
    static func clean(_ s: String, fallback: String, max: Int) -> String {
        let kept = s.unicodeScalars.map {
            "/\\:".unicodeScalars.contains($0) || $0.value < 0x20 || $0.value == 0x7F
                || $0.properties.generalCategory == .format ? "-" : String($0)
        }.joined()
        let t = String(kept.prefix(max)).trimmingCharacters(in: .whitespaces)
        let undotted = String(t.drop { $0 == "." })
        return undotted.isEmpty ? fallback : undotted
    }

    static func hash(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
