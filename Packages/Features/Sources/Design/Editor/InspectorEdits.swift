import Foundation

/// The values the inspector writes, built from the node's current props. Pure, so every write is tested without a view.
enum InspectorEdits {
    /// `layout` with one key changed (`nil` removes it). A node with no layout starts from a column.
    static func layout(_ n: EditorNode, _ key: String, _ value: DJSON?) -> DJSON {
        var o = n.props["layout"]?.object ?? ["dir": .string("column")]
        o[key] = value
        return .object(o)
    }

    /// `pad` is four numbers (top, right, bottom, left) in the schema; the field edits one number for all four.
    static func pad(_ v: Double) -> DJSON { .array(Array(repeating: .number(v), count: 4)) }
    static func padValue(_ n: EditorNode) -> Double? {
        n.props["layout"]?["pad"]?.array?.first?.double
    }

    /// `sizing` with one axis changed.
    static func sizing(_ n: EditorNode, _ axis: String, _ mode: String) -> DJSON {
        var o = n.props["sizing"]?.object ?? [:]
        o[axis] = .string(mode)
        return .object(o)
    }

    /// The first fill is the one the inspector edits; the rest are kept as they are.
    static func fills(_ n: EditorNode) -> [DJSON] { n.props["fill"]?.array ?? [] }
    static func firstSolid(_ n: EditorNode) -> DJSON? {
        guard let f = fills(n).first, f["type"]?.string == "solid" else { return nil }
        return f["color"]
    }
    static func fill(_ n: EditorNode, color: DJSON) -> DJSON {
        var all = fills(n)
        let solid = DJSON.object(["type": .string("solid"), "color": color])
        // A gradient or image first fill stays as it is.
        if all.isEmpty { all = [solid] } else if all[0]["type"]?.string == "solid" { all[0] = solid }
        return .array(all)
    }
    static func removingFirstFill(_ n: EditorNode) -> DJSON? {
        let rest = Array(fills(n).dropFirst())
        return rest.isEmpty ? nil : .array(rest)
    }

    /// The most strokes a node takes.
    static let maxStrokes = 8

    /// `stroke` is one object or a list of up to eight; the inspector always works on the list.
    static func strokes(_ n: EditorNode) -> [DJSON] {
        guard let s = n.props["stroke"] else { return [] }
        return s.array ?? (s.object == nil ? [] : [s])
    }

    /// The prop for a list of strokes: nothing, one object (as older designs and the Core's AI write it) or a list.
    static func strokeValue(_ list: [DJSON]) -> DJSON? {
        list.isEmpty ? nil : list.count == 1 ? list[0] : .array(list)
    }

    static let newStroke = DJSON.object(["color": .string("#111111"), "width": .number(1), "align": .string("inside")])

    /// Stroke `i` with one key changed (`nil` removes it).
    static func stroking(_ list: [DJSON], _ i: Int, _ key: String, _ value: DJSON?) -> [DJSON] {
        guard list.indices.contains(i) else { return list }
        var all = list
        var o = all[i].object ?? [:]
        o[key] = value
        all[i] = .object(o)
        return all
    }

    /// How a stroke's dash list reads: none is solid, a gap twice the width after a dash of one width is dotted.
    static func dashName(_ s: DJSON) -> String {
        guard let d = s["dash"]?.array?.compactMap(\.double), let first = d.first, first > 0 else { return "solid" }
        return first <= max(1, s["width"]?.double ?? 1) * 1.01 ? "dotted" : "dashed"
    }

    /// The `dash` list for a name at a stroke width; nil is solid.
    static func dash(_ name: String, width: Double) -> DJSON? {
        let w = max(1, width)
        switch name {
        case "dashed": return .array([.number(w * 4), .number(w * 2)])
        case "dotted": return .array([.number(w), .number(w * 2)])
        default: return nil
        }
    }

    /// An inner shadow is a shadow with `inset`.
    static func isInset(_ shadow: DJSON) -> Bool { shadow["inset"]?.bool == true }

    /// `type` (a text node's style) with one key changed; a token-named style is replaced by a literal one.
    static func type(_ n: EditorNode, _ key: String, _ value: DJSON) -> DJSON {
        var o = n.props["type"]?.tokenName == nil ? (n.props["type"]?.object ?? [:]) : [:]
        o[key] = value
        return .object(o)
    }

    /// The literal a prop takes when a person leaves its token ("Value").
    static func literal(kind: String) -> DJSON {
        switch kind {
        case "color": .string("#808080")
        case "radius": .number(8)
        case "space", "size": .number(16)
        case "material": .string("glass")
        case "type": .object(["size": .number(13), "weight": .number(400)])
        default: .null
        }
    }

    /// `overrides` (an instance's changes by child path) without one path; nil when none is left.
    static func overrides(_ n: EditorNode, removing path: String) -> DJSON? {
        var o = n.props["overrides"]?.object ?? [:]
        o[path] = nil
        return o.isEmpty ? nil : .object(o)
    }

    static func overridePaths(_ n: EditorNode) -> [(path: String, props: Int)] {
        (n.props["overrides"]?.object ?? [:]).map { ($0.key, $0.value.object?.count ?? 0) }.sorted { $0.path < $1.path }
    }
}
