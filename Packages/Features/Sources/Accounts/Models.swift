import CoreUI
import Foundation

/// A model a provider lists, with its list price in millionths of a dollar per million tokens (what the API has).
struct ModelPriceItem: Equatable, Sendable {
    let id: String
    let inputMicro: Int64
    let outputMicro: Int64
    /// `$3.00 in, $15.00 out per million tokens`; the Core's own numbers, never rounded away.
    var words: String { "\(Self.usd(inputMicro)) in, \(Self.usd(outputMicro)) out per million tokens" }
    static func usd(_ micro: Int64) -> String { (Double(micro) / 1_000_000).formatted(.currency(code: "USD")) }
}

/// A provider as the Core lists it (`GET /api/v1/accounts/providers`): only the fields the API has.
struct ProviderItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let harness: String
    let authVar: String
    let baseURL: String
    let delivery: [String]
    let loginMethods: [String]
    let models: [ModelPriceItem]
    let pricedAt: String?
    let builtin: Bool
    /// A user definition's key shape (it holds keys through the gateway only), its key-test path, and its version.
    var keyPrefix: String? = nil
    var testPath: String? = nil
    var version: Int64 = 1
}

/// An account as a `read` device sees it: its key's last four characters, never the key.
struct AccountItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let provider: String
    let label: String
    let maskedTail: String
    let baseURL: String
    var state: String
    let stateReason: String?
    let stateUntil: Date?
    var cap: Int64
    let lastUsedAt: Date?
    let createdAt: Date
    /// The last key test (`POST /accounts/{id}/test`): when, and the status class the provider answered.
    var lastTest: (at: Date, result: String)?
    /// What one session may spend on it; nil is no limit.
    var maxTokens: Int64?
    var maxUSDMicros: Int64?
    /// Sessions holding a slot now, and the scheduler's health counters (admin only; nil for any other device).
    var live: Int64?
    var health: AccountHealthItem?
    var phase: AccountPhase { AccountPhase(state) }

    static func == (l: Self, r: Self) -> Bool {
        l.id == r.id && l.provider == r.provider && l.label == r.label && l.maskedTail == r.maskedTail
            && l.baseURL == r.baseURL && l.state == r.state && l.stateReason == r.stateReason
            && l.stateUntil == r.stateUntil && l.cap == r.cap && l.lastUsedAt == r.lastUsedAt
            && l.createdAt == r.createdAt && l.lastTest?.at == r.lastTest?.at
            && l.lastTest?.result == r.lastTest?.result && l.maxTokens == r.maxTokens
            && l.maxUSDMicros == r.maxUSDMicros && l.live == r.live && l.health == r.health
    }
}

struct PoolItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let provider: String
    let isDefault: Bool
    /// Account ids, in fallback order.
    let members: [Int64]
}

/// One step of a chain: the pool tried at this position and the model its accounts run (nil: the harness's default).
struct ChainEntryItem: Equatable, Sendable {
    let pool: Int64
    let provider: String
    let harness: String
    let model: String?
}

/// An ordered fallback chain of 1 to 4 pools. A new session draws its account from the first entry that has one to give.
struct ChainItem: Identifiable, Equatable, Sendable {
    static let maxEntries = 4
    let id: Int64
    let name: String
    let isDefault: Bool
    let entries: [ChainEntryItem]
}

/// An agent's chain: its sessions get this chain.
struct ChainBindingItem: Identifiable, Equatable, Sendable {
    var id: String { agent }
    let agent: String
    let chain: Int64
}

/// One entry being written: a pool and a model (nil: the harness's default).
struct ChainEntryDraft: Equatable, Sendable {
    var pool: Int64
    var model: String?
}

/// An account's state word. The Core says `active`, `cooling`, `limited`, `unhealthy` or `disabled`; any other word shows
/// as itself and is never counted as a problem.
enum AccountPhase: Equatable, Sendable {
    case active, cooling, limited, unhealthy, disabled
    case other(String)

    init(_ raw: String) {
        switch raw {
        case "active": self = .active
        case "cooling": self = .cooling
        case "limited": self = .limited
        case "unhealthy": self = .unhealthy
        case "disabled": self = .disabled
        default: self = .other(raw)
        }
    }

    var label: String {
        switch self {
        case .active: "Ready"
        case .cooling: "Resting"
        case .limited: "Limited"
        case .unhealthy: "Needs a look"
        case .disabled: "Turned off"
        case .other(let raw): raw
        }
    }

    var tone: Tone {
        switch self {
        case .active: .run
        case .cooling, .limited: .warn
        case .unhealthy: .fail
        case .disabled, .other: .queue
        }
    }

    var symbol: String {
        switch self {
        case .active: "checkmark.circle"
        case .cooling: "clock"
        case .limited: "gauge.with.dots.needle.100percent"
        case .unhealthy: "exclamationmark.triangle"
        case .disabled: "pause.circle"
        case .other: "questionmark.circle"
        }
    }

    var needsLook: Bool {
        switch self {
        case .cooling, .limited, .unhealthy: true
        default: false
        }
    }
}

/// What stands between this Core and a stored provider key: `secrets.mode` and `secrets.provider_accounts`.
struct GateState: Equatable, Sendable {
    var mode: Int64?
    var providerAccounts: Int64?

    enum Kind: Equatable { case unknown, off, throwaway, real, other }
    var kind: Kind {
        guard let mode, let providerAccounts else { return .unknown }
        if mode == 0 { return .off }
        if mode == 1 { return providerAccounts >= 1 ? .real : .throwaway }
        return .other
    }

