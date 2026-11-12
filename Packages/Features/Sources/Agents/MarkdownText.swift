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

    /// Cells of a `| a | b |` line.
    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isSeparator(_ line: String) -> Bool {
        let c = cells(line)
        return !c.isEmpty && c.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } && $0.contains("-") }
    }

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
            } else if line.hasPrefix("|"), n + 1 < rawLines.count, isSeparator(rawLines[n + 1]) {
                flush()
                var rows: [[String]] = []
                var k = n + 2
                while k < rawLines.count, rawLines[k].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(rawLines[k]))
                    k += 1
                }
                blocks.append(.table(header: cells(line), rows: rows))
                skip = k - n - 1
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.drop(while: { $0 == ">" })).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else if line.isEmpty {
                flush()
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

    init(_ source: String) {
        self.source = source
        blocks = MarkdownBlock.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let t):
                    Text(MarkdownBlock.inline(t)).lineSpacing(3).textSelection(.enabled)
                case .heading(let t):
                    Text(MarkdownBlock.inline(t)).fontWeight(.semibold).textSelection(.enabled)
                case .item(let marker, let t):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(marker).foregroundStyle(GlassInk.secondary).frame(minWidth: 16, alignment: .trailing)
                        Text(MarkdownBlock.inline(t)).lineSpacing(3).textSelection(.enabled)
                    }
                case .code(let lang, let t):
                    CodeBlock(text: t, language: lang)
                case .table(let header, let rows):
                    MarkdownTable(header: header, rows: rows)
                case .quote(let t):
                    HStack(spacing: Space.s2) {
                        coreShape(1.5).fill(GlassInk.blue.opacity(0.7)).frame(width: 3)
                        Text(MarkdownBlock.inline(t)).foregroundStyle(GlassInk.secondary).textSelection(.enabled)
                    }
                case .rule:
                    coreShape(0.5).fill(GlassInk.track).frame(height: 1)
                }
            }
        }
        .coreFont(size: MacTextSize.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Monospaced card, scrolls sideways, with Copy.
private struct CodeBlock: View {
    let text: String
    var language = ""
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal) {
                Text(SyntaxHighlight.attributed(text)).font(.system(size: MacTextSize.body - 1, design: .monospaced))
                    .textSelection(.enabled).fixedSize().padding(Space.s3).padding(
                        .top, language.isEmpty ? 0 : Space.s3
                    )
                    .padding(.trailing, Space.s6)
            }
            if !language.isEmpty {
                Text(language).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3).padding(.top, Space.s2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
            .buttonStyle(.plain).coreFont(size: MacTextSize.meta, weight: .semibold)
            .foregroundStyle(GlassInk.secondary).padding(Space.s2)
        }
        .background(GlassInk.wellHover, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
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
        .background(GlassInk.well, in: coreShape(Radius.row))
        .overlay { coreShape(Radius.row).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
    }
}
