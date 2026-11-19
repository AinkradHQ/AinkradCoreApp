import Foundation

/// GitHub-flavoured Markdown tables, shared by the Lore editor and the agent answer view: one detector, so both read
/// the same text as the same table.
public enum GFMTable {
    public enum Align: Equatable, Sendable { case leading, center, trailing }

    /// Cells of a row; edge pipes optional, `\|` stays inside a cell.
    public static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var out: [String] = []
        var cur = ""
        var escaped = false
        for ch in t {
            if escaped {
                cur.append(ch)
                escaped = false
            } else if ch == "\\" {
                cur.append(ch)
                escaped = true
            } else if ch == "|" {
                out.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// A separator row: `|? *:?-+:? *(| *:?-+:? *)*|?`, every cell dashes with optional edge colons.
    public static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        let c = cells(t)
        return c.allSatisfy {
            !$0.isEmpty && $0.contains("-")
                && $0.dropFirst($0.hasPrefix(":") ? 1 : 0)
                    .dropLast($0.hasSuffix(":") ? 1 : 0).allSatisfy { $0 == "-" }
        }
    }

    public static func alignments(_ separator: String) -> [Align] {
        cells(separator).map { c in
            switch (c.hasPrefix(":"), c.hasSuffix(":")) {
            case (true, true): .center
            case (false, true): .trailing
            default: .leading
            }
        }
    }

    /// A table starts at `lines[i]` when it holds a pipe and the next line is a separator with the same cell count.
    /// Returns the number of lines it covers (header, separator, then rows up to a blank or pipe-less line), or nil.
    public static func extent(_ lines: [String], at i: Int) -> Int? {
        guard i + 1 < lines.count, lines[i].contains("|"), isSeparator(lines[i + 1]),
            cells(lines[i]).count == cells(lines[i + 1]).count
        else { return nil }
        var e = i + 2
        while e < lines.count {
            let t = lines[e].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || !t.contains("|") { break }
            e += 1
        }
        return e - i
    }
}
