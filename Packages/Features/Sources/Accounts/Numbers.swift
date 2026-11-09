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

    /// A dollar amount typed with the locale's decimal mark or a point: `2.50`, `2,50`.
    static func parseDecimal(_ text: String) -> Double? {
        let t = text.filter { !"$ \u{00A0}_".contains($0) }
        if let d = try? Double(t, format: .number) { return d }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }
}
