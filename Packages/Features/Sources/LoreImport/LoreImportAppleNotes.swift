// LoreImportAppleNotes — "Import Apple Notes…" (plan R4-03, T13): read Notes on this Mac, convert to Markdown here, send
// attachments first and then the notes as an `apple_notes` run, then the same review as every import.
// Security model: see `AppleNotesSource` (fixed script, only on this click, never run note content) and `NoteHTML`.
// Note text is private: nothing is logged and failures say fixed sentences.
import AppKit
import CoreKit
import Foundation

extension LoreImportModel {
    /// Only ever called by the person's click, so macOS asks for Automation access then and not before.
    func importAppleNotes() {
        phase = .working("Reading Apple Notes…", nil)
        let again: () -> Void = { [weak self] in self?.importAppleNotes() }
        Task {
            await Task.yield()
            let source = AppleNotesSource()
            defer { source.cleanUp() }
            var id: String?
            do {
                let notes = try await source.scan()
                let prepared = await Task.detached { AppleNotesExport.prepare(notes) }.value
                leftOut = prepared.skipped
                guard !prepared.files.isEmpty else {
                    fail("No notes could be read from Apple Notes.", retry: again)
                    return
                }
                let sent = try await sendAttachments(prepared.files)
                phase = .working("Sending \(LoreImportWords.notes(sent.count))…", nil)
                var r = try await service.startAppleNotesImport(project: project.isEmpty ? nil : project)
                id = r.id
                let runID = r.id
                let batches = LoreImportDisk.batches(sent)
                for (i, batch) in batches.enumerated() {
                    phase = .working(
                        "Sending \(LoreImportWords.notes(sent.count))…", Double(i) / Double(max(batches.count, 1)))
                    r = try await retrying { try await service.addImportFiles(runID, batch) }
                }
                r = try await retrying { try await service.finishImport(runID) }
                await review(r)
            } catch {
                if let id { _ = try? await service.abandonImport(id) }
                if let e = error as? AppleNotesError {
                    if e == .permissionDenied {
                        phase = .needsPermission
                    } else {
                        fail("Notes could not be read. Open Notes once, then try again.", retry: again)
                    }
                } else {
                    fail(words(error), retry: again)
                }
            }
        }
    }

    /// Sends every attachment (the Core allows images and PDF up to 10 MB; anything else is left out and the note says so)
    /// and returns the notes as files linking them.
    private func sendAttachments(_ notes: [AppleNotePrepared]) async throws -> [LoreImportFile] {
        var files: [LoreImportFile] = []
        for (i, note) in notes.enumerated() {
            var shas: [String?] = []
            for att in note.attachments {
                shas.append(try await sendAttachment(att))
            }
            files.append(LoreImportFile(path: note.path, text: AppleNotesExport.finish(note, shas: shas)))
            if !note.attachments.isEmpty {
                phase = .working("Sending attachments…", Double(i) / Double(max(notes.count, 1)))
            }
        }
        return files
    }

    private func sendAttachment(_ att: AppleNoteAttachment) async throws -> String? {
        guard let url = att.file,
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
            size > 0, size <= AppleNotesExport.attachmentMax,
            let data = try? Data(contentsOf: url)
        else { return nil }
        do {
            return try await retrying { try await service.uploadAttachment(data) }
        } catch {
            // 415 (a type outside the allow-list) and 413 (too large, store full) leave this one attachment out.
            if case .http(let status, _, _)? = CoreError.unwrapping(error), status == 415 || status == 413 {
                return nil
            }
            throw error
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
