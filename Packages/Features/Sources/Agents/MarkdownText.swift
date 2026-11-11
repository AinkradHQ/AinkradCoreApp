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

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (language: String, lines: [String])?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
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
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
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
                case .code(_, let t):
                    CodeBlock(text: t)
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
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal) {
                Text(text).font(.system(size: MacTextSize.body - 1, design: .monospaced)).textSelection(.enabled)
                    .fixedSize().padding(Space.s3).padding(.trailing, Space.s6)
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
