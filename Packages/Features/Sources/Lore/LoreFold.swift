import Foundation

/// Folding a remote change into the open page (T3): where the cursor goes once the text under it changed elsewhere.
enum LoreFold {
    /// Maps a caret offset (UTF-16) in `old` to the same spot in `new`: after the last character before it that both texts
    /// keep. Text inserted right at the caret lands after it, so typing goes on where it was.
    static func caret(_ at: Int, from old: String, to new: String) -> Int {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        let at = min(max(at, 0), a.count)
        // The common head and tail need no diff: most remote changes are one block (an AI append).
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        if at <= head { return at }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        if at >= a.count - tail { return at + b.count - a.count }
        // ponytail: a character diff of the changed middle only; a very large middle is slow but stays correct.
        let mid = b[head..<(b.count - tail)].difference(from: a[head..<(a.count - tail)])
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for c in mid {
            switch c {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        // Kept characters pair up in order: count the ones before the caret, find that one in `new`.
        var kept = 0
        for i in 0..<(at - head) where !removed.contains(i) { kept += 1 }
        if kept == 0 { return head }
        var seen = 0
        for j in 0..<(b.count - tail - head) where !inserted.contains(j) {
            seen += 1
            if seen == kept { return head + j + 1 }
        }
        return b.count - tail
    }
}
