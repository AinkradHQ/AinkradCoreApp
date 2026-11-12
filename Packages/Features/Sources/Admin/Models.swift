import Foundation

/// A setting as the Core lists it (`GET /api/v1/settings`): only the fields the API has.
struct SettingItem: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let detail: String
    /// The Core's unit word (`seconds`, `count`, ...), or one this build does not know, kept raw.
    let unit: String
    let defaultValue: Int64
    let min: Int64
    let max: Int64
    var value: Int64
    /// Where the value was set (`server`); nil: it is the default.
    var source: String?

    var isOverride: Bool { source != nil }
    var group: String { key.split(separator: ".", maxSplits: 1).first.map(String.init) ?? key }
    var name: String { key.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? key }
    /// The suffix beside a number: `s`, `ms`, `%`, `B`, `/min`; an unknown unit shows its raw word.
    var unitLabel: String { Units.label(unit) }
    /// 0 to 1: where the value sits between the bounds.
    func position(_ v: Int64) -> Double {
        guard max > min else { return 0 }
        return Swift.min(Swift.max(Double(v - min) / Double(max - min), 0), 1)
    }
}

enum Units {
    static func label(_ unit: String) -> String {
        switch unit {
        case "seconds": "s"
        case "milliseconds": "ms"
        case "percent": "%"
        case "count": ""
        case "bytes": "B"
        case "per_minute": "/min"
        default: unit
        }
    }
}

/// Who acted, on an audited change: the Core names a user by number, or the system.
enum ActorInfo: Equatable, Sendable {
    case user(Int64)
    case system
    var label: String {
        switch self {
        case .user(let n): "User \(n)"
        case .system: "The Core itself"
        }
    }
    /// The word the audit `actor` filter takes.
    var kind: String {
        switch self {
        case .user: "user"
        case .system: "system"
        }
    }
}

struct SettingChangeItem: Identifiable, Equatable, Sendable {
    var id: Int64 { seq }
    let seq: Int64
    let at: Date
    let actor: ActorInfo
    /// What was set before; nil when it inherited the default.
    let old: Int64?
    /// What was set; nil for a reset.
    let new: Int64?
}

/// A secret: name and metadata, never its value. There is no field for one anywhere in this type.
struct SecretItem: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let owner: String
    let runners: [String]
    let delivery: String
    let version: Int64
    let size: Int64
    let keyID: String
    let createdAt: Date
    let updatedAt: Date
    /// `text`, `multiline`, `file` or `env_bundle`; a Core before API minor 54 sends none, and that is `text`.
    var kind = "text"
    var description = ""
    var fileName: String?
    var fileMode: String?
    /// The group it is in; its runners are used when the secret has none of its own.
    var group: String?
    /// The runners that really may use it: its own, else its group's.
    var effectiveRunners: [String]?
    var lastUsedAt: Date?
    var useCount: Int64 = 0

    var runnersUsing: [String] { effectiveRunners ?? runners }
}

/// A group of secrets (one level): a description and a runner list its members inherit.
struct SecretGroupItem: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    var description: String
    var members: [String]
    var runners: [String]
}

/// What a new secret or a new value carries to the Core. The value is text; for a file it is the file's bytes in base64.
struct SecretDraft: Sendable {
    var name: String
    var kind: String
    var value: String
    var delivery: String
    var runners: [String]
    var description: String
    var group: String?
    var fileName: String?
    var fileMode: String?
}

/// A lease this Mac granted. The Core has no list of leases, so these are the ones made since the app opened.
struct LeaseItem: Identifiable, Equatable, Sendable {
    var id: String { lease }
    let lease: String
    let secret: String
    let runner: String
    let expiresAt: Date
    var grantedAt = Date()
}

struct RunnerChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let online: Bool
    let drivers: [String]
}

struct AuditItem: Identifiable, Equatable, Sendable {
    var id: Int64 { seq }
    let seq: Int64
    let at: Date
    let action: String
    let actor: ActorInfo
    let entityKind: String?
    let entityRef: String?
    /// The row's `details`, as pretty JSON (rows are content free: never terminal bytes or secret values).
    let details: String
}

struct AuditPageItem: Equatable, Sendable {
    var items: [AuditItem]
    var nextBefore: Int64?
}

struct AuditFilter: Equatable, Sendable {
    var kind = ""
    var target = ""
    var actor: ActorFilter = .any
    var isEmpty: Bool { kind.isEmpty && target.isEmpty && actor == .any }
}

enum ActorFilter: String, CaseIterable, Sendable {
    case any, user, system
}

/// What a section shows in place of its content.
enum SectionState: Equatable {
    case loading
    case ready
    case empty
    case failed(code: String, message: String, errorID: String?)
    case forbidden
}

/// A refusal from the Core with its error code and `error_id`, for the screens to say in words.
struct AdminFailure: Error, Equatable, Sendable {
    let status: Int
    let code: String
    let message: String
    let errorID: String?
}

/// This device's step-up did not elevate: the action did not run, and `AdminHost.elevationNotice` says why.
public struct AdminDeclined: Error {
    public init() {}
}

/// Why an elevated action did not run, in words, for the panel that asked to show inline.
public struct AdminNotice: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var symbol: String
    public var warn: Bool
    public init(title: String, detail: String, symbol: String, warn: Bool) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.warn = warn
    }
}

enum SettingChangeWords {
    /// `120 → 300 (+180)`, `300 → reset to default`; an inherited old value reads `default`.
    static func text(_ c: SettingChangeItem) -> String {
        let old = c.old.map { AdminWords.number($0) } ?? "default"
        guard let new = c.new else { return "\(old) → reset to default" }
        var s = "\(old) → \(AdminWords.number(new))"
        if let o = c.old { s += new >= o ? " (+\(AdminWords.number(new - o)))" : " (−\(AdminWords.number(o - new)))" }
        return s
    }
}
