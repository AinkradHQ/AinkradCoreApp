// LoreNoteActions — what a note's right-click menu (and the header's More) does: rename, move, copy a link, delete
// with Undo. Only the Core's own calls: rename is a save with a new first heading (the Core takes a note's title from
// its first H1 and rewrites the links to it), delete is `trash` (30 days, restorable), Undo is `restore`.
import AppKit
import CoreKit
import Foundation

extension LoreModel {
    /// `text` with `title` as its first H1 (outside code), or with one put on top when it has none: an H1 beats the
    /// first line for the Core's title, so this always names the note.
    static func retitled(_ text: String, to title: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var inCode = false
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if !inCode, line.hasPrefix("# ") || line.hasPrefix("#\t") || line == "#" {
                lines[i] = "# \(title)"
                return lines.joined(separator: "\n")
            }
        }
        return text.isEmpty ? "# \(title)\n" : "# \(title)\n\n\(text)"
    }

    /// One line, no spaces at the ends; nil when nothing is left.
    static func cleanTitle(_ s: String) -> String? {
        let t = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// Daily notes are named by their date and stay personal: only plain notes rename, move and go to the trash.
    static func canEdit(_ n: LoreNote) -> Bool { n.kind == "note" && !n.trashed }

    func rename(_ id: String, to raw: String) async {
        guard let service, let title = Self.cleanTitle(raw) else { return }
        if id == note?.id {
            guard load == .ready, note?.title != title else { return }
            page.show(Self.retitled(page.markdown(), to: title), fold: true)
            await save()
        } else {
            do {
                let n = try await service.note(id)
                guard Self.canEdit(n), n.title != title else { return }
                _ = try await service.save(id, baseRev: n.rev, text: Self.retitled(n.text, to: title))
            } catch { return say(error) }
        }
        await refreshSide()
    }

    /// Moves `id` to a project (nil = personal) from the list; the open note's chip follows.
    func moveNote(_ id: String, to project: String?) async {
        guard let service else { return }
        do {
            let n = try await service.move(id, project: project)
            if id == note?.id { moved(n) }
            host.shell.showToast("Moved to \(project.flatMap { projectNames[$0] } ?? "Personal").", kind: .info)
        } catch { say(error) }
        await refreshSide()
    }

    /// To the trash, with Undo (also ⌘Z) on the toast. The open note gives way to today's.
    func trashNote(_ id: String, title: String) async {
        guard let service else { return }
        let wasOpen = id == note?.id
        if wasOpen { await leave() }
        do {
            _ = try await service.trash(id)
        } catch { return say(error) }
        if wasOpen { await openDay(todayKey) } else { await refreshSide() }
        host.shell.showToast("“\(title)” moved to the trash.", kind: .info) { [weak self] in
            Task { await self?.untrash(id, reopen: wasOpen) }
        }
    }

    func untrash(_ id: String, reopen: Bool) async {
        guard let service else { return }
        do {
            _ = try await service.restore(id)
        } catch { return say(error) }
        if reopen { await openNote(id) } else { await refreshSide() }
    }

    /// A Markdown link to the note that opens it from any other note.
    static func link(_ id: String, title: String) -> String { "[\(title)](lore:\(id))" }

    func copyLink(_ id: String, title: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.link(id, title: title), forType: .string)
        host.shell.showToast("Link copied.", kind: .info)
    }
}
