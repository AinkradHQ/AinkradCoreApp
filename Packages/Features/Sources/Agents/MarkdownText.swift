import AppKit
import CoreUI
import SwiftUI

/// One block of an agent's answer. A small parser, not a full Markdown engine: paragraphs, headings (shown as bold lines),
/// bullet and numbered items, and fenced code. Inline styles (bold, italics, `code`, links) are `AttributedString`'s.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case item(marker: String, text: String)
    case code(language: String, text: String)
    case table(header: [String], rows: [[String]])
    case quote(String)
    case rule
    /// `![alt](src)` on a line of its own: a local file this Mac can read, or an https address.
    case image(alt: String, src: String)

    static func cells(_ line: String) -> [String] { GFMTable.cells(line) }

    /// `![alt](src)` alone on a line.
    static func image(_ line: String) -> MarkdownBlock? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("!["), t.hasSuffix(")"), let mid = t.range(of: "](") else { return nil }
        let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound])
        let src = String(t[mid.upperBound..<t.index(before: t.endIndex)])
        return src.isEmpty ? nil : .image(alt: alt, src: src)
    }

    static func isSeparator(_ line: String) -> Bool { GFMTable.isSeparator(line) }

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (language: String, lines: [String])?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        let rawLines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var skip = 0
        for (n, raw) in rawLines.enumerated() {
            if skip > 0 {
                skip -= 1
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var f = fence {
                if line.hasPrefix("```") {
                    blocks.append(.code(language: f.language, text: f.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    f.lines.append(raw)
                    fence = f
                }
            } else if line.hasPrefix("```") {
                flush()
                fence = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if let count = GFMTable.extent(rawLines, at: n) {
                flush()
                blocks.append(
                    .table(header: cells(line), rows: rawLines[(n + 2)..<(n + count)].map { cells($0) }))
                skip = count - 1
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.drop(while: { $0 == ">" })).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else if line.isEmpty {
                flush()
            } else if let img = image(line) {
                flush()
                blocks.append(img)
            } else if line.hasPrefix("#"), let h = line.drop(while: { $0 == "#" }).first, h == " " {
                flush()
                blocks.append(.heading(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
            } else if let item = listItem(line) {
                flush()
                blocks.append(item)
            } else {
                paragraph.append(line)
            }
        }
        // An unclosed fence (the answer is still streaming) shows what it has as code.
        if let f = fence { blocks.append(.code(language: f.language, text: f.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            return .item(marker: "•", text: String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 4, line.dropFirst(digits.count).hasPrefix(". ") {
            return .item(marker: "\(digits).", text: String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    /// Inline styles as an `AttributedString`. Only http(s) links stay links; nothing is ever run as HTML.
    static func inline(_ text: String) -> AttributedString {
        var out =
            (try? AttributedString(
                markdown: text,
                options: .init(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
            )) ?? AttributedString(text)
        for run in out.runs {
            if let url = run.link, !["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                out[run.range].link = nil
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                out[run.range].font = .system(size: MacTextSize.body - 1, design: .monospaced)
                out[run.range].backgroundColor = GlassInk.wellHover
            }
        }
        return out
    }
}

/// The agent's answer, formatted.
struct MarkdownText: View {
    let source: String
    private let blocks: [MarkdownBlock]
    /// True while this answer is still being written: a soft caret ends its last paragraph (static under Reduce Motion).
    var streaming = false

    init(_ source: String, streaming: Bool = false) {
        self.source = source
        self.streaming = streaming
        blocks = MarkdownBlock.parse(source)
    }

    /// The words of a paragraph, for finding the file a code block after it is about.
    private static func words(_ b: MarkdownBlock) -> String? {
        if case .paragraph(let t) = b { return t }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let t):
                    if streaming && index == blocks.count - 1 {
                        CaretParagraph(text: MarkdownBlock.inline(t))
                    } else {
                        Text(MarkdownBlock.inline(t)).lineSpacing(6).textSelection(.enabled)
                    }
                case .heading(let t):
                    // A report's headings read as headings: one step up from the body.
                    // 16 pt above a heading (8 from the stack + 8), so a section starts clearly (review 2026-11-16).
                    Text(MarkdownBlock.inline(t)).coreFont(size: MacTextSize.title, weight: .semibold)
                        .padding(.top, Space.s2).textSelection(.enabled)
                case .item(let marker, let t):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        // One 20 pt marker column for bullets and numbers alike, numbers right-aligned in it. A bullet is a
                        // small rounded square (the mockup's), not a dot character.
                        Group {
                            if marker == "•" {
                                coreShape(1.5).fill(SessionInk.text2).frame(width: 5, height: 5).offset(y: -1)
                            } else {
                                Text(marker).foregroundStyle(SessionInk.text2).monospacedDigit()
                            }
                        }
                        .frame(width: 20, alignment: .trailing)
                        Text(MarkdownBlock.inline(t)).lineSpacing(6).textSelection(.enabled)
                    }
                case .code(let lang, let t):
                    CodeBlock(text: t, language: lang, before: index > 0 ? Self.words(blocks[index - 1]) : nil)
                case .table(let header, let rows):
                    MarkdownTable(header: header, rows: rows)
                case .quote(let t):
                    // A quote is a quiet well, not a coloured bar (no lines on this screen).
                    Text(MarkdownBlock.inline(t)).foregroundStyle(SessionInk.text2).textSelection(.enabled)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SessionInk.card, in: coreShape(Radius.control))
                case .rule:
                    // A rule is space, not a line.
                    Color.clear.frame(height: Space.s4)
                case .image(let alt, let src):
                    MarkdownImage(alt: alt, src: src)
                }
            }
        }
        // Conversation prose: body size, which the app's text scale shows at about 15 pt, with chat-app line spacing.
        .coreFont(size: MacTextSize.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A code block as a card (the mockup's): a header with the language, Wrap, Copy and Apply. Apply writes the block to the file
/// named in the fence or the sentence before it; a block that names none asks which of the session's files.
private struct CodeBlock: View {
    let text: String
    /// The fence's whole info string (```swift Sources/A.swift).
    var language = ""
    var before: String?
    @Environment(\.applyCode) private var apply
    @State private var copied = false
    @State private var wrap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s1) {
                let target = CodeTarget.path(info: language, before: before)
                Text(language.split(separator: " ").first.map { String($0).components(separatedBy: ":")[0] } ?? "code")
                    .coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(SessionInk.text2)
                if let target {
                    Text(target).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(SessionInk.text2)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: Space.s2)
                if let apply {
                    if let target {
                        CoreIconButton(symbol: "square.and.arrow.down", label: "Apply to \(target)") {
                            apply.write(target, text)
                        }
                        .help("Write this to \(target)")
                    } else if !apply.files.isEmpty {
                        Menu {
                            ForEach(apply.files, id: \.self) { f in Button(f) { apply.write(f, text) } }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .menuStyle(.borderlessButton).fixedSize().help("Apply to a file: pick which")
                    }
                }
                CoreIconButton(symbol: "text.alignleft", label: wrap ? "Do not wrap lines" : "Wrap lines") {
                    wrap.toggle()
                }
                .help(wrap ? "Scroll long lines" : "Wrap long lines")
                CoreIconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy the code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .help("Copy the code")
            }
            .padding(.leading, Space.s3).padding(.trailing, Space.s1).frame(height: MacSize.controlLg)
            let code = Text(SyntaxHighlight.attributed(text))
                .font(.system(size: MacTextSize.body - 1, design: .monospaced)).textSelection(.enabled)
            if wrap {
                code.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .bottom], Space.s3)
            } else {
                ScrollView(.horizontal) { code.fixedSize().padding([.horizontal, .bottom], Space.s3) }
                    .scrollIndicators(.never)
            }
        }
        .background(SessionInk.code, in: coreShape(Radius.row))
    }
}

/// A Markdown table: header row in bold, cells aligned in columns, scrolls sideways when it does not fit.
private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                        Text(MarkdownBlock.inline(h)).fontWeight(.semibold)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        ForEach(Array(r.enumerated()), id: \.offset) { _, c in Text(MarkdownBlock.inline(c)) }
                    }
                }
            }
            .textSelection(.enabled).padding(Space.s3)
        }
        .background(SessionInk.code, in: coreShape(Radius.row))
    }
}

