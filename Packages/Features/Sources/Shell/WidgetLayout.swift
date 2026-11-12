import CoreGraphics
import Foundation

/// A widget's footprint on the Home grid, counted in 16 x 8 grid units: small 2x2, wide 4x2, tall 2x4, large 4x4, extra
/// large 8x4. One Home cell is 2x2 units, so the names read as cells: small 1x1, wide 2x1, tall 1x2, large 2x2 (home-clocks).
/// Only the digital clock has the tall size.
public enum WidgetSize: String, CaseIterable, Codable, Sendable {
    case s, m, t, l, x
    public var cols: Int { self == .s || self == .t ? 2 : self == .x ? 8 : 4 }
    public var rows: Int { self == .s || self == .m ? 2 : 4 }
    public var title: String {
        switch self {
        case .s: "Small"
        case .m: "Wide"
        case .t: "Tall"
        case .l: "Large"
        case .x: "Extra Large"
        }
    }
    /// The size choice in the gallery: one letter (S, W, T, L, X).
    public var short: String {
        switch self {
        case .s: "S"
        case .m: "W"
        case .t: "T"
        case .l: "L"
        case .x: "X"
        }
    }
    /// "Wide, 2 by 1": the name and its footprint in Home cells, for VoiceOver and the menus.
    public var spoken: String { "\(title), \(cols / 2) by \(rows / 2)" }
    var area: Int { cols * rows }

    /// A size saved by an earlier build (8 x 5 grid: s 1x1, m 2x1, t 1x2, l 2x2, x 2x3) on today's grid. That tall size
    /// becomes small (no v1 widget had today's tall), and the old extra large (two cells wide) becomes large.
    static func migrated(_ raw: String) -> WidgetSize? {
        switch raw {
        case "t": .s
        case "x": .l
        default: WidgetSize(rawValue: raw)
        }
    }
}

public struct WidgetItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var size: WidgetSize
    public var x: Int
    public var y: Int
    public init(id: UUID = UUID(), kind: WidgetKind, size: WidgetSize, x: Int, y: Int) {
        self.id = id
        self.kind = kind
        self.size = size
        self.x = x
        self.y = y
    }
}

/// The widget desk as pure data: a 16 x 8 grid of small units, widgets that never overlap, and the moves the prototype allows
/// (drag, resize, add, remove). A move pushes whatever is in the way to the nearest free cell, or is refused (nil) when there is none.
public struct WidgetLayout: Equatable, Sendable {
    public static let cols = 16
    public static let rows = 8
    public var items: [WidgetItem]
    public init(items: [WidgetItem] = []) { self.items = items }

    /// The first layout: the desk of the N9 mockup (its small clock is the digital one).
    public static func standard() -> WidgetLayout {
        let d: [(WidgetKind, WidgetSize, Int, Int)] = [
            (.running, .x, 0, 0), (.spend, .l, 8, 0), (.machines, .l, 12, 0), (.needs, .m, 0, 4), (.core, .m, 4, 4),
            (.events, .l, 8, 4), (.digital, .s, 12, 4), (.quick, .s, 14, 4), (.today, .m, 4, 6),
            (.board, .m, 0, 6),
        ].filter { $0.0 != .board || WidgetKind.boardShown }
        return WidgetLayout(items: d.map { WidgetItem(kind: $0.0, size: $0.1, x: $0.2, y: $0.3) })
    }

    /// The one copy of `kind` on the desk, for the gallery to resize or remove. nil when there is none, and when there
    /// are several: the gallery cannot tell which one is meant, so it offers Add instead (each copy keeps its own controls).
    public func onlyCopy(of kind: WidgetKind) -> WidgetItem? {
        let copies = items.filter { $0.kind == kind }
        return copies.count == 1 ? copies[0] : nil
    }

    // MARK: grid maths

    static func hit(_ a: WidgetItem, _ b: WidgetItem) -> Bool {
        a.x < b.x + b.size.cols && b.x < a.x + a.size.cols && a.y < b.y + b.size.rows && b.y < a.y + a.size.rows
    }

    static func fits(_ i: WidgetItem) -> Bool {
        i.x >= 0 && i.y >= 0 && i.x + i.size.cols <= cols && i.y + i.size.rows <= rows
    }

