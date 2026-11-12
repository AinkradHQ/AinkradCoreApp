import Foundation

// Activity's shapes: who touched which room, what was refused, and what a model ever received from a room. Ids, codes and
// plain verbs only. Nothing here can hold a memory's title, text or a search word (BM-00 I-8, BM-02 egress log).

/// The feed's category filter. `.all` is a filter value only, never the kind of an event.
public enum ActivityKind: String, Sendable, CaseIterable, Hashable {
    case all, blocked, changes, sync, access
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum ActivityResult: String, Sendable, CaseIterable, Hashable {
    case ok, blocked, failed
    public var label: String {
        switch self {
        case .ok: "Allowed"
        case .blocked: "Blocked"
        case .failed: "Failed"
        }
    }
}

/// The rule that refused something: its code (hover help), its plain name and what to do about it.
public struct BlockRule: Sendable, Hashable {
    public let code: String
    public let name: String
    public let fix: String
    public init(_ code: String, _ name: String, fix: String) {
        self.code = code
        self.name = name
        self.fix = fix
    }
}

/// One id or code in the details panel.
public struct DetailLine: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let value: String
}

public struct ActivityEvent: Sendable, Hashable, Identifiable {
    public var id: String { "evt-\(seq)" }
    public let seq: Int
    public let at: String
    public let actor: String
    public let device: String
    /// A plain verb phrase, never content.
    public let action: String
    public let room: String?
    public let result: ActivityResult
    public let reason: String?
    public let kind: ActivityKind
    public let rule: BlockRule?
    public let actionCode: String
    public let sessionID: String
    public let policyVersion: String

    public init(
        seq: Int, at: String, actor: String, device: String, action: String, room: String?, result: ActivityResult,
        reason: String? = nil, kind: ActivityKind, rule: BlockRule? = nil, actionCode: String = "event.other",
        sessionID: String = "sess-0000", policyVersion: String = "v7"
    ) {
        self.seq = seq
        self.at = at
        self.actor = actor
        self.device = device
        self.action = action
        self.room = room
        self.result = result
        self.reason = reason
        self.kind = kind
        self.rule = rule
        self.actionCode = actionCode
        self.sessionID = sessionID
        self.policyVersion = policyVersion
    }

    public var resultCode: String { result == .ok ? "allowed" : rule?.code ?? result.rawValue }
    /// The ids and codes of the details panel. Never the action text, the reason or anything typed.
    public var details: [DetailLine] {
        [
            DetailLine(key: "Event id", value: id), DetailLine(key: "Action code", value: actionCode),
            DetailLine(key: "Result code", value: resultCode), DetailLine(key: "Room id", value: room ?? "none"),
            DetailLine(key: "Device id", value: device.lowercased().replacingOccurrences(of: " ", with: "-")),
            DetailLine(key: "Session id", value: sessionID), DetailLine(key: "Policy version", value: policyVersion),
        ]
    }
}

public struct ActivityPage: Sendable, Hashable {
    public var events: [ActivityEvent]
    public var hasMore: Bool
    public init(events: [ActivityEvent], hasMore: Bool = false) {
        self.events = events
        self.hasMore = hasMore
    }
}

// MARK: egress log

public enum EgressKind: String, Sendable, CaseIterable, Hashable {
    case model, embedding, rerank, distill
    public var label: String {
        switch self {
        case .model: "Answer"
        case .embedding: "Meaning search"
        case .rerank: "Re-ordering results"
        case .distill: "Summarising"
        }
    }
}

public enum EgressBlock: String, Sendable, CaseIterable, Hashable {
    case notListed = "not_listed"
    case noApproval = "no_approval"
    case expired, revoked, visibility, restricted
    case modelDown = "model_down"
    public var sentence: String {
        switch self {
        case .notListed: "This provider is not on the room\u{2019}s list."
        case .noApproval: "No approval for this provider."
        case .expired: "The approval has expired."
        case .revoked: "The approval was revoked."
        case .visibility: "Some memories are too private for a cloud model."
        case .restricted: "Restricted memories never leave this Mac."
        case .modelDown: "The local model was down."
        }
    }
    public var ruleName: String {
        switch self {
        case .visibility, .restricted: "Visibility rule"
        default: "Provider rules"
        }
    }
}

/// One try to send something from a room to a model, allowed or blocked. Records are listed by id, never by text.
public struct EgressCall: Sendable, Hashable, Identifiable {
    public let id: String
    public let at: String
    public let room: String
    public let kind: EgressKind
    public let target: String
    public let provider: ProviderClass
    public let block: EgressBlock?
    public let recordIDs: [String]
    public let bytes: Int
    public let tokensIn: Int
    public let tokensOut: Int
    public let redacted: Int
    public let actor: String
    public let sessionID: String
    public let approvalID: String?

