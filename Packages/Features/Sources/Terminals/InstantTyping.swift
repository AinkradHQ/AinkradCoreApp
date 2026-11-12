import Foundation

/// Settings, Terminal, "Instant typing".
enum InstantTypingMode: String, CaseIterable {
    case automatic, off
}

/// What the engine needs to know of the emulator, read by the surface just before a key or just after output.
struct PredictionScreen {
    var x: Int
    var y: Int
    var cols: Int
    /// vim, less, htop: the application owns the screen.
    var alternate: Bool
    /// Scrolled back into history: the cursor row is not on screen.
    var atBottom: Bool
    /// The cell under the cursor is empty (typing at the end of the line, not inserting in the middle of it).
    var nextBlank: Bool
    /// The character at a column of the cursor's row.
    var cell: (Int) -> Character
}

/// Local echo for a slow link, after mosh: a printable key or backspace typed at the end of the line is drawn at once,
/// dimmed and underlined, and checked against the real output when it arrives. Display only: the bytes sent are never
/// changed. Pure, so it is tested without a terminal.
///
/// Conservative on purpose. A prediction is shown only when
/// - the round trip is slow (above `showAbove` ms, back off below `hideBelow`; measured from the echoes themselves),
/// - the screen is not an application's (alternate buffer),
/// - the line has been *proven* to echo: the first key after Enter, a control key, a mismatch or a time-out is only
///   tracked, never shown, until one of its predictions is confirmed. That is what keeps a password prompt (no echo) clean.
struct InstantTyping {
    var mode: InstantTypingMode = .automatic
    static let showAbove = 60.0
    static let hideBelow = 40.0
    /// A prediction nothing confirmed by now is dropped (the program is not echoing).
    static let timeout: TimeInterval = 2

    private(set) var rtt: Double?
    private(set) var slow = false
    private(set) var trusted = false

    enum Op: Equatable {
        case char(Character)
        case back
    }
    private struct Pending {
        let op: Op
        let at: Date
    }
    private var pending: [Pending] = []
    private var base = (x: 0, y: 0)
    /// Cells just left of `base` that we typed ourselves and may therefore erase.
    private var owned = 0

    /// Whether the display should show predictions now.
    var showing: Bool { mode == .automatic && slow && trusted && !pending.isEmpty }
    var hasPending: Bool { !pending.isEmpty }

    /// Cells to draw (column, character; a space erases) on `row`; empty when nothing is shown.
    var cells: (row: Int, cells: [(x: Int, ch: Character)]) {
        guard showing else { return (base.y, []) }
        let s = Self.simulate(pending.map(\.op), from: base.x)
        return (base.y, s.cells.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    /// The cursor column the display should now show.
    var cursorX: Int { Self.simulate(pending.map(\.op), from: base.x).x }

    // MARK: typing

    /// Call with the bytes about to be sent. Returns true when what is shown changed.
    @discardableResult
    mutating func typed(_ data: Data, _ s: PredictionScreen, now: Date = Date()) -> Bool {
        guard mode == .automatic, !s.alternate, s.atBottom, let op = Self.op(for: data) else {
            return reset()
        }
        if pending.isEmpty {
            // Inserting into the middle of a line would shift text we do not know about.
            guard s.nextBlank else { return reset() }
            base = (s.x, s.y)
        }
        let next = pending.map(\.op) + [op]
        let sim = Self.simulate(next, from: base.x)
        let lowest = base.x - owned
        guard sim.x >= max(0, lowest), sim.x < s.cols - 1, sim.low >= max(0, lowest) else { return reset() }
        pending.append(Pending(op: op, at: now))
        return showing
    }

    /// Call after output has been drawn, and on a timer while `hasPending`. Returns true when what is shown changed.
    @discardableResult
    mutating func output(_ s: PredictionScreen, now: Date = Date()) -> Bool {
        guard !pending.isEmpty else { return false }
        let was = showing
        if s.alternate { return reset() }
        if s.y != base.y { return reset() }
        let ops = pending.map(\.op)
        // The real screen may have caught up with the first `n` keys.
        var matched: Int?
        for n in stride(from: ops.count, through: 0, by: -1) {
            let sim = Self.simulate(Array(ops[..<n]), from: base.x)
            if sim.x == s.x, sim.cells.allSatisfy({ Self.same(s.cell($0.key), $0.value) }) {
                matched = n
                break
            }
        }
        guard let n = matched else { return reset() }
        if n == 0 {
            if now.timeIntervalSince(pending[0].at) > Self.timeout { return reset() }
            return false
        }
        sample(now.timeIntervalSince(pending[n - 1].at) * 1000)
        for p in pending[..<n] {
            switch p.op {
            case .char: owned += 1
            case .back: owned = max(0, owned - 1)
            }
        }
        pending.removeFirst(n)
        base.x = s.x
        trusted = true
        return true
    }

    /// Drops everything shown or tracked (a snapshot, a resize, a key we do not predict).
    @discardableResult
    mutating func reset() -> Bool {
        let was = showing || !pending.isEmpty
        pending = []
        trusted = false
        owned = 0
        return was
    }

    // MARK: pieces

    private mutating func sample(_ ms: Double) {
        let r = rtt.map { $0 * 0.7 + ms * 0.3 } ?? ms
        rtt = r
        if r > Self.showAbove { slow = true } else if r < Self.hideBelow { slow = false }
    }

    /// `a`-style keys and backspace only; anything else (Enter, Tab, arrows, Ctrl-keys, pastes, wide text) is not predicted.
    static func op(for data: Data) -> Op? {
        let b = [UInt8](data)
        if b == [0x7f] { return .back }
        guard let str = String(data: data, encoding: .utf8), str.unicodeScalars.count == 1,
            let u = str.unicodeScalars.first
        else { return nil }
        // ASCII and Latin letters: one cell wide, left to right. Arabic, CJK and emoji are left to the real echo.
        guard (0x20...0x7e).contains(u.value) || (0xa0...0x24f).contains(u.value) else { return nil }
        return .char(Character(u))
    }

    /// The cursor and the cells written, after typing `ops` from column `x`; `low` is the leftmost column touched.
    static func simulate(_ ops: [Op], from x: Int) -> (x: Int, low: Int, cells: [Int: Character]) {
        var cx = x
        var low = x
        var cells: [Int: Character] = [:]
        for op in ops {
            switch op {
            case .char(let c):
                cells[cx] = c
                cx += 1
            case .back:
                cx -= 1
                cells[cx] = " "
                low = min(low, cx)
            }
        }
        return (cx, low, cells)
    }

    static func same(_ a: Character, _ b: Character) -> Bool {
        (a == " " || a == "\u{0}") ? (b == " " || b == "\u{0}") : a == b
    }
}
