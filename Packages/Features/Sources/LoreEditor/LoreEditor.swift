// LoreEditor — the Lore note editor (plan R6-02, editor A: Markdown symbols hidden, TextKit 2).
//
// Security model (plan T1, T8, T9). Note text is untrusted: imports and AI sessions write it.
// - Nothing is rendered as HTML and there is no web view. Raw HTML in a note is shown as text.
// - A link click opens only http, https and mailto (in the person's browser or mail app). The internal `lore:` and
//   `lore-attachment:` links go to the host, never to the system. Every other scheme (file:, javascript:, app schemes)
//   is never opened: its address is copied and the host is told.
// - Nothing is fetched. No remote URL is loaded, not for links, not for image refs; an image ref shows as a link.
//   Force click / Quick Look and Look Up on a link (live web previews) are off, and the context menu (filtered by
//   action selector, on a copy of the shared menu) has no Open Link, Look Up, Quick Look, Search With, Share, Services
//   or Writing Tools. Writing Tools are off, so note text never leaves the Mac.
// - Parsing is bounded: every inline rule has a length cap, a paragraph over 4,096 characters is plain text, and at most
//   200 spans per paragraph and 10,000 per note are styled (the rest is plain). Text that was not parsed is marked raw
//   and saved exactly as it was, so a nearby edit never escapes it.
// - An upload that finishes after the note changed is dropped; a dropped or pasted file's real type and size (symlinks
//   resolved) are checked before it is read.
// - Paste and drop take plain text or Markdown only; rich text, RTF and HTML on the pasteboard are ignored. Images and
//   PDFs (local files or pasteboard data, ≤ 10 MB, allow-listed types) go to the injected upload hook, and only a
//   `lore-attachment:` ref it returns is inserted.
// - The Markdown string stays the document: what is saved is what `markdown()` returns, unchanged blocks byte-identical.
import AppKit
import CoreUI
import SwiftUI
import UniformTypeIdentifiers

/// Note titles for the `[[` link picker.
@MainActor public protocol LoreNoteTitles: AnyObject {
    /// Titles matching `query` (empty = recent), best first.
    func titles(matching query: String) async -> [String]
}

/// Stand-in until the Core's `/search` exists: filters a fixed list in memory.
// TODO(R2-02): a source backed by `GET /modules/lore/v1/search` (titles only) replaces this in the Lore space.
@MainActor public final class LoreStubTitles: LoreNoteTitles {
    let all: [String]
    public init(_ all: [String] = []) { self.all = all }
    public func titles(matching query: String) async -> [String] {
        let q = query.lowercased()
        return q.isEmpty ? all : all.filter { $0.lowercased().contains(q) }
    }
}

/// One file handed to the upload hook.
public struct LoreUpload: Sendable {
    public let name: String
    public let type: UTType
    public let data: Data
}

/// Stores an attachment and returns its `lore-attachment:<sha256>` URL.
@MainActor public protocol LoreAttachmentUploader: AnyObject {
    func upload(_ file: LoreUpload) async throws -> URL
}

/// Stand-in until the Core stores attachments: refuses, so nothing is inserted.
// TODO(R1-05): an uploader backed by `POST /modules/lore/v1/attachments` replaces this in the Lore space.
@MainActor public final class LoreNoUploads: LoreAttachmentUploader {
    public init() {}
    public func upload(_ file: LoreUpload) async throws -> URL { throw LoreUploadError.unavailable }
}

public enum LoreUploadError: Error { case unavailable }

/// What a link click may do (T9).
public enum LoreLinkPolicy {
    public enum Action: Equatable, Sendable { case open, host, copyOnly }
    public static func action(for url: URL) -> Action {
        switch url.scheme?.lowercased() {
        case "http", "https": url.host?.isEmpty == false ? .open : .copyOnly
        case "mailto": .open
        case "lore", "lore-attachment": .host
        default: .copyOnly
        }
    }
    /// Attachment types the editor hands to the upload hook (T8).
    public static let uploadTypes: [UTType] = [.png, .jpeg, .gif, .webP, .heic, .pdf]
    public static let maxUpload = 10 * 1024 * 1024
}

/// Owns one editor: load a note's Markdown, read it back, react to changes. The host (the Lore space) saves.
@MainActor public final class LoreEditorController: NSObject, NSTextViewDelegate {
    public let scrollView: NSScrollView
    let textView: LoreTextView
    let titles: LoreNoteTitles
    let uploader: LoreAttachmentUploader
    private var map = LoreSourceMap()
    /// Bumped by every `load`: an upload that finishes after the note changed is dropped, never put in the other note.
    private(set) var generation = 0
    /// After every edit (debounce and save in the host).
    public var onChange: (() -> Void)?
    /// A `[[Title]]` link was clicked.
    public var onOpenNote: ((String) -> Void)?
    /// A `lore:` or `lore-attachment:` link was clicked.
    public var onOpenInternal: ((URL) -> Void)?
    /// One short line for the person (a toast): a link that was copied instead of opened, an upload that failed.
    public var onNotice: ((String) -> Void)?
    /// The caret moved into (true) or out of (false) a table.
    public var onTable: ((Bool) -> Void)?
    /// The outline heading the reader is at (the inspector lights it).
    public let spy = LoreHeadingSpy()

