import CoreUI
import Foundation

/// The pure rules of the AI order surface: moves, the state chip, the usage sentence, the Add steps. No views, no Core.

enum ProviderKind: Hashable, Sendable { case subscription, apiKey }

/// How a provider is shown: its name, its one letter and the line under it on the Add card. Names the Core knows come from
/// this table; any other provider the Core lists shows under its own name, so a new preset needs no UI work.
enum ProviderCatalog {
    private static let faces: [String: (name: String, blurb: String)] = [
        "claude-sub": ("Claude", "Your Claude plan"), "codex-sub": ("ChatGPT / Codex", "Your ChatGPT plan"),
        "agy-sub": ("Antigravity", "Your Antigravity plan"), "opencode-sub": ("OpenCode", "Your OpenCode login"),
        "anthropic": ("Anthropic", "Claude models"), "openai": ("OpenAI", "GPT models"),
        "google": ("Google Gemini", "Gemini models"), "gemini": ("Google Gemini", "Gemini models"),
        "openrouter": ("OpenRouter", "Many models"), "aimlapi": ("AIMLAPI", "Many models"),
        "groq": ("Groq", "Very fast models"), "deepseek": ("DeepSeek", "Low-cost models"),
        "mistral": ("Mistral", "European models"), "xai": ("xAI", "Grok models"), "apinex": ("APInex", "Many models"),
    ]
    /// The order of the Add cards, as in the approved mockup. Providers not listed follow in the Core's order.
    static let order = [
        "claude-sub", "codex-sub", "agy-sub", "opencode-sub", "anthropic", "openai", "google", "gemini", "openrouter",
        "aimlapi", "groq", "deepseek", "mistral", "xai", "apinex",
    ]

    static func kind(_ p: ProviderItem) -> ProviderKind {
        p.loginMethods.contains("browser_code") || p.id.hasSuffix("-sub") ? .subscription : .apiKey
    }
    static func name(_ id: String, fallback: String? = nil) -> String { faces[id]?.name ?? fallback ?? id }
    static func blurb(_ p: ProviderItem) -> String {
        faces[p.id]?.blurb ?? (kind(p) == .subscription ? "Your \(p.name) plan" : "\(p.name) models")
    }
    static func letter(_ name: String) -> String { name.first.map { String($0).uppercased() } ?? "?" }

    /// Providers of one kind in card order.
    static func cards(_ providers: [ProviderItem], _ kind: ProviderKind) -> [ProviderItem] {
        let mine = providers.filter { self.kind($0) == kind }
        let rank = { (p: ProviderItem) in order.firstIndex(of: p.id) ?? order.count }
        return mine.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// The Core's rule for a name, as `KeyEntryFlow.slug` has it (that one is main-actor only).
    static func slug(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        let ok = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(t.filter { ok.contains($0) })
    }

    /// A name the Core takes (`[a-z][a-z0-9._-]*`) that no account has: `anthropic`, then `anthropic-2`.
    static func label(for name: String, taken: Set<String>) -> String {
        let base = slug(name).isEmpty ? "account" : slug(name)
        let start = base.first.map { ("a"..."z").contains($0) } == true ? base : "a-\(base)"
        guard taken.contains(start) else { return start }
        var n = 2
        while taken.contains("\(start)-\(n)") { n += 1 }
        return "\(start)-\(n)"
    }
}

/// Moves in the list. All of them are whole-list answers, because the Core takes the whole list.
enum OrderMoves {
    static func moved(_ ids: [Int64], from: Int, to: Int) -> [Int64] {
        guard ids.indices.contains(from), from != to else { return ids }
        var r = ids
        let x = r.remove(at: from)
        r.insert(x, at: min(max(to, 0), r.count))
        return r
    }
    static func up(_ ids: [Int64], _ id: Int64) -> [Int64] {
        ids.firstIndex(of: id).map { moved(ids, from: $0, to: $0 - 1) } ?? ids
    }
    static func down(_ ids: [Int64], _ id: Int64) -> [Int64] {
        ids.firstIndex(of: id).map { moved(ids, from: $0, to: $0 + 1) } ?? ids
    }
    /// Where a row dragged `translation` points from `index` lands, `pitch` being one row plus its gap.
    static func dragTarget(from index: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return index }
        return min(max(index + Int((translation / pitch).rounded()), 0), count - 1)
    }
    /// A row not being dragged shifts by one slot to open the gap for the dragged one.
    static func shift(row: Int, dragged: Int, target: Int) -> Int {
        if row == dragged { return 0 }
        if dragged < target, row > dragged, row <= target { return -1 }
        if dragged > target, row < dragged, row >= target { return 1 }
        return 0
    }
}

enum OrderChip: Equatable, Sendable {
    case ready, inUse, limitHit, signingIn, off
    case needsLook(String)
}

enum OrderChips {
    /// States the Core may give an account that is still signing in.
    static let signing: Set<String> = ["signing_in", "pending", "login_pending"]

