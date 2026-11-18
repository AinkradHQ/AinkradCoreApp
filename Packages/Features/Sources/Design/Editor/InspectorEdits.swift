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

    static func stroke(_ n: EditorNode, _ key: String, _ value: DJSON) -> DJSON {
        var o = n.props["stroke"]?.object ?? ["width": .number(1)]
        o[key] = value
        return .object(o)
    }

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
