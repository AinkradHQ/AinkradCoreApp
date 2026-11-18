// AppleNotesSource — reads the notes of Notes.app through AppleScript (plan R4-03, T13). Moved from the old AinkradLore
// importer (`AppleNotesScriptSource`), cut down to what the Core import needs, and hardened.
//
// Security model.
// - The script is OURS and fixed. Note text only ever comes back as output text to be parsed; it is never passed to
//   `do shell script`, `run script`, `osascript` or anything that evaluates it. Nothing here opens or runs note content.
// - It runs only when the person asks for the import (the chooser row), never at launch: the first run is when macOS asks
//   for Automation access to Notes. A refusal (-1743) becomes `permissionDenied`, shown as one explanation card.
// - Attachments are saved by Notes into a private folder under the temporary directory (mode 0700). A path the output
//   names is used only when it is inside that folder, so a note that forges an attachment line cannot make this app
//   read another file. Staged bytes are removed when the run ends. The staged file name is never taken from the note.
// - A note's text and names are private: nothing here logs, and errors carry fixed sentences, not Notes' own messages.
//
// ponytail: NSAppleScript runs on the main actor (it is not thread-safe), so a very large library blocks the UI while it
// reads; move to an NSUserAppleScriptTask helper if that matters.
import Foundation

struct AppleNoteAttachment: Equatable, Sendable {
    let name: String
    /// Where Notes saved the bytes; nil when it could not (a link preview, say).
    let file: URL?
}

struct AppleNote: Equatable, Sendable {
    /// Notes' own id (`x-coredata://…`): only ever hashed into a file name.
    let id: String
    let title: String
    let account: String
    let folder: String
    let html: String
    let attachments: [AppleNoteAttachment]
}

enum AppleNotesError: Error, Equatable {
    case permissionDenied
    case unavailable
}

/// One entry per note: id, title, account, folder, HTML body, then (id, name, saved path) for each attachment. Structured
/// values, never delimited text: a note body can hold any character, so nothing in it can end a field or start a record.
protocol ScriptRunner: Sendable {
    func run(_ source: String) throws -> [[String]]
}

/// Runs AppleScript through `NSAppleScript`. Main actor only (it traps otherwise): `scan` hops there before the call.
struct OSAScriptRunner: ScriptRunner {
    func run(_ source: String) throws -> [[String]] {
        try MainActor.assumeIsolated {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { throw AppleNotesError.unavailable }
            let result = script.executeAndReturnError(&error)
            if let error {
                // -1743: not authorised to send Apple events to Notes (an Automation denial).
                if (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw AppleNotesError.permissionDenied }
                throw AppleNotesError.unavailable
            }
            return Self.lists(result)
        }
    }

    /// A list of lists of text, read item by item (AppleEvent descriptors count from 1).
    static func lists(_ d: NSAppleEventDescriptor) -> [[String]] {
        guard d.numberOfItems > 0 else { return [] }
        return (1...d.numberOfItems).compactMap { i in
            guard let inner = d.atIndex(i), inner.numberOfItems > 0 else { return nil }
            return (1...inner.numberOfItems).map { inner.atIndex($0)?.stringValue ?? "" }
        }
    }
}

struct AppleNotesSource: Sendable {
    /// Notes that Notes.app already threw away stay out.
    static let excludedFolder = "Recently Deleted"
    /// The Core stages at most 2 000 items a run.
    static let notesMax = 2000

    let runner: any ScriptRunner
    let stagingRoot: URL

    init(
        runner: any ScriptRunner = OSAScriptRunner(),
        stagingRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lore-notes-" + UUID().uuidString)
    ) {
        self.runner = runner
        self.stagingRoot = stagingRoot
    }

    /// Returns a list with one list per note (see `ScriptRunner`), so no delimiter is involved.
    ///
    /// Iterates accounts, folders, notes (asking a note for its container fails with -1700). The staged file name is
    /// `<note>-<attachment>` with NO extension: the name comes from the note, and an extension taken from it could carry
    /// `/..`. The Core sniffs the bytes, so the name is not needed.
    static func script(stagingRoot: String) -> String {
        let stage = stagingRoot.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
            set out to {}
            set stage to "\(stage)"
            set ni to 0
            tell application "Notes"
              repeat with a in accounts
                set acct to name of a
                repeat with f in folders of a
                  set fname to name of f
                  if fname is not "\(excludedFolder)" then
                    repeat with n in notes of f
                      if ni < \(notesMax) then
                        set ni to ni + 1
                        set rec to {(id of n) as text, (name of n) as text, acct as text, fname as text, (body of n) as text}
                        set ai to 0
                        repeat with att in attachments of n
                          set ai to ai + 1
                          set aname to ""
                          try
                            set aname to (name of att) as string
                          end try
                          set apath to ""
                          if aname is not "" then
                            try
                              set apath to stage & "/" & ni & "-" & ai
                              save att in POSIX file apath
                            on error
                              set apath to ""
                            end try
                          end if
                          set aid to ""
                          try
                            set aid to (id of att) as text
                          end try
                          set rec to rec & {aid, aname, apath}
                        end repeat
                        set end of out to rec
                      end if
                    end repeat
                  end if
                end repeat
              end repeat
            end tell
            return out
            """
    }

    /// Runs the script (asking macOS for Automation access the first time) and returns the notes.
    func scan() async throws -> [AppleNote] {
        try FileManager.default.createDirectory(
            at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let runner = self.runner
        let source = Self.script(stagingRoot: stagingRoot.path)
        let output = try await MainActor.run { try runner.run(source) }
        return Self.parse(output, stagingRoot: stagingRoot)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: stagingRoot) }

    /// A record short of its five fields is DROPPED, never padded: a guessed title would be worse than one note fewer.
    /// Attachments follow as (id, name, path) triples; a cut-off triple is ignored.
    static func parse(_ records: [[String]], stagingRoot: URL) -> [AppleNote] {
        records.prefix(notesMax).compactMap { r -> AppleNote? in
            guard r.count >= 5 else { return nil }
            let attachments = stride(from: 5, to: r.count - 2, by: 3).map {
                AppleNoteAttachment(name: r[$0 + 1], file: inside(stagingRoot, r[$0 + 2]))
            }
            return AppleNote(
                id: r[0], title: r[1], account: r[2], folder: r[3], html: r[4], attachments: attachments)
        }
    }

    /// `path` as a file URL only when it lies inside `root`; a forged path is nil (the attachment is then "not exported").
    static func inside(_ root: URL, _ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let base = root.resolvingSymlinksInPath().path
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        return file.path.hasPrefix(base + "/") ? file : nil
    }
}