    static func isFree(_ i: WidgetItem, _ others: [WidgetItem]) -> Bool {
        fits(i) && !others.contains { hit(i, $0) }
    }

    /// The nearest free cell for `it`, preferring straight down, then closest. nil when nothing fits.
    static func spot(_ it: WidgetItem, _ others: [WidgetItem], near: WidgetItem? = nil) -> WidgetItem? {
        if isFree(it, others) { return it }
        let n = near ?? it
        var best: (Double, WidgetItem)?
        for y in 0...(rows - it.size.rows) {
            for x in 0...(cols - it.size.cols) {
                var t = it
                t.x = x
                t.y = y
                guard isFree(t, others) else { continue }
                let cost = Double(abs(x - n.x)) * 1.4 + Double(abs(y - n.y)) + (x == n.x && y > n.y ? -0.5 : 0)
                if best == nil || cost < best!.0 { best = (cost, t) }
            }
        }
        return best?.1
    }

    /// The layout with `mover` at (x, y) and size `size`: the others keep their cell unless in the way, then they step aside.
    /// The mover is first in the result. nil = no room.
    public static func moving(
        _ mover: WidgetItem, to x: Int, _ y: Int, size: WidgetSize? = nil, in list: [WidgetItem]
    ) -> [WidgetItem]? {
        var m = mover
        if let size { m.size = size }
        m.x = max(0, min(cols - m.size.cols, x))
        m.y = max(0, min(rows - m.size.rows, y))
        var out = [m]
        let rest = list.filter { $0.id != mover.id }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        for o in rest {
            if !out.contains(where: { hit(o, $0) }) {
                out.append(o)
                continue
            }
            guard let t = spot(o, out, near: o) else { return nil }
            out.append(t)
        }
        return out
    }

    /// A free cell for a new widget: its size first, then smaller ones. nil when the desk is full.
    public func firstFree(_ kind: WidgetKind, _ size: WidgetSize) -> WidgetItem? {
        // Only sizes this widget has a layout for: the tall size must never land on a widget without one.
        let sizes =
            [size] + WidgetSize.allCases.filter { $0 != size && $0.area <= size.area && kind.sizes.contains($0) }
        for z in sizes {
            for y in 0...(Self.rows - z.rows) {
                for x in 0...(Self.cols - z.cols) {
                    let c = WidgetItem(kind: kind, size: z, x: x, y: y)
                    if Self.isFree(c, items) { return c }
                }
            }
        }
        return nil
    }

    // MARK: edits (each returns false when there is no room; nothing changes then)

    /// Keeps the order of `items` stable (so a re-render does not reshuffle), applying the new cells.
    private mutating func apply(_ next: [WidgetItem]) {
        items = items.map { old in next.first { $0.id == old.id } ?? old }
    }

    @discardableResult public mutating func move(_ id: UUID, to x: Int, _ y: Int) -> Bool {
        guard let i = items.first(where: { $0.id == id }), let next = Self.moving(i, to: x, y, in: items) else {
            return false
        }
        apply(next)
        return true
    }

    @discardableResult public mutating func nudge(_ id: UUID, dx: Int, dy: Int) -> Bool {
        guard let i = items.first(where: { $0.id == id }) else { return false }
        let x = i.x + dx
        let y = i.y + dy
        guard x >= 0, y >= 0, x + i.size.cols <= Self.cols, y + i.size.rows <= Self.rows else { return false }
        return move(id, to: x, y)
    }

    @discardableResult public mutating func resize(_ id: UUID, to size: WidgetSize) -> Bool {
        guard let i = items.first(where: { $0.id == id }), i.size != size, i.kind.sizes.contains(size),
            let next = Self.moving(i, to: i.x, i.y, size: size, in: items)
        else { return false }
        apply(next)
        return true
    }

    @discardableResult public mutating func add(_ kind: WidgetKind, _ size: WidgetSize? = nil) -> WidgetItem? {
        guard let c = firstFree(kind, size ?? kind.sizes[0]) else { return nil }
        items.append(c)
        return c
    }

    /// Drop a new widget (from the gallery) at a cell; the others make room.
    @discardableResult public mutating func insert(_ item: WidgetItem, at x: Int, _ y: Int) -> Bool {
        guard let next = Self.moving(item, to: x, y, in: items + [item]) else { return false }
        items = items.map { old in next.first { $0.id == old.id } ?? old } + [next[0]]
        return true
    }

