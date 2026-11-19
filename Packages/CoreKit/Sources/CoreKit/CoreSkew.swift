import Foundation

/// E12-5, the version-skew rule: this app refuses to talk to a Core older than `minCore` and says so in plain words. The Core
/// reports the oldest app and runner it works with (`GET /core/health` `min_app`, `min_runner`), so the rule is two-sided.
public enum CoreSkew {
    /// The oldest Core this app works with: the first one that has the routes this app calls (`serverSupports`).
    public static let minCore = "0.10.0"

    /// `a.b.c` as numbers, a suffix ignored; nil when it is not one.
    static func numbers(_ v: String) -> [Int]? {
        let parts = v.split(whereSeparator: { "-+".contains($0) }).first?.split(separator: ".").map { Int($0) }
        guard let p = parts, p.count == 3, !p.contains(nil) else { return nil }
        return p.compactMap { $0 }
    }

    /// True only when both versions parse and the Core is older. An unknown version (a development build) is not blocked.
    public static func tooOld(_ server: String?, min: String = minCore) -> Bool {
        guard let s = server.flatMap(numbers), let m = numbers(min) else { return false }
        return s.lexicographicallyPrecedes(m)
    }

    public static func message(core: String, min: String = minCore) -> String {
        "Your Core is on \(core). This version of Ainkrad needs Core \(min) or newer. Update the Core (it can update itself at night once it is on \(min)), or run the installer again, then open Ainkrad."
    }
}
