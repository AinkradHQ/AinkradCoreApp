// NoteHTML — Apple Notes HTML to Markdown, on this Mac (plan R4-03, T13). Copied from the old AinkradLore importer
// (`HTMLToMarkdown.swift`), then hardened.
//
// Security model. Note HTML is untrusted text, and this file only READS it: a hand-written tokenizer (no WebKit, no
// NSAttributedString HTML import, nothing is evaluated or opened). Output is plain Markdown text.
// - `script`, `style`, `iframe`, `noscript`, `object`, `embed` and `template` keep none of their content.
// - A link survives only with an `https`, `http` or `mailto` address; any other (`javascript:`, `data:`, `file:`) leaves
//   the link text and drops the link. Images are never kept from the HTML (no remote fetch, no tracking pixel): the
//   note's attachments are sent as files and linked by the exporter.
// - Input over `maxInput` is refused before it is read; warnings are capped, so a hostile note cannot flood the review.
// - Nothing is logged: note text is private.
import Foundation

enum NoteHTML {
    /// The most HTML one note may hold (T13).
    static let maxInput = 5 << 20
    static let maxWarnings = 20
    static let maxIndent = 8

    static let known: Set<String> = [
        "p", "br", "div", "span", "b", "strong", "i", "em", "u", "s", "strike", "del",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "a", "blockquote",
        "table", "tr", "td", "th", "img", "input", "code", "pre", "body", "html", "font",
    ]

    /// Markdown for `html`, and what it could not represent (tag names only, never text). Nil when over `maxInput`.
    static func convert(_ html: String) -> (markdown: String, warnings: [String])? {
        guard html.utf8.count <= maxInput else { return nil }
        var warned = Set<String>()
        var out = ""
        var listDepth = 0
        var hrefStack: [String?] = []

        for token in Tokenizer(html) {
            switch token {
            case .text(let raw):
                out += decodeEntities(raw)
            case .open(let name, let attributes):
                if !known.contains(name) {
                    if warned.count < maxWarnings { warned.insert(name) }
                    continue
                }
                switch name {
                case "b", "strong": out += "**"
                case "i", "em": out += "*"
                case "s", "strike", "del": out += "~~"
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    out += "\n" + String(repeating: "#", count: Int(name.dropFirst()) ?? 1) + " "
                case "ul", "ol": listDepth += 1
                case "li":
                    out += "\n" + String(repeating: "  ", count: min(max(listDepth - 1, 0), maxIndent)) + "- "
                case "input" where attributes["type"] == "checkbox":
                    out += attributes["checked"] == nil ? "[ ] " : "[x] "
                case "br", "p", "div": out += "\n"
                case "blockquote": out += "\n> "
                case "a":
                    let href = safeLink(attributes["href"])
                    hrefStack.append(href)
                    if href != nil { out += "[" }
                default: break
                }
            case .close(let name):
                switch name {
                case "b", "strong": out += "**"
                case "i", "em": out += "*"
                case "s", "strike", "del": out += "~~"
                case "ul", "ol":
                    listDepth = max(listDepth - 1, 0)
                    out += "\n"
                case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6": out += "\n"
                case "a":
                    // An unmatched </a> with no prior <a> is a no-op, not a stray "]()".
                    if let href = hrefStack.popLast(), let href { out += "](\(href))" }
                default: break
                }
            }
        }
        let squeezed = out.replacing(/\n{3,}/, with: "\n\n")
        return (
            squeezed.trimmingCharacters(in: .whitespacesAndNewlines),
            warned.sorted().map { "<\($0)> not converted" }
        )
    }

    /// The address when its scheme is `https`, `http` or `mailto`, with the characters that would end the Markdown
    /// link escaped; nil for anything else (no scheme included: a relative link has nowhere to go).
    static func safeLink(_ raw: String?) -> String? {
        guard let raw else { return nil }
        // Browsers ignore tabs, newlines and spaces inside a scheme (`java\nscript:`), so the check does too.
        let flat = raw.unicodeScalars.filter { !$0.properties.isWhitespace && $0.value > 0x1F }
        let s = String(String.UnicodeScalarView(flat))
        let lower = s.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") else {
            return nil
        }
        return s.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }
}

/// Decodes the HTML entities Apple Notes actually emits: the common named entities plus
/// decimal (`&#39;`) and hex (`&#x2019;`) numeric entities.
private func decodeEntities(_ string: String) -> String {
    guard string.contains("&") else { return string }

    let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    let chars = Array(string)
    var result = ""
    result.reserveCapacity(chars.count)
    var i = 0

    while i < chars.count {
        guard chars[i] == "&" else {
            result.append(chars[i])
            i += 1
            continue
        }

        guard let semicolonOffset = chars[(i + 1)...].prefix(24).firstIndex(of: ";") else {
            result.append(chars[i])
            i += 1
            continue
        }
        let entity = String(chars[(i + 1)..<semicolonOffset])

        if let decoded = decodeNumericEntity(entity) ?? named[entity.lowercased()] {
            result += decoded
            i = semicolonOffset + 1
        } else {
            result.append(chars[i])
            i += 1
        }
    }
    return result
}

private func decodeNumericEntity(_ entity: String) -> String? {
    guard entity.hasPrefix("#") else { return nil }
    let digits = entity.dropFirst()
    let code: UInt32?
    if digits.hasPrefix("x") || digits.hasPrefix("X") {
        code = UInt32(digits.dropFirst(), radix: 16)
    } else {
        code = UInt32(digits)
    }
    guard let value = code, let scalar = Unicode.Scalar(value) else { return nil }
    return String(Character(scalar))
}