/// An image in an answer: a local file this Mac can read, or an https address (plain http is not fetched). It keeps its
/// shape up to the reading width; what cannot load shows its words and address instead.
private struct MarkdownImage: View {
    let alt: String
    let src: String

    var body: some View {
        Group {
            if let url = URL(string: src), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        picture(image)
                    } else if phase.error != nil {
                        fallback
                    } else {
                        CoreSkeleton(coreShape(Radius.cardMac)).frame(width: Space.s8 * 8, height: Space.s8 * 5)
                    }
                }
            } else if let img = NSImage(
                contentsOf: URL(fileURLWithPath: src.hasPrefix("file://") ? String(src.dropFirst(7)) : src))
            {
                picture(Image(nsImage: img))
            } else {
                fallback
            }
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    private func picture(_ image: Image) -> some View {
        image.resizable().scaledToFit().frame(maxWidth: Space.s8 * 18, maxHeight: Space.s8 * 12, alignment: .leading)
            .clipShape(coreShape(Radius.cardMac)).help(alt.isEmpty ? src : alt)
    }

    private var fallback: some View {
        CoreChip(alt.isEmpty ? src : alt, symbol: "photo", minWidth: 0).help(src)
    }
}


/// The last paragraph of an answer that is still being written: its text and a calm caret that breathes between faint and full
/// about every 0.6 s. Reduce Motion: the caret stays, still and full.
private struct CaretParagraph: View {
    let text: AttributedString
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if reduce {
            paragraph(on: true)
        } else {
            TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
                paragraph(on: Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0)
                    .animation(Motion.out(0.3), value: Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2)
            }
        }
    }

    private func paragraph(on: Bool) -> some View {
        var caret = AttributedString(" \u{258D}")
        caret.foregroundColor = GlassInk.blue.opacity(on ? 1 : 0.25)
        return Text(text + caret).lineSpacing(6).textSelection(.enabled)
    }
}