    // Plain words for the screen (Ahmed, 2026-11-05: easy to understand). The settings and codes stay in `technical`.
    var title: String {
        switch kind {
        case .unknown: "Can't tell if accounts can be added"
        case .off: "Adding accounts is turned off"
        case .throwaway: "Test keys only, for now"
        case .real: "Real keys are allowed"
        case .other: "An unusual setting"
        }
    }

    var detail: String {
        switch kind {
        case .unknown: "This Mac couldn't read your Core's settings. Try again in a moment."
        case .off:
            "Your Core is set to keep no provider keys, so an account can't be added yet. Turn it on in Settings."
        case .throwaway:
            "Your Core takes practice keys but refuses real ones, to keep you safe while testing. Allow real keys in Settings when you're ready."
        case .real: "Your Core can keep real provider keys for your agents."
        case .other: "Your Core has a setting this app doesn't know yet."
        }
    }

    /// The same, in the Core's own terms, for the hover help.
    var technical: String {
        "secrets.mode = \(mode.map(String.init) ?? "?"), secrets.provider_accounts = \(providerAccounts.map(String.init) ?? "?")"
            + (kind == .off ? " (secrets_disabled)" : kind == .throwaway ? " (real_secret_refused)" : "")
    }

    /// Where it stands on the way from off to real keys: 0 off, 1 test keys, 2 real keys; nil when unknown.
    var step: Int? {
        switch kind {
        case .off: 0
        case .throwaway: 1
        case .real: 2
        default: nil
        }
    }

    var symbol: String {
        switch kind {
        case .real: "checkmark.shield"
        case .unknown, .other: "questionmark.circle"
        default: "lock"
        }
    }

    var tone: Tone { kind == .real ? .run : kind == .unknown || kind == .other ? .queue : .warn }
}

/// What a page shows in place of its content.
enum AccountsLoad: Equatable {
    case loading
    case ready
    case failed(code: String, message: String)
    case forbidden
}

enum AccountsPage: String, CaseIterable, Identifiable, Sendable {
    case overview, accounts, pools, chains, budgets, costs, ledger, prices
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .accounts: "Accounts"
        case .pools: "Pools"
        case .chains: "Chains"
        case .budgets: "Budgets"
        case .costs: "Costs and usage"
        case .ledger: "Ledger"
        case .prices: "Prices"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .accounts: "creditcard"
        case .pools: "square.grid.2x2"
        case .chains: "link"
        case .budgets: "dollarsign.circle"
        case .costs: "chart.bar"
        case .ledger: "list.bullet"
        case .prices: "tag"
        }
    }
    var isSpend: Bool { [.budgets, .costs, .ledger, .prices].contains(self) }
    static let groups: [(String?, [AccountsPage])] = [
        (nil, [.overview]), ("Accounts", [.accounts, .pools]),
        ("Spend", [.budgets, .costs, .ledger, .prices]),
    ]
}

enum AccountFilter: String, CaseIterable, Sendable {
    case all = "All"
    case need = "Needs a look"
    case off = "Turned off"
    func matches(_ a: AccountItem, verdict: AccountVerdict) -> Bool {
        switch self {
        case .all: true
        case .need: verdict.needsLook
        case .off: a.phase == .disabled
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .need: "exclamationmark.triangle"
        case .off: "pause"
        }
    }
}

/// Where each built-in provider keeps its keys. Only a page to open: this app never takes a key.
enum ProviderSites {
    static func page(_ provider: String) -> (name: String, url: URL)? {
        switch provider {
        case "anthropic": ("the Anthropic Console", URL(string: "https://console.anthropic.com/settings/keys")!)
        case "openai": ("the OpenAI platform", URL(string: "https://platform.openai.com/api-keys")!)
        case "google": ("Google AI Studio", URL(string: "https://aistudio.google.com/apikey")!)
        default: nil
        }
    }
}

enum AccountsWords {
    /// `41 min`, `2 h 10 min`, `3 d`.
    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        if m >= 1440 { return "\(m / 1440) d" }
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    /// `Used 11 min ago`, `Never used`.
    static func used(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "Never used" }
        let s = now.timeIntervalSince(d)
        return s < 60 ? "Used just now" : "Used \(duration(s)) ago"
    }

    /// What a not-ready account is doing, from the fields the API has.
    static func why(_ a: AccountItem, now: Date = Date()) -> String {
        var s: String
        switch a.phase {
        case .cooling: s = "Resting. Other accounts of this provider cover until it is back."
        case .limited: s = "The provider limited it."
        case .unhealthy: s = "Core marked it unhealthy, so agents do not use it."
        case .disabled: s = "Agents will not use it until you turn it back on."
        case .active: s = "Agents can use it now."
        case .other(let raw): s = "Core reports it as \(raw)."
        }
        if let r = a.stateReason, !r.isEmpty { s += r.hasSuffix(".") ? " \(r)" : " \(r)." }
        if let u = a.stateUntil, u > now { s += " Back in \(duration(u.timeIntervalSince(now)))." }
        return s
    }

    /// The section of the account page a verdict's cause lives in.
    static func causeName(_ c: AccountVerdict.Cause) -> String {
        switch c {
        case .keyTest: "Key test"
        case .limits: "Limits"
        case .budgets: "Budgets"
        case .state: "Account state"
        case .pools: "Pools"
        }
    }

    static func capWords(_ cap: Int64) -> String { cap == 0 ? "No limit on sessions at once" : "Up to \(cap) at once" }
}
