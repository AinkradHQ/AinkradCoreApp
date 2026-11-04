import CoreGraphics
import Foundation

/// A widget's footprint on the Home grid (`widgets.js` SZ): s 1x1, m 2x1, t 1x2, l 2x2, x 2x3.
public enum WidgetSize: String, CaseIterable, Codable, Sendable {
    case s, m, t, l, x
    public var cols: Int { self == .m || self == .l || self == .x ? 2 : 1 }
    public var rows: Int { self == .t || self == .l ? 2 : self == .x ? 3 : 1 }
    public var title: String {
        switch self {
        case .s: "Small"
        case .m: "Wide"
        case .t: "Tall"
        case .l: "Large"
        case .x: "XL"
        }
    }
    var area: Int { cols * rows }
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

/// The widget desk as pure data: an 8 x 5 grid of 150 pt cells, widgets that never overlap, and the moves the prototype allows
/// (drag, resize, add, remove). A move pushes whatever is in the way to the nearest free cell, or is refused (nil) when there is none.
public struct WidgetLayout: Equatable, Sendable {
    public static let cols = 8
    public static let rows = 5
    public var items: [WidgetItem]
    public init(items: [WidgetItem] = []) { self.items = items }

    /// The prototype's first layout.
    public static func standard() -> WidgetLayout {
        let d: [(WidgetKind, WidgetSize, Int, Int)] = [
            (.today, .x, 0, 0), (.clock, .s, 0, 3), (.spend, .s, 1, 3), (.quick, .m, 0, 4),
            (.machines, .l, 6, 0), (.board, .m, 6, 2), (.events, .m, 6, 3),
        ]
        return WidgetLayout(items: d.map { WidgetItem(kind: $0.0, size: $0.1, x: $0.2, y: $0.3) })
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
        let sizes = [size] + WidgetSize.allCases.filter { $0 != size && $0.area <= size.area }
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

    // MARK: persistence (`{ v: 1, items: [{ t, s, x, y }] }`)

    private struct Stored: Codable {
        var v = 1
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
    public static func decoded(_ data: Data) -> WidgetLayout? {
        guard let s = try? JSONDecoder().decode(Stored.self, from: data), s.v == 1 else { return nil }
        var out: [WidgetItem] = []
        for r in s.items {
            guard let k = WidgetKind(rawValue: r.t), let z = WidgetSize(rawValue: r.s), k.sizes.contains(z) else {
                continue
            }
            let i = WidgetItem(kind: k, size: z, x: r.x, y: r.y)
            if isFree(i, out) { out.append(i) }
        }
        return WidgetLayout(items: out)
    }
}

/// Stage geometry (`widgets.js`: 150 pt cells, 14 pt gaps, origin 71 / 50), in the 1440 x 900 design stage.
public enum DeskGrid {
    public static let cell: CGFloat = 150
    public static let gap: CGFloat = 14
    public static let originX: CGFloat = 71
    public static let originY: CGFloat = 50
    public static var step: CGFloat { cell + gap }

    public static func origin(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: originX + CGFloat(x) * step, y: originY + CGFloat(y) * step)
    }

    public static func frameSize(_ s: WidgetSize) -> CGSize {
        CGSize(
            width: CGFloat(s.cols) * cell + CGFloat(s.cols - 1) * gap,
            height: CGFloat(s.rows) * cell + CGFloat(s.rows - 1) * gap)
    }

    /// The cell a widget's top-left corner is nearest to, kept on the grid.
    public static func cell(at p: CGPoint, size: WidgetSize) -> (x: Int, y: Int) {
        let x = Int(((p.x - originX) / step).rounded())
        let y = Int(((p.y - originY) / step).rounded())
        return (
            max(0, min(WidgetLayout.cols - size.cols, x)), max(0, min(WidgetLayout.rows - size.rows, y))
        )
    }
}
