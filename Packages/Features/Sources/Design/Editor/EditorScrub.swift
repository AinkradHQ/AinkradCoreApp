import Foundation

/// Number scrubbing and arrow steps for the inspector's fields, in the units the field shows (a percentage shows 50, not
/// 0.5). One unit per point dragged or per arrow press; Shift makes it ten.
enum Scrub {
    static func unit(shift: Bool) -> Double { shift ? 10 : 1 }

    /// The value after dragging the label `dx` points from `start`.
    static func value(start: Double, dx: Double, shift: Bool) -> Double {
        clean(start + (dx * unit(shift: shift)).rounded())
    }

    /// The value after an arrow: `up` raises it.
    static func step(_ v: Double, up: Bool, shift: Bool) -> Double {
        clean(v + (up ? 1 : -1) * unit(shift: shift))
    }

    /// Two decimals at most, so 0.1 + 0.2 never shows as 0.30000000000000004.
    private static func clean(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

/// The font choices of the Typography section: `system` (what the canvas draws with by default) and the fonts in the
/// library. The engine draws only those two: a font reaches it as a library file, by its hash (`font.asset`), never from
/// the Mac's installed fonts.
enum FontChoice {
    /// A library name as a `family` value the model accepts: letters, digits, space, `_`, `-`; 1 to 100 characters.
    static func family(_ name: String) -> String {
        var base = name
        if let dot = name.lastIndex(of: "."), name.distance(from: dot, to: name.endIndex) <= 5 {
            base = String(name[..<dot])
        }
        let ok = base.unicodeScalars.map { s -> Character in
            s.isASCII && (CharacterSet.alphanumerics.contains(s) || " _-".unicodeScalars.contains(s))
                ? Character(s) : " "
        }
        let words = String(ok).split(separator: " ").joined(separator: " ")
        return String((words.isEmpty ? "Font" : words).prefix(100))
    }

    /// The `type.font` value for a library font, or `system`.
    static func value(sha: String?, name: String = "") -> DJSON {
        guard let sha else { return .string("system") }
        return .object(["asset": .string(sha), "family": .string(family(name))])
    }

    /// The sha a `type.font` names, nil for `system` or none.
    static func sha(of font: DJSON?) -> String? { font?["asset"]?.string }
}