    /// The chip of an account from its verdict; `first` is true for the first usable one, the one in use now.
    static func chip(_ v: AccountVerdict, state: String, first: Bool) -> OrderChip {
        if signing.contains(state) { return .signingIn }
        switch v.kind {
        case .limitReached, .limited, .resting, .budgetStopped: return .limitHit
        case .turnedOff: return .off
        case .keyRefused, .unhealthy: return .needsLook(v.label)
        default: return first ? .inUse : .ready
        }
    }
    static func usable(_ c: OrderChip) -> Bool { c == .ready || c == .inUse }
    /// The first usable row is the one in use now.
    static func chips(_ rows: [(AccountVerdict, String)]) -> [OrderChip] {
        chips(rows.map { ($0.0, $0.1, false) })
    }
    /// As above, where the third value is the Core's own word that the row hit a limit (its meter's `limit_hit`).
    static func chips(_ rows: [(AccountVerdict, String, Bool)]) -> [OrderChip] {
        var seen = false
        return rows.map { v, s, hit in
            let c = hit && !signing.contains(s) ? OrderChip.limitHit : chip(v, state: s, first: !seen)
            if usable(c) { seen = true }
            return c
        }
    }
}

/// What a row says about use, in one sentence, and how full its meter is.
struct UsageFacts: Equatable, Sendable {
    var signing = false
    var limitHit = false
    var resetsAt: Date?
    /// 0...1+ of the tightest window of a plan or usage limit, and the window's length in seconds.
    var share: Double?
    var windowSecs: Int64?
    var monthSpendMicros: Int64?
    var monthLimitMicros: Int64?
    /// The Core's own meter (0.10): used of limit, in `unit` (`percent`, `usd_micros`, `messages` or `tokens`).
    var used: Double?
    var limit: Double?
    var unit: String?
}

enum UsageSentence {
    static func window(_ secs: Int64?) -> String {
        switch secs {
        case 18_000?: "these 5 hours"
        case 86_400?: "today"
        case 604_800?, nil: "this week"
        case 2_592_000?: "this month"
        default: "this period"
        }
    }
    static func dollars(_ micros: Int64) -> String {
        micros % 1_000_000 == 0 ? "$\(micros / 1_000_000)" : String(format: "$%.2f", Double(micros) / 1_000_000)
    }
    static func back(_ d: Date, tz: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "EEEE H:mm"
        return f.string(from: d)
    }

    static func of(_ f: UsageFacts, tz: TimeZone = .current) -> String {
        if f.signing { return "Finish signing in to use it" }
        if f.limitHit {
            let used = "Used all of \(window(f.windowSecs))"
            return f.resetsAt.map { "\(used). Back \(back($0, tz: tz))" } ?? "\(used). Waiting for it to reset"
        }
        if let u = f.unit, u != "percent", let used = f.used, let limit = f.limit, limit > 0 {
            let w = window(f.windowSecs)
            switch u {
            case "usd_micros": return "\(dollars(Int64(used))) of \(dollars(Int64(limit))) \(w)"
            case "messages": return "\(Int64(used).formatted()) of \(Int64(limit).formatted()) messages \(w)"
            default: return "\(AccountsNumbers.tokens(Int64(used))) of \(AccountsNumbers.tokens(Int64(limit))) \(w)"
            }
        }
        if let s = f.share { return "\(Int((s * 100).rounded()))% of \(window(f.windowSecs)) used" }
        if let spent = f.monthSpendMicros, let cap = f.monthLimitMicros, cap > 0 {
            return "\(dollars(spent)) of \(dollars(cap)) this month"
        }
        if let spent = f.monthSpendMicros, spent > 0 { return "\(dollars(spent)) this month" }
        return "No use yet this month"
    }

    /// 0...1 for the meter.
    static func meter(_ f: UsageFacts) -> Double {
        if f.limitHit { return 1 }
        if let s = f.share { return min(max(s, 0), 1) }
        if let spent = f.monthSpendMicros, let cap = f.monthLimitMicros, cap > 0 {
            return min(max(Double(spent) / Double(cap), 0), 1)
        }
        return 0
    }
}

/// The Add account steps: pick, then a key or a sign-in, then done. `checking` is the key's way through the Core.
struct AddStepper: Equatable, Sendable {
    enum Step: Equatable, Sendable { case pick, key, checking, signIn, done }
    private(set) var step = Step.pick
    /// 1, 2 or 3 of the three-step bar.
    var number: Int {
        switch step {
        case .pick: 1
        case .key, .checking, .signIn: 2
        case .done: 3
        }
    }
    mutating func choose(_ kind: ProviderKind) { if step == .pick { step = kind == .subscription ? .signIn : .key } }
    mutating func submitKey() { if step == .key { step = .checking } }
    /// The Core took the key and it works (`true`), or it did not and the key is asked for again.
    mutating func checked(ok: Bool) { if step == .checking { step = ok ? .done : .key } }
    mutating func signedIn() { if step == .signIn { step = .done } }
    mutating func back() { if [.key, .checking, .signIn].contains(step) { step = .pick } }
    mutating func again() { step = .pick }
}

/// The line under the key field while it is typed.
enum KeyShape {
    enum Live: Equatable {
        case empty
        case wrongPrefix(String)
        case looksValid
    }
    static func live(_ key: String, prefix: String?) -> Live {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.count < 8 { return .empty }
        if let prefix, !prefix.isEmpty, !k.hasPrefix(prefix) { return .wrongPrefix(prefix) }
        return .looksValid
    }
    static func words(_ l: Live) -> String {
        switch l {
        case .empty: "Paste your key. Core checks it as you type."
        case .wrongPrefix(let p): "This key should start with \(p)."
        case .looksValid: "Looks like a valid key"
        }
    }
}