/// A minimal streaming tokenizer over the small HTML subset Apple Notes readers emit.
/// Tag and attribute names are lowercased; attribute values may be single-quoted,
/// double-quoted, or bare; self-closing tags (`<br/>`, `<img .../>`) emit `.open` only.
struct Tokenizer: Sequence {
    enum Token: Equatable {
        case text(String)
        case open(name: String, attributes: [String: String])
        case close(name: String)
    }

    private let chars: [Character]

    init(_ html: String) {
        self.chars = Array(html)
    }

    func makeIterator() -> TokenizerIterator {
        TokenizerIterator(chars: chars)
    }
}

/// Elements whose content is raw text per the HTML spec — it must never be interpreted
/// as markup or copied into the markdown output, only scanned for the matching close tag.
private let rawTextElements: Set<String> = [
    "script", "style", "iframe", "noscript", "object", "embed", "template",
]

struct TokenizerIterator: IteratorProtocol {
    private let chars: [Character]
    private var i = 0
    private var pendingRawSkip: String?

    init(chars: [Character]) {
        self.chars = chars
    }

    mutating func next() -> Tokenizer.Token? {
        if let rawName = pendingRawSkip {
            pendingRawSkip = nil
            skipRawTextContent(of: rawName)
            return .close(name: rawName)
        }
        guard i < chars.count else { return nil }
        if chars[i] == "<" {
            return parseTag()
        }
        var text = ""
        while i < chars.count && chars[i] != "<" {
            text.append(chars[i])
            i += 1
        }
        return .text(text)
    }

    private mutating func parseTag() -> Tokenizer.Token? {
        i += 1  // consume '<'

        if i < chars.count, chars[i] == "!", i + 1 < chars.count,
            chars[i + 1] == "-", i + 2 < chars.count, chars[i + 2] == "-"
        {
            i += 3  // consume '!--'
            skipUntilAndConsume("-->")
            return next()
        }

        if i < chars.count, chars[i] == "!" || chars[i] == "?" {
            skipUntilAndConsume(">")
            return next()
        }

        var closing = false
        if i < chars.count, chars[i] == "/" {
            closing = true
            i += 1
        }

        let name = readName().lowercased()
        if name.isEmpty {
            skipUntilAndConsume(">")
            return next()
        }

        if closing {
            skipUntilAndConsume(">")
            return .close(name: name)
        }

        let attributes = readAttributes()
        skipUntilAndConsume(">")
        if rawTextElements.contains(name) {
            pendingRawSkip = name
        }
        return .open(name: name, attributes: attributes)
    }

    /// Advances past a raw-text element's content up to (and consuming) its closing tag,
    /// e.g. `</script>`. If no closing tag is found, consumes to end of input.
    private mutating func skipRawTextContent(of name: String) {
        let closeTag = Array("</\(name)".lowercased())
        while i < chars.count {
            if chars[i] == "<", matches(closeTag, at: i) {
                i += closeTag.count
                skipUntilAndConsume(">")
                return
            }
            i += 1
        }
    }

    private func matches(_ pattern: [Character], at start: Int) -> Bool {
        guard start + pattern.count <= chars.count else { return false }
        for offset in 0..<pattern.count {
            if chars[start + offset].lowercased() != String(pattern[offset]) { return false }
        }
        return true
    }

    private mutating func readName() -> String {
        var name = ""
        while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "-" {
            name.append(chars[i])
            i += 1
        }
        return name
    }

    private mutating func readAttributes() -> [String: String] {
        var attributes: [String: String] = [:]
        while i < chars.count, chars[i] != ">" {
            skipWhitespace()
            guard i < chars.count, chars[i] != ">" else { break }
            if chars[i] == "/" {
                i += 1
                continue
            }

            let attrName = readAttributeName().lowercased()
            if attrName.isEmpty {
                // Unrecognized character in tag body; skip it to guarantee progress.
                i += 1
                continue
            }
            skipWhitespace()

            if i < chars.count, chars[i] == "=" {
                i += 1
                skipWhitespace()
                attributes[attrName] = readAttributeValue()
            } else {
                attributes[attrName] = ""
            }
        }
        return attributes
    }

    private mutating func readAttributeName() -> String {
        var name = ""
        while i < chars.count, chars[i] != "=", chars[i] != ">", chars[i] != "/",
            !chars[i].isWhitespace
        {
            name.append(chars[i])
            i += 1
        }
        return name
    }

    private mutating func readAttributeValue() -> String {
        guard i < chars.count else { return "" }
        if chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]
            i += 1
            var value = ""
            while i < chars.count, chars[i] != quote {
                value.append(chars[i])
                i += 1
            }
            if i < chars.count { i += 1 }  // consume closing quote
            return value
        }
        var value = ""
        while i < chars.count, !chars[i].isWhitespace, chars[i] != ">" {
            value.append(chars[i])
            i += 1
        }
        return value
    }

    private mutating func skipWhitespace() {
        while i < chars.count, chars[i].isWhitespace { i += 1 }
    }

    private mutating func skipUntilAndConsume(_ target: Character) {
        while i < chars.count, chars[i] != target { i += 1 }
        if i < chars.count { i += 1 }
    }

    /// Skips forward until the literal `target` sequence is found and consumes it too
    /// (e.g. `"-->"` for HTML comments). If never found, consumes to end of input.
    private mutating func skipUntilAndConsume(_ target: String) {
        let pattern = Array(target)
        while i < chars.count {
            if matches(pattern, at: i) {
                i += pattern.count
                return
            }
            i += 1
        }
    }
}
