import Foundation

/// Sibling order (T1 `ids.rs`): lowercase base-36 strings, 1...32 long, never ending in `0`, so a midpoint always exists. A
/// port of the Core's `between` and `rebalance`, because a layer drag writes `move` ops with the order it chose.
enum FractionalOrder {
    static let maxLength = 32

    static func isOrder(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= maxLength
            && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 122) }
            && !s.hasSuffix("0")
    }

    private static func digit(_ b: UInt8) -> Int { b <= 57 ? Int(b) - 48 : Int(b) - 97 + 10 }
    private static func char(_ d: Int) -> Character { Character(String(d, radix: 36)) }

    /// A valid order strictly between `lo` and `hi` (nil = open end), or nil when the arguments are not valid orders with
    /// `lo < hi`, or the result would be too long (the caller rebalances the siblings).
    static func between(_ lo: String?, _ hi: String?) -> String? {
        let l = lo ?? ""
        if (lo != nil && !isOrder(l)) || (hi != nil && !isOrder(hi!)) { return nil }
        if let h = hi, !l.utf8.lexicographicallyPrecedes(h.utf8) { return nil }
        let a = Array(l.utf8)
        let b = hi.map { Array($0.utf8) }
        var out = ""
        var i = 0
        var hiOpen = b == nil
        while true {
            if out.utf8.count >= maxLength { return nil }
            let da = i < a.count ? digit(a[i]) : 0
            let db = hiOpen ? 36 : (b.flatMap { i < $0.count ? digit($0[i]) : nil } ?? 36)
            if db - da >= 2 {
                out.append(char((da + db) / 2))
                return out
            }
            out.append(char(da))
            if da < db { hiOpen = true }
            i += 1
        }
    }

    /// `n` evenly spaced valid orders in increasing order, for renumbering siblings after `between` ran out of room.
    static func rebalance(_ n: Int) -> [String]? {
        guard n >= 0, n <= 20_000 else { return nil }
        let slots = UInt64(n + 1) * 4
        var width = 1
        var cap: UInt64 = 36
        while cap < slots {
            width += 1
            cap *= 36
        }
        let step = cap / UInt64(n + 1)
        return (0..<n).map { k in
            var v = UInt64(k + 1) * step
            if v % 36 == 0 { v += 1 }
            var digits = [Int](repeating: 0, count: width)
            for j in stride(from: width - 1, through: 0, by: -1) {
                digits[j] = Int(v % 36)
                v /= 36
            }
            return String(digits.map(char))
        }
    }
}