    @discardableResult public mutating func remove(_ id: UUID) -> WidgetItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Bring a removed widget back near where it was (Undo).
    @discardableResult public mutating func restore(_ item: WidgetItem) -> Bool {
        guard let t = Self.spot(item, items, near: item) ?? firstFree(item.kind, item.size) else { return false }
        var back = t
        back.id = item.id
        items.append(back)
        return true
    }

    // MARK: persistence (`{ v: 2, items: [{ t, s, x, y }] }`; v1 was the 8 x 5 grid)

    private struct Stored: Codable {
        var v = 2
        var items: [Row]
        struct Row: Codable {
            var t: String
            var s: String
            var x: Int
            var y: Int
        }
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(
            Stored(items: items.map { .init(t: $0.kind.rawValue, s: $0.size.rawValue, x: $0.x, y: $0.y) }))
    }

    /// nil for anything unreadable; rows that name an unknown widget or size, or do not fit or overlap, are dropped.
    /// A v1 layout moves to the new grid: cells double, sizes migrate (`WidgetSize.migrated`), and a widget that no longer
    /// fits where it was takes the nearest free spot (dropped only when the desk has no room).
    public static func decoded(_ data: Data) -> WidgetLayout? {
        guard let s = try? JSONDecoder().decode(Stored.self, from: data), s.v == 1 || s.v == 2 else { return nil }
        var out: [WidgetItem] = []
        let ordered = s.v == 1 ? s.items.sorted { ($0.y, $0.x) < ($1.y, $1.x) } : s.items
        for r in ordered {
            guard let k = WidgetKind(rawValue: r.t),
                let z = s.v == 1 ? WidgetSize.migrated(r.s) : WidgetSize(rawValue: r.s)
            else { continue }
            let size = k.sizes.contains(z) ? z : k.sizes[0]
            if s.v == 1 {
                var i = WidgetItem(kind: k, size: size, x: r.x * 2, y: r.y * 2)
                i.y = min(i.y, rows - size.rows)
                i.x = min(i.x, cols - size.cols)
                if let spot = spot(i, out) { out.append(spot) }
            } else {
                guard k.sizes.contains(z) else { continue }
                let i = WidgetItem(kind: k, size: z, x: r.x, y: r.y)
                if isFree(i, out) { out.append(i) }
            }
        }
        return WidgetLayout(items: out)
    }
}

/// Stage geometry in the 1440 x 900 design stage: square 76 pt units, 12 pt gaps. A small widget is 164 pt, medium
/// 340 x 164, large 340 x 340, extra large 692 x 340.
public enum DeskGrid {
    /// Side margin on the 1440 x 900 stage (Ahmed, 2026-11-05: as little empty space at the screen edges as the bottom
    /// margin; the prototype had 71).
    public static let originX: CGFloat = 20
    public static let originY: CGFloat = 50
    public static let gap: CGFloat = 12
    /// The 16 columns fill the width between the side margins; the units are square, as macOS widgets are.
    public static let cellW: CGFloat = (1440 - 2 * originX - 15 * gap) / 16
    public static let cellH: CGFloat = cellW
    public static var stepX: CGFloat { cellW + gap }
    public static var stepY: CGFloat { cellH + gap }

    public static func origin(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: originX + CGFloat(x) * stepX, y: originY + CGFloat(y) * stepY)
    }

    public static func frameSize(_ s: WidgetSize) -> CGSize {
        CGSize(
            width: CGFloat(s.cols) * cellW + CGFloat(s.cols - 1) * gap,
            height: CGFloat(s.rows) * cellH + CGFloat(s.rows - 1) * gap)
    }

    /// The cell a widget's top-left corner is nearest to, kept on the grid.
    public static func cell(at p: CGPoint, size: WidgetSize) -> (x: Int, y: Int) {
        let x = Int(((p.x - originX) / stepX).rounded())
        let y = Int(((p.y - originY) / stepY).rounded())
        return (
            max(0, min(WidgetLayout.cols - size.cols, x)), max(0, min(WidgetLayout.rows - size.rows, y))
        )
    }
}
