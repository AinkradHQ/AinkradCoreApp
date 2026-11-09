import Foundation

// The Inbox's shapes. Unlike `BrainModels`, these DO carry memory content (titles, text), because the Inbox is where
// you decide on it. So they live only in `InboxState`, only for the one viewing room, and are cleared before any room
// switch, seal or lock. They are never logged, persisted, or put in a bell, toast or push (BM-00 I-8).

/// What kind of memory a candidate is, in the words the screens use.
public enum MemoryType: String, Sendable, CaseIterable, Hashable {
    case identity, preference, rule, fact, decision, state, task, summary
    public var label: String {
        self == .state ? "Project state" : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// Who said so. A higher rank wins; keeping a lower one over a higher one asks for Touch ID.
public enum Authority: String, Sendable, CaseIterable, Hashable {
    case userExplicit = "user-explicit"
    case tenantOwner = "tenant-owner"
    case projectOwner = "project-owner"
    case teamMember = "team-member"
    case imported
    case modelInferred = "model-inferred"

    public var label: String {
        switch self {
        case .userExplicit: "You said so"
        case .tenantOwner: "Room owner"
        case .projectOwner: "Project owner"
        case .teamMember: "Team member"
        case .imported: "Imported"
        case .modelInferred: "Guessed by a model"
        }
    }
    public var rank: Int {
        switch self {
        case .userExplicit: 5
        case .tenantOwner: 4
        case .projectOwner: 3
        case .teamMember: 2
        case .imported: 1
        case .modelInferred: 0
        }
    }
}

/// A memory an agent proposed. Nothing is used until you approve it.
public struct Candidate: Sendable, Hashable, Identifiable {
    public let id: String
    public let room: String
    public var type: MemoryType
    public var title: String
    public var text: String
    public let source: String
    public let by: String
    public let age: String
    /// Set when the text reads like an instruction. It is shown as quoted text and asks before approving.
    public let flag: String?
    public init(
        id: String, room: String, type: MemoryType, title: String, text: String, source: String, by: String,
        age: String, flag: String? = nil
    ) {
        self.id = id
        self.room = room
        self.type = type
        self.title = title
        self.text = text
        self.source = source
        self.by = by
        self.age = age
        self.flag = flag
    }
}

public struct ConflictSide: Sendable, Hashable {
    public let text: String
    public let source: String
    public let authority: Authority
    public let scope: String
    public let when: String
    public init(text: String, source: String, authority: Authority, scope: String, when: String) {
        self.text = text
        self.source = source
        self.authority = authority
        self.scope = scope
        self.when = when
    }
}

/// Two memories in one room that disagree. Two rooms that disagree are not a conflict.
public struct Conflict: Sendable, Hashable, Identifiable {
    public let id: String
    public let room: String
    public let title: String
    public let a: ConflictSide
    public let b: ConflictSide
    public let age: String
    public init(id: String, room: String, title: String, a: ConflictSide, b: ConflictSide, age: String) {
        self.id = id
        self.room = room
        self.title = title
        self.a = a
        self.b = b
        self.age = age
    }
    /// Both sides apply to the same scope, so they cannot both stay.
    var sameScope: Bool { a.scope == b.scope }
}

public enum ConflictChoice: String, Sendable, Hashable { case first, second, both }

/// A note a room rule stopped. It names the rule; the blocked secret itself is never shown.
public struct BlockedNote: Sendable, Hashable, Identifiable {
    public let id: String
    public let room: String
    public let title: String
    public let ruleName: String
    public let ruleAbout: String
    public let source: String
    public let by: String
    public let age: String
    public init(
        id: String, room: String, title: String, ruleName: String, ruleAbout: String, source: String, by: String,
        age: String
    ) {
        self.id = id
        self.room = room
        self.title = title
        self.ruleName = ruleName
        self.ruleAbout = ruleAbout
        self.source = source
        self.by = by
        self.age = age
    }
}

/// A capture that had no trusted room. It sits in the unclassified inbox, which is not a room.
public struct Capture: Sendable, Hashable, Identifiable {
    public let id: String
    public let source: String
    public let days: Int
    /// A room name the local model guessed, only if that is turned on. Advice, not action.
    public let guess: String?
    public init(id: String, source: String, days: Int, guess: String? = nil) {
        self.id = id
        self.source = source
        self.days = days
        self.guess = guess
    }
    /// Older than 14 days shows as stale; at 30 days it also rings the bell.
    public var stale: Bool { days >= 14 }
    public var inBell: Bool { days >= 30 }
    var age: String { days == 1 ? "1 day" : "\(days) days" }
}

/// What one room's Inbox holds. Only for the viewing room.
public struct RoomInbox: Sendable, Hashable {
    public var room: String
    public var waiting: [Candidate]
    public var conflicts: [Conflict]
    public var blocked: [BlockedNote]
    public init(room: String, waiting: [Candidate] = [], conflicts: [Conflict] = [], blocked: [BlockedNote] = []) {
        self.room = room
        self.waiting = waiting
        self.conflicts = conflicts
        self.blocked = blocked
    }
}

public enum MoveMode: String, Sendable, Hashable, CaseIterable { case move, copy }

public struct CandidateEdit: Sendable, Hashable {
    public var title: String
    public var text: String
    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// The settings of "Approve with options…". The plain Approve uses the room defaults.
public struct ApproveOptions: Sendable, Hashable {
    public var appliesTo = "Whole project"
    public var whoSaidSo: Authority = .projectOwner
    public var validUntil = "No end date"
    public var reviewAgain = "In 90 days"
    public init() {}
    public static let appliesChoices = ["Whole project", "Only me", "This team"]
    public static let untilChoices = ["No end date", "90 days", "1 year"]
    public static let reviewChoices = ["In 90 days", "In 30 days", "Never"]
}

/// Every change the Inbox can ask for. One method on the service takes it, so each screen action is one case.
public enum InboxAction: Sendable, Hashable {
    case approve(id: String, room: String, edit: CandidateEdit?, options: ApproveOptions?)
    case reject(id: String, room: String)
    case keep(id: String, room: String, ConflictChoice)
    case redact(id: String, room: String)
    case discard(id: String, room: String)
    case assign(ids: [String], room: String, mode: MoveMode)
    case split(id: String, rooms: [String])
    case markPrivate(ids: [String])
    case exclude(ids: [String])
    case delete(ids: [String])
}

/// The four lists of the Inbox.
public enum InboxList: String, Sendable, CaseIterable, Hashable {
    case waiting, conflicts, blocked, noRoom
    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .conflicts: "Conflicts"
        case .blocked: "Blocked"
        case .noRoom: "No room yet"
        }
    }
}

/// How an approve ended. A flagged note needs its confirm first.
public enum InboxOutcome: Sendable, Hashable { case done, needsConfirm, cancelled, failed }