    public init(titles: LoreNoteTitles = LoreStubTitles(), uploader: LoreAttachmentUploader = LoreNoUploads()) {
        self.titles = titles
        self.uploader = uploader
        textView = LoreTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        textView.setUp()
        scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        super.init()
        textView.controller = self
        textView.delegate = self
        watchScroll()
    }

    /// Replaces the page with a note. Clears undo: the loaded text is the new starting point. `fade`: another note is
    /// opening, so the page crossfades.
    public func load(markdown: String, fade: Bool = false) {
        if fade { crossfade() }
        textView.closePicker()
        textView.tools.closeAll()
        generation += 1
        let (text, map) = MarkdownReader.parse(markdown)
        self.map = map
        textView.ts.setAttributedString(text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = Style.typing(textView.ts.length > 0 ? Block.at(textView.ts, 0) : .p)
        textView.undoManager?.removeAllActions()
        textView.scroll(.zero)
        spy.starts = nil
        updateSpy()
        textView.tools.updateGutter()
    }

    /// Lore's own text size factor; the page is drawn again at the new size (the text and the cursor stay, undo restarts).
    public func setTextScale(_ scale: CGFloat) {
        guard Typeface.userScale != scale else { return }
        Typeface.userScale = scale
        load(markdown: markdown())
    }

    /// The note as Markdown: the loaded bytes where nothing changed, fresh Markdown for edited blocks only.
    public func markdown() -> String { MarkdownWriter.markdown(textView.ts, map: map) }

    public func focus() { textView.window?.makeFirstResponder(textView) }

    /// Typing latency in ms over the last 200 keys.
    public var latency: (p50: Double, p95: Double, n: Int) { textView.latency.stats }
    public func resetLatency() { textView.latency.reset() }

    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return true }
        switch LoreLinkPolicy.action(for: url) {
        case .open: NSWorkspace.shared.open(url)
        case .host: onOpenInternal?(url)
        case .copyOnly:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            onNotice?("Link copied. Only web and mail links open from a note.")
        }
        return true  // handled: AppKit never opens it itself
    }

    /// Validates a file and sends it to the hook; on success inserts `![name](lore-attachment:…)` at `location`.
    func upload(_ file: LoreUpload, at location: Int) {
        guard LoreLinkPolicy.uploadTypes.contains(where: { file.type.conforms(to: $0) }) else {
            onNotice?("Only images and PDFs can be added to a note.")
            return
        }
        guard file.data.count <= LoreLinkPolicy.maxUpload else {
            onNotice?("\(file.name) is larger than 10 MB.")
            return
        }
        let note = generation
        Task { @MainActor in
            do {
                let url = try await uploader.upload(file)
                guard url.scheme == "lore-attachment", generation == note else { return }
                let name = file.name.filter { !"[]()\n\r\u{2028}\u{2029}".contains($0) }
                // ponytail: inserted where the drop or paste happened; text typed before it meanwhile shifts the spot.
                textView.insertMarkdown("![\(name)](\(url.absoluteString))", at: NSRange(location: location, length: 0))
            } catch {
                onNotice?("Unable to add \(file.name). Attachments need the Core.")
            }
        }
    }
}

