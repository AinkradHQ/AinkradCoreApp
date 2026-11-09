import CoreUI
import Foundation

/// Numbers the way the person's Mac writes them: grouped digits in fields, "2 million tokens" in sentences, the locale's
/// own decimal mark and currency. Fields parse what they print.
enum AccountsNumbers {
    /// `80,000,000` (the locale's grouping).
    static func grouped(_ n: Int64) -> String { n.formatted(.number.grouping(.automatic)) }

    /// `2 million`, `1.5 billion`, `328,000`: whole thousands stay as digits, millions and up become words.
    static func amount(_ n: Int64) -> String {
        let (div, word): (Double, String?) =
            abs(n) >= 1_000_000_000 ? (1e9, "billion") : abs(n) >= 1_000_000 ? (1e6, "million") : (1, nil)
        guard let word else { return grouped(n) }
        let v = (Double(n) / div).formatted(.number.precision(.fractionLength(0...1)))
        return "\(v)\u{00A0}\(word)"
    }

    /// `2 million tokens`, with a no-break space before the unit.
    static func tokens(_ n: Int64) -> String {
        let a = amount(n)
        return a.contains("\u{00A0}") ? "\(a) tokens" : coreUnit(a, n == 1 ? "token" : "tokens")
    }

    static func usd(_ micros: Int64) -> String { (Double(micros) / 1_000_000).formatted(.currency(code: "USD")) }

    /// A dollar amount for a field: two decimals in the locale's mark, no grouping, no symbol.
    static func dollarsField(_ micros: Int64) -> String {
        (Double(micros) / 1_000_000).formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    /// A whole number typed with any grouping: `80,000,000`, `80 000 000`, `80_000_000`.
    static func parseWhole(_ text: String) -> Int64? {
        let drop = Set(",_ \u{00A0}\u{202F}'").union(Locale.current.groupingSeparator.map(Set.init) ?? [])
        return Int64(text.filter { !drop.contains($0) })
    }

    /// A dollar amount typed with the locale's decimal mark, or the other form when it is unambiguous: `2.50`, `2,50`, `1,234.50`.
    /// One mark alone is the decimal mark if it is the locale's; the other mark alone is a decimal mark unless three digits
    /// follow it (`2.500` in German is 2500). Grouping must be groups of three, and nothing may follow a decimal mark but digits.
    static func parseDecimal(_ text: String, locale: Locale = .current) -> Double? {
        let t = text.filter { !"$ \u{00A0}\u{202F}_".contains($0) }
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let localeDecimal: Character = locale.decimalSeparator?.first ?? "."
        let marks = t.filter { $0 == "." || $0 == "," }
        func grouped(_ s: Substring, by mark: Character) -> String? {
            let parts = s.split(separator: mark, omittingEmptySubsequences: false)
            guard let first = parts.first, (1...3).contains(first.count) || parts.count == 1,
                parts.dropFirst().allSatisfy({ $0.count == 3 })
            else { return nil }
            return parts.joined()
        }
        func make(_ whole: String?, _ frac: Substring) -> Double? {
            guard let whole, !(whole.isEmpty && frac.isEmpty), frac.allSatisfy(\.isNumber) else { return nil }
            return Double("\(whole.isEmpty ? "0" : whole).\(frac.isEmpty ? "0" : String(frac))")
        }
        guard let last = marks.last else { return Double(t) }
        let at = t.lastIndex(of: last)!
        let head = t[..<at]
        let tail = t[t.index(after: at)...]
        let other: Character = last == "." ? "," : "."
        if marks.allSatisfy({ $0 == last }) && marks.count > 1 {
            // The same mark more than once can only be grouping, and the locale's decimal mark never is.
            return last == localeDecimal ? nil : Double(grouped(t[...], by: last) ?? "")
        }
        if marks.count == 1 && last != localeDecimal && tail.count == 3 {
            return Double(grouped(t[...], by: last) ?? "")  // `2.500` in German: grouping, 2500
        }
        return make(grouped(head, by: other), tail)
    }
}
