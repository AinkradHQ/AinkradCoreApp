import Foundation

/// A JSON value: the shape of a node's props and of the edit ops written back (T1 `props`, T12 ops). Whole numbers encode as
/// integers, because the Core's `weight` is an integer prop and `16.0` would be refused.
enum DJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DJSON])
    case object([String: DJSON])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([DJSON].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: DJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v):
            if v == v.rounded(), abs(v) < 1e15 { try c.encode(Int(v)) } else { try c.encode(v) }
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    subscript(key: String) -> DJSON? { if case .object(let o) = self { o[key] } else { nil } }
    var double: Double? { if case .number(let v) = self { v } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var array: [DJSON]? { if case .array(let v) = self { v } else { nil } }
    var object: [String: DJSON]? { if case .object(let v) = self { v } else { nil } }

    /// `{"token": "radius.control"}` and nothing else.
    static func token(_ name: String) -> DJSON { .object(["token": .string(name)]) }
    var tokenName: String? {
        guard let o = object, o.count == 1 else { return nil }
        return o["token"]?.string
    }
}

/// One node in the layers panel: what the engine lists about it (`de_tree`).
struct DesignLayer: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    var type: String
    var parent: String?
    var order: String
    var name: String
    var hidden: Bool

    init(id: String, type: String, parent: String?, order: String, name: String = "", hidden: Bool = false) {
        self.id = id
        self.type = type
        self.parent = parent
        self.order = order
        self.name = name
        self.hidden = hidden
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        order = try c.decodeIfPresent(String.self, forKey: .order) ?? "i"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
    private enum Keys: String, CodingKey { case id, type, parent, order, name, hidden }

    /// Frames, pages and components hold children (T1 `is_container`); an instance's children come from its component.
    var isContainer: Bool { ["page", "frame", "component"].contains(type) }
    /// The row's words: its name, else what it is.
    var title: String { name.isEmpty ? type.capitalizedFirst : name }
    var symbol: String {
        switch type {
        case "page": "doc"
        case "frame": "rectangle.dashed"
        case "text": "textformat"
        case "rect": "rectangle"
        case "ellipse": "oval"
        case "image": "photo"
        case "vector": "scribble"
        case "component": "diamond"
        case "instance": "diamond.fill"
        default: "square"
        }
    }
}

/// One node for the inspector (`de_node`): `{id, type, parent, order, name, props, text}`.
struct EditorNode: Equatable, Sendable, Decodable {
    let id: String
    let type: String
    var parent: String?
    var name: String
    var props: [String: DJSON]
    var text: String?

    init(id: String, type: String, name: String = "", props: [String: DJSON] = [:], text: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.props = props
        self.text = text
    }

    init?(json: String) {
        guard let d = json.data(using: .utf8), let n = try? JSONDecoder().decode(EditorNode.self, from: d) else {
            return nil
        }
        self = n
    }

    var isContainer: Bool { ["frame", "component", "instance"].contains(type) }
    var hasLayout: Bool { props["layout"]?.object != nil }
}

/// Someone else on the design (`de_presence_peers`): a device or an AI session.
struct DesignPeer: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let isAI: Bool
    let selection: [String]

    /// `{"<client>": {label, selection, ai?, session?}}`. A malformed entry is skipped, never trusted: the peer is another
    /// device's text.
    static func decode(_ data: Data?) -> [DesignPeer] {
        guard let data, let all = try? JSONDecoder().decode([String: DJSON].self, from: data) else { return [] }
        return all.compactMap { id, v in
            guard v.object != nil else { return nil }
            let label = String((v["label"]?.string ?? "").prefix(40))
            let ai = v["ai"]?.bool == true || v["session"] != nil
            let sel = (v["selection"]?.array ?? []).compactMap(\.string).prefix(64)
            return DesignPeer(
                id: id, label: label.isEmpty ? (ai ? "An AI session" : "Someone") : label, isAI: ai,
                selection: Array(sel))
        }
        .sorted { ($0.isAI ? 0 : 1, $0.label, $0.id) < ($1.isAI ? 0 : 1, $1.label, $1.id) }
    }
}

/// A token of the design's system, for the pickers: `radius.control`, kind `radius`.
struct DesignToken: Identifiable, Equatable, Sendable, Decodable {
    var id: String { name }
    let name: String
    let kind: String
}

/// A saved state of the design (T14): `auto` before an AI turn or every 10 minutes, `named` by a person, `approval` frozen.
struct DesignVersion: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case auto, named, approval }
    let id: String
    var kind: Kind
    var name: String
    var createdBy: String
    var createdAt: Date?
}

/// The canvas as the editor chrome sees it. The app implements it over the engine (`DesignCanvasNSView.editor…`); tests
/// bring a fake. JSON text in, JSON text out: decoding lives here, in `Features`, where it is tested.
@MainActor
public protocol DesignEditBackend: AnyObject {
    func tree() -> Data?
    func node(_ id: String) -> String?
    func selection() -> [String]
    /// False when the engine cannot select by id.
    func select(_ ids: [String]) -> Bool
    /// A JSON array of edit ops, all or nothing, one undo step; false when refused.
    func edit(_ json: String) -> Bool
    func undo()
    func redo()
    func fitSelection()
    func peers() -> Data?
    func setPresence(_ json: String)
    func tokens() -> Data?
    /// An unsent edit can never go to the Core (it is over what one update takes): the design must be reopened.
    var syncStuck: Bool { get }
    /// The first snapshot from the Core has reached the canvas.
    var loaded: Bool { get }
    /// The sync socket to the Core is open.
    var syncConnected: Bool { get }
    /// The last `edit` was refused because the change is too large for one update.
    var lastEditTooLarge: Bool { get }
    /// The canvas tool (`CanvasTool`); it returns to select by itself after a shape is drawn.
    var tool: Int { get }
    /// A design system's own tokens as JSON `[{name, kind, day, night}]`.
    func docTokens() -> Data?
    func setTool(_ tool: Int)
    /// How document points show in the canvas view: `view = doc × zoom + pan`.
    func camera() -> CanvasCamera?
    /// Moves the camera so the document rect fits the view.
    func fit(_ rect: CGRect)
    /// Presenting: clicks report the node under them (prototype links) and nothing is edited; nil ends it.
    func present(_ tap: (@MainActor (String?) -> Void)?)
}

public struct CanvasCamera: Sendable, Equatable {
    public let zoom: Double
    public let pan: CGPoint
    public init(zoom: Double, pan: CGPoint) {
        self.zoom = zoom
        self.pan = pan
    }
}

extension DesignEditBackend {
    public var syncStuck: Bool { false }
    public var loaded: Bool { true }
    public var syncConnected: Bool { true }
    public var lastEditTooLarge: Bool { false }
    public var tool: Int { 0 }
    public func docTokens() -> Data? { nil }
    public func setTool(_ tool: Int) {}
    public func camera() -> CanvasCamera? { nil }
    public func present(_ tap: (@MainActor (String?) -> Void)?) {}
    public func fit(_ rect: CGRect) {}
}

/// One token of a design system as the style guide edits it: a literal per theme.
struct SystemToken: Identifiable, Equatable, Decodable, Sendable {
    var id: String { name }
    let name: String
    let kind: String
    let day: DJSON
    let night: DJSON

    /// The group it shows in: the part before the first dot (`color.primary` → `color`).
    var group: String { String(name.split(separator: ".").first ?? "") }
    var short: String { name.split(separator: ".").dropFirst().joined(separator: ".") }
}