/// The editor as a SwiftUI view. The page is unboxed: put it on the surface it belongs to.
public struct LoreEditor: NSViewRepresentable {
    let controller: LoreEditorController
    public init(_ controller: LoreEditorController) { self.controller = controller }
    public func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    public func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

// MARK: - clicks, copy, paste, drop

extension LoreTextView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty {
            if let pr = taskBoxHit(event) { return toggleTask(pr) }
            if let title = runHit(event, .loreChip) as? String, let open = controller?.onOpenNote { return open(title) }
            if let ref = runHit(event, .loreImage) as? String, let url = URL(string: ref), let controller {
                _ = controller.textView(self, clickedOnLink: url, at: 0)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Focus arriving puts the + beside an empty line (the first responder changes after this returns).
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in self?.tools.updateGutter() } }
        return ok
    }

    private func taskBoxHit(_ event: NSEvent) -> NSRange? {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let cp = CGPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        guard let frag = tlm.textLayoutFragment(for: cp), let para = frag.textElement as? NSTextParagraph,
            para.attributedString.length > 0,
            para.attributedString.attribute(.loreBlock, at: 0, effectiveRange: nil) as? String == "task",
            let first = frag.textLineFragments.first
        else { return nil }
        let style = para.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let indent = style?.headIndent ?? 0
        let ly = cp.y - frag.layoutFragmentFrame.minY
        guard cp.x > indent - 26, cp.x < indent - 2, ly < first.typographicBounds.maxY + 2 else { return nil }
        let loc = tcm.offset(from: tcm.documentRange.location, to: frag.rangeInElement.location)
        return ns.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    /// The value of `key` under the click (a note link's title, an image's address), nil off the run.
    private func runHit(_ event: NSEvent, _ key: NSAttributedString.Key) -> Any? {
        guard let window else { return nil }
        let screen = window.convertPoint(toScreen: event.locationInWindow)
        let i = characterIndex(for: screen)
        guard i < ts.length, let value = ts.attribute(key, at: i, effectiveRange: nil) else { return nil }
        let rect = firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)
        return rect.insetBy(dx: -2, dy: -2).contains(screen) ? value : nil
    }

    /// Flips `[ ]`/`[x]`: an attribute change of that paragraph only, one undo step.
    func toggleTask(_ pr: NSRange) {
        guard case .task(let l, let c) = Block.at(ts, pr.location) else { return }
        edit { setBlock(.task(l, !c), paragraph: pr, updateTyping: false) }
        animateTick(pr, checked: !c)
    }

    // Copy gives Markdown; paste and drop read plain text, Markdown, files and image data, nothing rich.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.fileURL, .string, .png, .tiff, .pdf] }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { readablePasteboardTypes }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return false }
        let sel = selectedRange()
        let sub = ts.attributedSubstring(from: sel)
        let md =
            sub.string.contains("\n")
            ? MarkdownWriter.markdown(sub)
            : MarkdownWriter.inline(ts, sel, heading: Block.at(ts, sel.location).isHeading)
        pboard.setString(md, forType: .string)
        return true
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        readPasteboard(pboard)
    }
    override func pasteAsPlainText(_ sender: Any?) { _ = readPasteboard(.general) }
    override func pasteAsRichText(_ sender: Any?) { _ = readPasteboard(.general) }

    /// Local files first (never a remote URL), then text, then raw image or PDF data.
    func readPasteboard(_ pb: NSPasteboard) -> Bool {
        let sel = selectedRange()
        let files =
            pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty {
            for url in files {
                // Type and size come from the file itself (a symlink resolved first), before a byte is read.
                let real = url.resolvingSymlinksInPath()
                let facts = try? real.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
                guard facts?.isRegularFile == true, let type = facts?.contentType,
                    LoreLinkPolicy.uploadTypes.contains(where: { type.conforms(to: $0) })
                else {
                    controller?.onNotice?("Only images and PDFs can be added to a note.")
                    continue
                }
                guard let size = facts?.fileSize, size <= LoreLinkPolicy.maxUpload,
                    let data = try? Data(contentsOf: real, options: .mappedIfSafe),
                    data.count <= LoreLinkPolicy.maxUpload
                else {
                    controller?.onNotice?("\(url.lastPathComponent) is larger than 10 MB.")
                    continue
                }
                controller?.upload(LoreUpload(name: url.lastPathComponent, type: type, data: data), at: sel.location)
            }
            return true
        }
        if let str = pb.string(forType: .string), !str.isEmpty {
            insertMarkdown(str, at: sel)
            return true
        }
        for (t, ut) in [(NSPasteboard.PasteboardType.pdf, UTType.pdf), (.png, .png), (.tiff, .tiff)] {
            guard let data = pb.data(forType: t) else { continue }
            var out = (data, ut)
            // TIFF is what screenshots put on the pasteboard; it is stored as PNG.
            if t == .tiff, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                out = (png, .png)
            }
            let name = "Pasted \(out.1 == .pdf ? "document.pdf" : "image.png")"
            controller?.upload(LoreUpload(name: name, type: out.1, data: out.0), at: sel.location)
            return true
        }
        return false
    }

    /// Inserts text as Markdown (structure kept, symbols hidden). Inside a code block it stays literal; a lone web URL
    /// becomes a link.
    func insertMarkdown(_ str: String, at sel: NSRange) {
        let b = currentBlock()
        let plain = Style.typing(b)
        let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let a: NSAttributedString
        if b == .code {
            a = NSAttributedString(string: str.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: plain)
        } else if let url = URL(string: t), ["http", "https"].contains(url.scheme ?? ""), !t.contains(" ") {
            a = NSAttributedString(string: t, attributes: plain.merging([.link: url]) { $1 })
        } else if str.contains("\n") {
            a = MarkdownReader.parse(str, trailingNewline: false).0
        } else {
            a = MarkdownReader.inline(str, plain)
        }
        let r = NSRange(
            location: min(sel.location, ts.length), length: min(sel.length, ts.length - min(sel.location, ts.length)))
        let pasted = NSMutableAttributedString(attributedString: a)
        // Pasted text is new text: it never claims an original source block.
        pasted.removeAttribute(.loreSeq, range: NSRange(location: 0, length: pasted.length))
        edit {
            replace(r, with: pasted)
            restyle(NSRange(location: r.location, length: pasted.length))
        }
        setSelectedRange(NSRange(location: r.location + pasted.length, length: 0))
        typingAttributes = Style.typing(currentBlock())
    }
}
