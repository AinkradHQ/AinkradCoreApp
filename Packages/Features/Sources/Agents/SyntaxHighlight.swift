import CoreUI
import SwiftUI

/// A small highlighter for the code blocks of an answer: comments, strings, numbers and the keywords most languages share. Not
/// a parser; an unknown language still gets comments, strings and numbers. ponytail: per-language grammars if this falls short.
enum SyntaxHighlight {
    static let keywords: Set<String> = [
        "func", "fn", "let", "var", "const", "struct", "class", "enum", "protocol", "impl", "trait", "pub", "use",
        "mod", "import",
        "from", "export", "return", "if", "else", "for", "while", "loop", "match", "switch", "case", "default", "guard",
        "in",
        "async", "await", "try", "catch", "throw", "throws", "def", "self", "Self", "this", "new", "static", "final",
        "extension",
        "where", "true", "false", "nil", "null", "None", "True", "False", "mut", "ref", "type", "interface", "package",
        "go",
        "defer", "yield", "with", "as", "is", "not", "and", "or", "public", "private", "internal", "override", "init",
    ]

    enum Token: Equatable { case plain, keyword, string, number, comment }

    /// Splits one line into runs, so the result is easy to test.
    static func tokens(_ line: String) -> [(String, Token)] {
        var out: [(String, Token)] = []
        let c = Array(line)
        var i = 0
        func push(_ s: String, _ t: Token) {
            if let last = out.last, last.1 == t, t == .plain { out[out.count - 1].0 += s } else { out.append((s, t)) }
        }
        while i < c.count {
            let ch = c[i]
            if ch == "#" || (ch == "/" && i + 1 < c.count && c[i + 1] == "/")
                || (ch == "-" && i + 1 < c.count && c[i + 1] == "-" && i == 0)
            {
                push(String(c[i...]), .comment)
                break
            }
            if ch == "\"" || ch == "'" || ch == "`" {
                var j = i + 1
                while j < c.count, c[j] != ch { j += c[j] == "\\" ? 2 : 1 }
                j = min(j + 1, c.count)
                push(String(c[i..<j]), .string)
                i = j
            } else if ch.isNumber {
                var j = i
                while j < c.count, c[j].isNumber || c[j] == "." || c[j] == "_" { j += 1 }
                push(String(c[i..<j]), .number)
                i = j
            } else if ch.isLetter || ch == "_" {
                var j = i
                while j < c.count, c[j].isLetter || c[j].isNumber || c[j] == "_" { j += 1 }
                let w = String(c[i..<j])
                push(w, keywords.contains(w) ? .keyword : .plain)
                i = j
            } else {
                push(String(ch), .plain)
                i += 1
            }
        }
        return out
    }

    static func attributed(_ code: String) -> AttributedString {
        var out = AttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        for (n, line) in lines.enumerated() {
            for (text, t) in tokens(String(line)) {
                var a = AttributedString(text)
                switch t {
                case .keyword: a.foregroundColor = GlassInk.violet
                case .string: a.foregroundColor = GlassInk.green
                case .number: a.foregroundColor = GlassInk.orangeInk
                case .comment: a.foregroundColor = GlassInk.secondary
                case .plain: break
                }
                out += a
            }
            if n < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }
}
