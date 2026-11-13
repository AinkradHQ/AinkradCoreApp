import Foundation

/// The kinds of extra allow a room can name. Matches the Core's `brain_room_access.kind`.
public enum AccessKind: String, Codable, Sendable, CaseIterable, Hashable {
    case project, runner, session

    public var title: String {
        switch self {
        case .project: "Project"
        case .runner: "Runner"
        case .session: "AI session"
        }
    }
}

/// `GET /rooms/{room}/access`: who besides the matching project may see a room through an AI session. Matches AinkradCore
/// `RoomAccess` (feat/mcp-e4-brain, 7b68d0fa); `room` is echoed and not kept. All three lists empty means project match only.
public struct RoomAccess: Codable, Sendable, Equatable {
    public var project: [String]
    public var runner: [String]
    public var session: [String]

    public init(project: [String] = [], runner: [String] = [], session: [String] = []) {
        self.project = project
        self.runner = runner
        self.session = session
    }

    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        project = try c.decodeIfPresent([String].self, forKey: .project) ?? []
        runner = try c.decodeIfPresent([String].self, forKey: .runner) ?? []
        session = try c.decodeIfPresent([String].self, forKey: .session) ?? []
    }

    public subscript(kind: AccessKind) -> [String] {
        get {
            switch kind {
            case .project: project
            case .runner: runner
            case .session: session
            }
        }
        set {
            switch kind {
            case .project: project = newValue
            case .runner: runner = newValue
            case .session: session = newValue
            }
        }
    }

    /// Every extra allow, kind by kind.
    public var entries: [(kind: AccessKind, value: String)] {
        AccessKind.allCases.flatMap { k in self[k].map { (k, $0) } }
    }
}

/// The PUT body: only the list being changed, so a list left out stays as the Core has it.
struct AccessPutBody: Encodable {
    var lists: [String: [String]]
    func encode(to e: any Encoder) throws {
        var c = e.container(keyedBy: AnyKey.self)
        for (k, v) in lists { try c.encode(v, forKey: AnyKey(k)) }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension BrainRoutes {
    func roomAccess(room: String) async throws -> RoomAccess {
        try await call("GET", "/rooms/\(Self.seg(room))/access")
    }
    /// Step-up route: the caller asks for Touch ID around it.
    func putRoomAccess(room: String, kind: AccessKind, values: [String]) async throws -> RoomAccess {
        try await call("PUT", "/rooms/\(Self.seg(room))/access", AccessPutBody(lists: [kind.rawValue: values]))
    }
}
