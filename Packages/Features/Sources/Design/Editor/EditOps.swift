import Foundation

/// Edit ops (T12) as the engine's `de_edit` reads them: `[{"op": "set", "id": …, "key": …, "value": …}, …]`. Pure, so what
/// the panels write is tested without an engine.
enum EditOps {
    static func name(_ id: String, _ name: String) -> [String: DJSON] {
        ["op": .string("name"), "id": .string(id), "name": .string(name)]
    }
    /// `value: nil` removes the prop.
    static func set(_ id: String, _ key: String, _ value: DJSON?) -> [String: DJSON] {
        ["op": .string("set"), "id": .string(id), "key": .string(key), "value": value ?? .null]
    }
    static func move(_ id: String, parent: String, order: String) -> [String: DJSON] {
        ["op": .string("move"), "id": .string(id), "parent": .string(parent), "order": .string(order)]
    }
    static func delete(_ id: String) -> [String: DJSON] { ["op": .string("delete"), "id": .string(id)] }

    /// The batch as JSON text, keys sorted so it is stable. The Core caps a batch at 200 ops and 1 MiB; a bigger one is not
    /// sent (the engine would refuse it all).
    static func json(_ ops: [[String: DJSON]]) -> String? {
        guard !ops.isEmpty, ops.count <= 200 else { return nil }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let d = try? e.encode(ops), d.count <= 1 << 20 else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