    public init(
        id: String, at: String, room: String, kind: EgressKind, target: String, provider: ProviderClass,
        block: EgressBlock? = nil, recordIDs: [String], bytes: Int = 0, tokensIn: Int = 0, tokensOut: Int = 0,
        redacted: Int = 0, actor: String, sessionID: String, approvalID: String? = nil
    ) {
        self.id = id
        self.at = at
        self.room = room
        self.kind = kind
        self.target = target
        self.provider = provider
        self.block = block
        self.recordIDs = recordIDs
        self.bytes = bytes
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.redacted = redacted
        self.actor = actor
        self.sessionID = sessionID
        self.approvalID = approvalID
    }

    public var sent: Bool { block == nil }
    public var stayedHere: Bool { provider == .local && sent }
    public var details: [DetailLine] {
        [
            DetailLine(key: "Call id", value: id), DetailLine(key: "Room id", value: room),
            DetailLine(key: "Kind code", value: kind.rawValue),
            DetailLine(key: "Target class", value: provider.rawValue),
            DetailLine(key: "Decision", value: block.map { "blocked / \($0.rawValue)" } ?? "sent"),
            DetailLine(key: "Approval id", value: approvalID ?? "none"),
            DetailLine(key: "Session id", value: sessionID), DetailLine(key: "Policy version", value: "v7"),
            DetailLine(key: "Records sent", value: recordIDs.isEmpty ? "none" : recordIDs.joined(separator: ", ")),
            DetailLine(key: "Tokens in / out", value: "\(tokensIn) / \(tokensOut)"),
            DetailLine(key: "Redaction hits", value: "\(redacted)"),
        ]
    }
}

// MARK: filters

/// The feed's filters. Pure: it decides what is shown from what the service sent, nothing else.
public struct ActivityFilter: Sendable, Equatable {
    public enum RoomChoice: Hashable, Sendable {
        case all, none
        case room(String)
    }
    public var kind: ActivityKind = .all
    public var room: RoomChoice = .all
    /// "" is anyone.
    public var who = ""
    public var result: ActivityResult?
    public init() {}

    /// Whether a filter the person set is on. The room follows the room picker, so it never counts.
    public var isActive: Bool {
        var base = self
        base.room = .all
        return base != ActivityFilter()
    }

    /// Rows of a sealed room never show (Q2): `mounted` is the set of mounted room ids.
    public func matches(_ e: ActivityEvent, mounted: Set<String>) -> Bool {
        if let r = e.room, !mounted.contains(r) { return false }
        switch kind {
        case .all: break
        case .blocked: if e.result != .blocked { return false }
        default: if e.kind != kind { return false }
        }
        switch room {
        case .all: break
        case .none: if e.room != nil { return false }
        case .room(let id): if e.room != id { return false }
        }
        if !who.isEmpty, e.actor != who { return false }
        if let result, e.result != result { return false }
        return true
    }

    public func apply(_ events: [ActivityEvent], mounted: Set<String>) -> [ActivityEvent] {
        events.filter { matches($0, mounted: mounted) }
    }
}

extension BrainWords {
    public static func blockedBy(_ rule: String) -> String { "Blocked by: \(rule)" }
    public static func leftNothing(_ room: String) -> String { "Nothing from \(room) has left this Mac" }
    public static let leftNothingText =
        "This room is local only. It is not visible to cloud AI sessions and not backed up."
    public static let activityIdsOnly = "Ids and codes only. No memory text or search words are kept here."

    /// One row of the feed, as a sentence: who, on what, where, and how it ended. Words only; the codes are elsewhere.
    static func sentence(_ e: ActivityEvent, room: String?) -> String {
        let where_ = room.map { "in \($0)" } ?? "with no room chosen"
        let how =
            switch e.result {
            case .ok: "It was allowed."
            case .blocked: "It was blocked\(e.reason.map { ": \($0)" } ?? ".")"
            case .failed: "It failed\(e.reason.map { ": \($0)" } ?? ".")"
            }
        return "\(e.actor) on \(e.device): \(e.action.lowercased()) \(where_). \(how)"
    }

    /// One row of "Sent out of this Mac", as a sentence.
    static func sentence(_ c: EgressCall) -> String {
        let place =
            c.provider == .local
            ? "a model on this Mac"
            : c.provider == .approvedCloud ? "an approved cloud model" : "a model you have not approved"
        guard c.sent else {
            return "\(c.actor) tried to use \(place) for \(c.kind.label.lowercased()). It was blocked, so nothing left."
        }
        return c.stayedHere
            ? "\(c.actor) used \(place) for \(c.kind.label.lowercased()). Nothing left this Mac."
            : "\(c.actor) sent \(c.kind.label.lowercased()) to \(place)."
    }
}
